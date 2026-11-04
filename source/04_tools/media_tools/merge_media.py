"""Merge an HXAU photo/PCM album image with an HXJV card image into one .img.

Combined layout is fixed: the album image leads, zero-padded to a 512-byte
sector boundary, and the HXJV image follows byte-for-byte at that sector.
Only album first-sector bytes 36..51 are rewritten (HXUV marker plus the
video_base_lba / video_sectors / combined_total_sectors triple); every other
album byte is preserved and no HXJV index or PCM LBA is rebased, because the
FPGA reads only the first 36 album bytes.  Never opens a physical device.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import zlib
from fractions import Fraction

import hxjv
from jpeg_profile import ProfileError, inspect_jpeg

SECTOR = hxjv.SECTOR
ENTRY = hxjv.ENTRY
HEADER = hxjv.HEADER
HEADER_FIELDS = hxjv.HEADER_FIELDS
MAGIC = b"HXAU"
PATCH_MAGIC = b"HXUV"
VIDEO_MAGIC = hxjv.MAGIC
ALBUM_HEADER = struct.Struct("<4s8I")
PATCH_SIZE = 16
OFFSET_PATCH = 36
OFFSET_VIDEO_BASE = 40
OFFSET_VIDEO_SECTORS = 44
OFFSET_TOTAL_SECTORS = 48
ALBUM_FIELDS = (
    "version", "sample_rate", "channels", "bits_per_sample", "audio_start_lba",
    "audio_sample_frames", "photo_end_sector_exclusive", "photo_count",
)
ALBUM_VERSION = 1
MIN_PHOTO_COUNT, MAX_PHOTO_COUNT = 1, 4
MIN_AUDIO_FRAMES = 128
CHANNEL_BYTES = 4
BMP_HEAD = 54
MAX_BMP_WIDTH, MAX_BMP_HEIGHT = 1920, 1080
MAX_JPEG_BYTES = 131072
MIN_JPEG_BYTES = 4
ALLOWED_FPS_NUMERATORS = (25, 30, 50, 60)
UINT32_MAX = 0xFFFFFFFF
CHUNK = 1 << 20
FORMAT = "HXAU+HXUV+HXJV"


class MediaError(ValueError):
    pass


def _u32(raw: bytes, offset: int) -> int:
    return struct.unpack_from("<I", raw, offset)[0]


def _s32(raw: bytes, offset: int) -> int:
    return struct.unpack_from("<i", raw, offset)[0]


def _input_file(path: str | Path, label: str) -> Path:
    value = str(path).replace("\\", "/")
    if value.startswith(("//./", "//?/", "/dev/")):
        raise MediaError(f"{label} must be an ordinary file, not a device path")
    p = Path(path)
    if not p.is_file():
        raise MediaError(f"{label} is not an existing file: {p}")
    return p.resolve()


class _Source:
    """Offset-addressed reader so large images are never copied or fully loaded."""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self._file = self.path.open("rb")
        self._file.seek(0, os.SEEK_END)
        self.size = self._file.tell()

    def __enter__(self) -> "_Source":
        return self

    def __exit__(self, *exc) -> None:
        self._file.close()

    def iterate(self, offset: int, length: int):
        return self._blocks(offset, length)

    def _blocks(self, offset: int, length: int):
        self._file.seek(offset)
        left = length
        while left:
            block = self._file.read(min(CHUNK, left))
            if not block:
                raise MediaError(
                    f"truncated: {self.path.name} needs {length} bytes at offset {offset}"
                )
            left -= len(block)
            yield block

    def read(self, offset: int, length: int) -> bytes:
        if length == 0:
            return b""
        return b"".join(self._blocks(offset, length))

    def sha256(self, offset: int, length: int) -> str:
        digest = hashlib.sha256()
        for block in self._blocks(offset, length):
            digest.update(block)
        return digest.hexdigest()


def _check_uint32(name: str, value: int) -> int:
    if not 0 <= value <= UINT32_MAX:
        raise MediaError(f"{name} does not fit a uint32 field: {value}")
    return value


# --------------------------------------------------------------------------- #
# HXAU album side
# --------------------------------------------------------------------------- #
def _parse_bmp(head: bytes, start_lba: int, limit_bytes: int, index: int) -> dict:
    if head[:2] != b"BM":
        raise MediaError(f"photo {index}: missing BM signature")
    size = _u32(head, 2)
    pixel_offset = _u32(head, 10)
    dib = _u32(head, 14)
    width = _s32(head, 18)
    height = _s32(head, 22)
    planes, bits = struct.unpack_from("<HH", head, 26)
    compression = _u32(head, 30)
    if size < BMP_HEAD:
        raise MediaError(f"photo {index}: BMP size {size} is below the 54-byte header")
    if dib < 40 or dib > 124:
        raise MediaError(f"photo {index}: DIB header {dib} bytes is smaller than 40")
    if compression != 0 or bits != 24 or planes != 1:
        raise MediaError(
            f"photo {index}: need uncompressed RGB24 planes=1, got planes={planes} "
            f"bits={bits} compression={compression}"
        )
    if not 1 <= width <= MAX_BMP_WIDTH:
        raise MediaError(f"photo {index}: width {width} is outside 1..{MAX_BMP_WIDTH}")
    if not 1 <= abs(height) <= MAX_BMP_HEIGHT:
        raise MediaError(
            f"photo {index}: height {height} magnitude is outside 1..{MAX_BMP_HEIGHT}"
        )
    stride = (width * 3 + 3) & ~3
    rows = abs(height)
    if pixel_offset < 14 + dib:
        raise MediaError(f"photo {index}: pixel offset {pixel_offset} overlaps the DIB header")
    if pixel_offset + stride * rows > size:
        raise MediaError(
            f"photo {index}: pixel data needs {pixel_offset + stride * rows} bytes, "
            f"BMP declares {size}"
        )
    if start_lba * SECTOR + size > limit_bytes:
        raise MediaError(
            f"photo {index}: {size} bytes at sector {start_lba} exceed the album region "
            f"limit of {limit_bytes} bytes"
        )
    return {
        "index": index,
        "start_lba": start_lba,
        "sector_count": hxjv.sectors(size),
        "size_bytes": size,
        "width": width,
        "height": height,
        "stride_bytes": stride,
        "pixel_offset": pixel_offset,
        "dib_bytes": dib,
        "planes": planes,
        "bits_per_sample": bits,
        "compression": compression,
    }


def _read_photos(src: _Source, count: int, photo_end: int, limit_bytes: int) -> list[dict]:
    cursor = 1
    photos = []
    for index in range(count):
        if cursor >= photo_end:
            raise MediaError(
                f"photo {index}: no room before photo_end_sector_exclusive {photo_end}"
            )
        head = src.read(cursor * SECTOR, BMP_HEAD)
        photo = _parse_bmp(head, cursor, min(limit_bytes, photo_end * SECTOR), index)
        photo["sha256"] = src.sha256(cursor * SECTOR, photo["size_bytes"])
        photos.append(photo)
        cursor += photo["sector_count"]
    if cursor > photo_end:
        raise MediaError(
            f"photo {count - 1}: region ends at sector {cursor}, past "
            f"photo_end_sector_exclusive {photo_end}"
        )
    if cursor != photo_end:
        raise MediaError(
            f"photo scan ends at sector {cursor}, but photo_end_sector_exclusive is {photo_end}"
        )
    return photos


def _read_album(src: _Source, *, combined: bool) -> dict:
    raw = src.read(0, SECTOR)
    fields = ALBUM_HEADER.unpack_from(raw)
    if fields[0] != MAGIC:
        raise MediaError("album header magic is not HXAU")
    header = dict(zip(ALBUM_FIELDS, fields[1:]))
    if (header["version"], header["sample_rate"], header["channels"],
            header["bits_per_sample"]) != (ALBUM_VERSION, 48000, 2, 16):
        raise MediaError(
            "unsupported HXAU profile: need version 1 with 48000 Hz stereo 16-bit PCM"
        )
    count = header["photo_count"]
    if not MIN_PHOTO_COUNT <= count <= MAX_PHOTO_COUNT:
        raise MediaError(f"photo_count {count} is outside {MIN_PHOTO_COUNT}..{MAX_PHOTO_COUNT}")
    photo_end = header["photo_end_sector_exclusive"]
    audio_start = header["audio_start_lba"]
    frames = header["audio_sample_frames"]
    if photo_end <= 1:
        raise MediaError(f"photo_end_sector_exclusive {photo_end} must exceed sector 1")
    if frames and audio_start < photo_end:
        raise MediaError(f"audio_start_lba {audio_start} overlaps the photo region")
    if frames and frames < MIN_AUDIO_FRAMES:
        raise MediaError(f"audio_sample_frames {frames} is below {MIN_AUDIO_FRAMES}")
    old_total = None
    if combined:
        if raw[OFFSET_PATCH:OFFSET_PATCH + 4] != PATCH_MAGIC:
            raise MediaError(f"album sector byte {OFFSET_PATCH} is not an HXUV marker")
        base, video_sectors, total = struct.unpack_from("<3I", raw, OFFSET_VIDEO_BASE)
        if base < 1:
            raise MediaError("video_base_lba must be positive")
    else:
        old_total = _u32(raw, OFFSET_PATCH)
        base = hxjv.sectors(src.size)
        video_sectors, total = None, None
        if old_total != base:
            raise MediaError(
                f"album total_image_sectors {old_total} != ceil(file bytes/512) = {base}"
            )
    pcm_bytes = frames * CHANNEL_BYTES
    pcm_end = audio_start * SECTOR + pcm_bytes
    if pcm_end > base * SECTOR:
        raise MediaError(
            f"album PCM ends at byte {pcm_end}, which overlaps video_base_lba sector {base}"
        )
    if pcm_end > src.size:
        raise MediaError(f"album PCM ends at byte {pcm_end}, past the {src.size}-byte file")
    photos = _read_photos(src, count, photo_end, base * SECTOR)
    audio = {
        "start_lba": audio_start,
        "sample_frames": frames,
        "bytes": pcm_bytes,
        "sector_count": hxjv.sectors(pcm_bytes),
        "end_byte": pcm_end,
        "sha256": src.sha256(audio_start * SECTOR, pcm_bytes),
    }
    return {
        "header": header,
        "photos": photos,
        "audio": audio,
        "video_base_lba": base,
        "video_sectors": video_sectors,
        "combined_total_sectors": total,
        "album_total_image_sectors": old_total,
        "header_bytes": raw[:OFFSET_PATCH],
    }


def _profile_guard(func):
    """Keep ProfileError an internal detail: the public API raises MediaError."""
    def wrapped(*args, **kwargs):
        try:
            return func(*args, **kwargs)
        except ProfileError as exc:
            raise MediaError(f"JPEG profile check failed: {exc}") from exc
    wrapped.__name__ = func.__name__
    wrapped.__doc__ = func.__doc__
    return wrapped


# --------------------------------------------------------------------------- #
# HXJV video side, addressed relative to a base sector
# --------------------------------------------------------------------------- #
@_profile_guard
def _read_video(src: _Source, base: int, segment_sectors: int, verify_profiles=True,
                report_base=None) -> dict:
    raw = src.read(base * SECTOR, SECTOR)
    fields = HEADER.unpack_from(raw)
    if fields[0] != VIDEO_MAGIC:
        raise MediaError(f"sector {base} does not start with an HXJV header")
    header = dict(zip(HEADER_FIELDS, fields[1:]))
    if (header["version"], header["header_bytes"], header["index_entry_bytes"]) != (
            hxjv.VERSION, SECTOR, ENTRY.size):
        raise MediaError("unsupported HXJV version/header/index entry size")
    if raw[HEADER.size:] != bytes(SECTOR - HEADER.size):
        raise MediaError("nonzero reserved header bytes in the HXJV image")
    if (header["width"], header["height"], header["sample_rate"], header["channels"],
            header["bits_per_sample"]) != (hxjv.WIDTH, hxjv.HEIGHT, 48000, 2, 16):
        raise MediaError("unsupported HXJV geometry/audio profile")
    if header["flags"] not in (0, 1):
        raise MediaError(f"unsupported HXJV flags {header['flags']}")
    if header["fps_den"] != 1 or header["fps_num"] not in ALLOWED_FPS_NUMERATORS:
        raise MediaError(
            f"combined images need integer 25 or 30 fps, got {header['fps_num']}/"
            f"{header['fps_den']}"
        )
    rate = Fraction(header["fps_num"], header["fps_den"])
    count = header["frame_count"]
    if count <= 0:
        raise MediaError("HXJV frame_count must be positive")
    if header["index_lba"] != 1 or header["index_sectors"] != hxjv.sectors(count * ENTRY.size):
        raise MediaError("invalid HXJV frame index layout")
    if header["video_start_lba"] != 1 + header["index_sectors"]:
        raise MediaError("invalid HXJV video start")
    if header["duration_pcm_samples"] != hxjv.duration_samples(count, rate):
        raise MediaError("HXJV duration/fps mismatch")
    total = header["total_sectors"]
    if total != segment_sectors:
        raise MediaError(
            f"HXJV total_sectors {total} != the {segment_sectors}-byte-sector video segment"
        )
    index_pad = header["index_sectors"] * SECTOR - count * ENTRY.size
    if index_pad and src.read((base + 1) * SECTOR + count * ENTRY.size, index_pad) != bytes(index_pad):
        raise MediaError("nonzero HXJV index reserve")
    frames = []
    cursor = header["video_start_lba"]
    for index in range(count):
        lba, size, pts, crc = ENTRY.unpack(src.read((base + 1) * SECTOR + index * ENTRY.size,
                                                    ENTRY.size))
        if size < MIN_JPEG_BYTES:
            raise MediaError(f"frame {index}: JPEG length {size} is implausibly small")
        if size > MAX_JPEG_BYTES:
            raise MediaError(f"frame {index}: JPEG length {size} exceeds {MAX_JPEG_BYTES}")
        if lba != cursor or lba + hxjv.sectors(size) > total:
            raise MediaError(
                f"frame {index}: LBA {lba} is not contiguous (expected {cursor}) or runs "
                f"past total_sectors {total}"
            )
        if pts != hxjv.pts_for_frame(index, rate):
            raise MediaError(f"frame {index}: incorrect 48 kHz timestamp {pts}")
        offset = (base + lba) * SECTOR
        data = src.read(offset, size)
        if zlib.crc32(data) != crc:
            raise MediaError(f"frame {index}: CRC mismatch")
        if verify_profiles:
            inspect_jpeg(data, hxjv.WIDTH, hxjv.HEIGHT)
        pad = (-size) % SECTOR
        if pad and src.read(offset + size, pad) != bytes(pad):
            raise MediaError(f"frame {index}: nonzero sector padding")
        frames.append({"frame": index, "start_lba": lba, "jpeg_bytes": size,
                       "pts_pcm48k": pts, "jpeg_crc32": crc,
                       "sector_count": hxjv.sectors(size)})
        cursor += hxjv.sectors(size)
    if header["max_jpeg_bytes"] != max(f["jpeg_bytes"] for f in frames):
        raise MediaError("HXJV max_jpeg_bytes mismatch")
    if header["flags"] == 1:
        if header["audio_start_lba"] != cursor:
            raise MediaError("HXJV audio_start_lba does not follow the last frame")
        if header["audio_sample_frames"] != header["duration_pcm_samples"]:
            raise MediaError("HXJV PCM length does not match the video duration")
        pcm_bytes = header["audio_sample_frames"] * CHANNEL_BYTES
        audio = {"start_lba": cursor, "sample_frames": header["audio_sample_frames"],
                 "bytes": pcm_bytes, "sector_count": hxjv.sectors(pcm_bytes),
                 "sha256": src.sha256((base + cursor) * SECTOR, pcm_bytes)}
        cursor += hxjv.sectors(pcm_bytes)
    else:
        if header["audio_start_lba"] or header["audio_sample_frames"]:
            raise MediaError("HXJV audio fields present without the PCM flag")
        audio = {"start_lba": 0, "sample_frames": 0, "bytes": 0, "sector_count": 0,
                 "sha256": None}
    if cursor != total:
        raise MediaError(f"HXJV layout ends at sector {cursor}, expected total_sectors {total}")
    return {
        "format": "HXJV v1",
        "header": header,
        "fps": f"{header['fps_num']}/{header['fps_den']}",
        "frame_count": count,
        "frames": frames,
        "audio": audio,
        "segment": {
            "base_lba": base,
            "start_byte": base * SECTOR,
            "sectors": total,
            "bytes": total * SECTOR,
            "sha256": src.sha256(base * SECTOR, total * SECTOR),
        },
    }


def _video_input_sectors(size: int) -> int:
    if size % SECTOR:
        raise MediaError(f"video image size {size} is not a whole number of 512-byte sectors")
    return size // SECTOR


def _build_patch(base: int, video_sectors: int, total: int) -> bytes:
    return PATCH_MAGIC + struct.pack(
        "<3I", _check_uint32("video_base_lba", base),
        _check_uint32("video_sectors", video_sectors),
        _check_uint32("combined_total_sectors", total),
    )


def _layout(album: dict, video: dict, album_bytes: int | None) -> dict:
    base = album["video_base_lba"]
    sectors = video["segment"]["sectors"]
    return {
        "sector_bytes": SECTOR,
        "album_source_bytes": album_bytes,
        "album_sectors": base,
        "album_padding_bytes": None if album_bytes is None else base * SECTOR - album_bytes,
        "video_base_lba": base,
        "video_base_offset_bytes": base * SECTOR,
        "video_sectors": sectors,
        "combined_total_sectors": base + sectors,
        "album_video_sectors_field": album["video_sectors"],
        "album_total_sectors_field": album["combined_total_sectors"],
        "album_header_retained_bytes": OFFSET_PATCH,
        "album_bytes_replaced": {"offset": OFFSET_PATCH, "length": PATCH_SIZE},
        "album_untouched_from_byte": OFFSET_PATCH + PATCH_SIZE,
        "patch_field_offsets_bytes": {"HXUV": OFFSET_PATCH, "video_base_lba": OFFSET_VIDEO_BASE,
                                      "video_sectors": OFFSET_VIDEO_SECTORS,
                                      "combined_total_sectors": OFFSET_TOTAL_SECTORS},
    }


# --------------------------------------------------------------------------- #
# Public API
# --------------------------------------------------------------------------- #
def pack_images(album_path: str | Path, video_path: str | Path,
                output_path: str | Path) -> dict:
    """Append an HXJV image to an HXAU album image and stamp the HXUV sector fields."""
    album_src = _input_file(album_path, "album image")
    video_src = _input_file(video_path, "video image")
    target = hxjv._output_file(output_path)
    if target in (album_src, video_src):
        raise MediaError("output and source must differ")
    album_sha = hxjv._hash_file(album_src)
    video_sha = hxjv._hash_file(video_src)
    with _Source(album_src) as album_file, _Source(video_src) as video_file:
        album = _read_album(album_file, combined=False)
        base = album["video_base_lba"]
        video_sectors = _video_input_sectors(video_file.size)
        video = _read_video(video_file, 0, video_sectors)
        total = base + video_sectors
        if total > 4194304:
            raise MediaError("combined image exceeds the 2GiB catalog limit")
        album["video_sectors"], album["combined_total_sectors"] = video_sectors, total
        patch = _build_patch(base, video_sectors, total)
        if patch != bytes(PATCH_SIZE):
            album_sector = bytearray(album_file.read(0, SECTOR))
            album_sector[OFFSET_PATCH:OFFSET_PATCH + PATCH_SIZE] = patch
        else:
            album_sector = bytearray(album_file.read(0, SECTOR))
        padding = base * SECTOR - album_file.size
        segment_sha = hashlib.sha256()
        with target.open("wb") as sink:
            sink.write(bytes(album_sector))
            for block in album_file._blocks(SECTOR, album_file.size - SECTOR):
                sink.write(block)
            sink.write(bytes(padding))
            for block in video_file._blocks(0, video_file.size):
                segment_sha.update(block)
                sink.write(block)
    size = target.stat().st_size
    if size != total * SECTOR:
        raise MediaError(f"wrote {size} bytes, expected {total * SECTOR}")
    if segment_sha.hexdigest() != video["segment"]["sha256"]:
        raise MediaError("video image changed while it was being copied")
    video["segment"]["base_lba"] = base
    video["segment"]["start_byte"] = base * SECTOR
    with _Source(target) as packed:
        album_segment = {"base_lba":0,"sectors":base,"bytes":base*SECTOR,"sha256":packed.sha256(0,base*SECTOR)}
    report = {
        "format": FORMAT,
        "layout": _layout(album, video, album_file.size),
        "album": {"segment": album_segment,"header": album["header"], "photos": album["photos"],
                  "audio": album["audio"],
                  "replaced_total_image_sectors": album["album_total_image_sectors"]},
        "video": video,
        "sources": {
            "album": {"path": str(album_src), "size_bytes": album_file.size,
                      "sha256": album_sha},
            "video": {"path": str(video_src), "size_bytes": video_file.size,
                      "sha256": video_sha},
        },
        "output": {"path": str(target), "size_bytes": size,
                   "video_segment_sha256": segment_sha.hexdigest(),
                   "sha256": hxjv._hash_file(target)},
    }
    Path(str(target) + ".json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    return report


def inspect_image(path: str | Path, *, verify_profiles=True) -> dict:
    """Verify a combined HXAU+HXUV+HXJV image in place, without copying it."""
    source = _input_file(path, "card image")
    with _Source(source) as src:
        album = _read_album(src, combined=True)
        base = album["video_base_lba"]
        video_sectors = album["video_sectors"]
        total = album["combined_total_sectors"]
        if total != base + video_sectors:
            raise MediaError(
                f"combined_total_sectors {total} != video_base_lba {base} + video_sectors "
                f"{video_sectors}"
            )
        if src.size != total * SECTOR:
            raise MediaError(
                f"image is {src.size} bytes, but combined_total_sectors {total} needs "
                f"{total * SECTOR}"
            )
        video = _read_video(src, base, video_sectors, verify_profiles=verify_profiles)
        report = {
            "format": FORMAT,
            "layout": _layout(album, video, None),
            "album": {"segment":{"base_lba":0,"sectors":base,"bytes":base*SECTOR,"sha256":src.sha256(0,base*SECTOR)},"header": album["header"], "photos": album["photos"],
                      "audio": album["audio"],
                      "replaced_total_image_sectors": None},
            "video": video,
            "output": {"path": str(source), "size_bytes": src.size,
                       "video_segment_sha256": video["segment"]["sha256"],
                       "sha256": hxjv._hash_file(source)},
        }
    return report


def _summary(report: dict) -> dict:
    album = dict(report["album"])
    album["photos"] = len(album["photos"])
    video = {k: v for k, v in report["video"].items() if k != "frames"}
    video["frames_omitted"] = len(report["video"]["frames"])
    video.pop("frames", None)
    summary = dict(report)
    summary["album"] = album
    summary["video"] = video
    return summary


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    pack = sub.add_parser("pack", help="Merge an HXAU album image with an HXJV video image")
    pack.add_argument("--album", required=True, help="HXAU album .img input")
    pack.add_argument("--video", required=True, help="HXJV video .img input")
    pack.add_argument("--output", required=True, help="combined ordinary .img output")
    verify = sub.add_parser("inspect", help="Verify a combined HXAU+HXUV+HXJV image")
    verify.add_argument("image", help="combined .img to verify")
    args = parser.parse_args(argv)
    try:
        if args.action == "pack":
            report = pack_images(args.album, args.video, args.output)
        else:
            report = inspect_image(args.image)
    except (MediaError, ProfileError, OSError, ValueError) as exc:
        print(f"ERROR: {exc}")
        return 2
    print(json.dumps(_summary(report), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
