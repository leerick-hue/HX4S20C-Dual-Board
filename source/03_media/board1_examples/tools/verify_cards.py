"""Independent offline validator for the three .img card images under DELIVERY.

Raw struct-based parsers only (no hxjv / pack_tf_audio imports), no device access.
Writes reports/INDEPENDENT_VALIDATION.json; exits nonzero on any check failure.
"""
import hashlib
import json
import math
import struct
import sys
import traceback
import zlib
from io import BytesIO
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from jpeg_profile import inspect_jpeg  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SECTOR = 512


def fail(msg):
    raise ValueError(msg)


def check(value, expected, what):
    if value != expected:
        fail("%s: got %r, expected %r" % (what, value, expected))


def bmp_layout(blob):
    """Validate a BMP header per format spec; return (filesize, stride*rows+pix)."""
    if len(blob) < 54 or blob[:2] != b"BM":
        fail("not a BMP (missing BM or truncated)")
    file_size = int.from_bytes(blob[2:6], "little")
    pix_off = int.from_bytes(blob[10:14], "little")
    hdr, w, h, planes, bits, comp = struct.unpack_from("<IiiHHI", blob, 14)
    check(hdr, 40, "DIB header size")
    check(planes, 1, "BMP planes")
    check(bits, 24, "BMP bits per pixel")
    check(comp, 0, "BMP compression")
    if not 1 <= w <= 1920 or not 1 <= abs(h) <= 1080:
        fail("BMP dimensions out of range: %dx%d" % (w, h))
    stride = (w * 3 + 3) & ~3
    expected_size = stride * abs(h) + pix_off
    check(file_size, expected_size, "BMP filesize vs stride*rows+pixoffset")
    check(len(blob), file_size, "BMP read length vs declared filesize")


def verify_album(data, bmp_dir):
    magic, ver, rate, chans, bits, audio_start, audio_frames, photo_end, count, total = \
        struct.unpack_from("<4s9I", data, 0)
    check(magic, b"HXAU", "album magic")
    check((ver, rate, chans, bits, count), (1, 48000, 2, 16, 4),
          "album (version,sample_rate,channels,bits,photo_count)")
    check(total * SECTOR, len(data), "album total_sectors*512 vs file size")
    lba = 1
    photos = []
    for i in range(count):
        off = lba * SECTOR
        file_size = int.from_bytes(data[off + 2:off + 6], "little")
        blob = data[off:off + file_size]
        bmp_layout(blob)
        photos.append(blob)
        lba += (file_size + SECTOR - 1) // SECTOR
    check(lba, audio_start, "final photo end vs audio_start_lba")
    check(photo_end, audio_start, "photo_end_lba vs audio_start_lba")
    audio_end = audio_start * SECTOR + audio_frames * 4
    if audio_end > len(data):
        fail("audio end %d exceeds image length %d" % (audio_end, len(data)))
    for i, blob in enumerate(photos):
        ref_path = ROOT / bmp_dir / ("%04d.BMP" % (i + 1))
        with Image.open(ref_path) as ref_img:
            embedded = Image.open(BytesIO(blob))
            if embedded.size != ref_img.size or embedded.mode != ref_img.mode:
                fail("photo %d mode/size differs from %s" % (i + 1, ref_path.name))
            if embedded.convert("RGB").tobytes() != ref_img.convert("RGB").tobytes():
                fail("photo %d pixels differ from %s" % (i + 1, ref_path.name))
            embedded.close()
    return {"photo_count": count, "audio_frames": audio_frames,
            "audio_start_lba": audio_start, "total_sectors": total}


def verify_video(data):
    check(data[:4], b"HXAU", "video file magic")
    check(data[36:40], b"HXUV", "HXUV sub-header at offset 36")
    vbase, vsect, total = struct.unpack_from("<3I", data, 40)
    check(total * SECTOR, len(data), "video total_sectors*512 vs file size")
    if vbase + vsect > total:
        fail("video region exceeds image")
    v = data[vbase * SECTOR:(vbase + vsect) * SECTOR]
    fields = struct.unpack_from("<4s20I", v, 0)
    (magic, ver, hdr_bytes, flags, w, h, fps_n, fps_d, frames, index_lba, index_sectors,
     video_start_lba, _, audio_sample_frames, sample_rate, chans, bits,
     v_total_sectors, max_jpeg_bytes, duration, index_entry_bytes) = fields
    check(magic, b"HXJV", "embedded video magic")
    check((ver, hdr_bytes, flags, w, h, fps_n, fps_d, index_entry_bytes),
          (1, 512, 0, 320, 240, 25, 1, 16),
          "HXJV (version,header_bytes,flags,width,height,fps,index_entry_bytes)")
    check((sample_rate, chans, bits), (48000, 2, 16), "HXJV audio format")
    check(v_total_sectors, vsect, "HXJV total_sectors vs HXUV video_sectors")
    check(vbase+vsect,total,"video region fills combined image")
    check(audio_sample_frames,0,"silent video audio frames")
    if frames <= 0:fail("empty video")
    check(duration,frames*1920,"frame-count duration")
    check(index_lba,1,"index LBA")
    check(index_sectors,(frames*16+511)//512,"index sector count")
    check(video_start_lba,1+index_sectors,"video payload start")
    idx_off = index_lba * SECTOR
    if idx_off + frames * index_entry_bytes > len(v):
        fail("index table exceeds embedded video")
    prev_end = video_start_lba
    for i in range(frames):
        start, jpeg_bytes, pts, crc = struct.unpack_from("<4I", v, idx_off + i * 16)
        sectors=(jpeg_bytes+511)//512
        check(start,prev_end,"contiguous frame extent")
        if start < prev_end:
            fail("frame %d overlaps or is unsorted (start %d < %d)" % (i, start, prev_end))
        if start < video_start_lba:
            fail("frame %d start %d below video_start_lba %d" % (i, start, video_start_lba))
        if jpeg_bytes > sectors * SECTOR or jpeg_bytes > max_jpeg_bytes:
            fail("frame %d size exceeds its sectors or max_jpeg_bytes" % i)
        if jpeg_bytes > 20000:
            fail("frame %d jpeg_bytes %d exceeds 20000" % (i, jpeg_bytes))
        if start + sectors > vsect:
            fail("frame %d extent exceeds embedded video" % i)
        check(pts, i * 1920, "frame %d pts at 48000 Hz" % i)
        jpeg = v[start * SECTOR:start * SECTOR + jpeg_bytes]
        check(zlib.crc32(jpeg),crc,"JPEG CRC32")
        if jpeg[:2] != b"\xff\xd8" or jpeg[-2:] != b"\xff\xd9":
            fail("frame %d missing JPEG SOI/EOI" % i)
        img = Image.open(BytesIO(jpeg))
        check(img.size, (w, h), "frame %d decoded size" % i)
        img.load()
        img.close()
        inspect_jpeg(jpeg,w,h)
        prev_end = start + sectors
    check(prev_end,vsect,"end of video payload")
    return {"frame_count": frames, "video_base_lba": vbase, "video_sectors": vsect,
            "audio_sample_frames": audio_sample_frames, "total_sectors": total}


def main():
    images = sorted((ROOT / "DELIVERY").glob("*.img"))
    if len(images) != 3:
        fail("expected exactly 3 .img files under DELIVERY, found %d" % len(images))
    for path, prefix in zip(images, ("01", "02", "03")):
        if not path.name.startswith(prefix):
            fail("unexpected card order/name %s (expected prefix %s)" % (path.name, prefix))
    checks, passed = [], True
    for path in images:
        record = {"file": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        data = path.read_bytes()
        try:
            record["counts"] = (verify_video(data) if path.name.startswith("03")
                                else verify_album(data, "album1_bmp" if path.name.startswith("01") else "album2_bmp"))
            record["ok"] = True
        except Exception as exc:  # fail closed per file
            record["ok"] = False
            record["error"] = "%s: %s" % (type(exc).__name__, exc)
            traceback.print_exc()
        passed = passed and record["ok"]
        checks.append(record)
    report = {"passed": passed, "files": checks,
              "note": "offline structural/pixel validation only; no hardware tested"}
    out = ROOT / "reports" / "INDEPENDENT_VALIDATION.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("passed" if passed else "FAILED", "->", out)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
