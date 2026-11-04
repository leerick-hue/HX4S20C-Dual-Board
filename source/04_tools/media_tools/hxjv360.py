"""Offline HXJV v1 JPEG/PCM card image tools. Never opens a physical device."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import wave
import zlib
from fractions import Fraction

from PIL import Image, ImageDraw

from jpeg_profile import ProfileError, inspect_jpeg

SECTOR = 512
MAGIC = b"HXJV"
VERSION = 1
WIDTH, HEIGHT = 640, 360
SAMPLE_RATE, CHANNELS, SAMPLE_BYTES = 48000, 2, 2
ENTRY = struct.Struct("<4I")
HEADER_FIELDS = (
    "version", "header_bytes", "flags", "width", "height", "fps_num", "fps_den",
    "frame_count", "index_lba", "index_sectors", "video_start_lba", "audio_start_lba",
    "audio_sample_frames", "sample_rate", "channels", "bits_per_sample", "total_sectors",
    "max_jpeg_bytes", "duration_pcm_samples", "index_entry_bytes",
)
HEADER = struct.Struct("<4s20I")
DEFAULT_BUDGET = 2_000_000  # decimal byte/s; a test budget, not measured TF speed


class MediaError(ValueError):
    pass


def sectors(n: int) -> int:
    return (n + SECTOR - 1) // SECTOR


def rate_value(value: str | int | Fraction) -> Fraction:
    try:
        rate = Fraction(value)
    except (ValueError, ZeroDivisionError) as e:
        raise MediaError("fps must be a positive integer or fraction") from e
    if not 0 < rate <= 60:
        raise MediaError("fps must be in (0, 60]")
    return rate


def pts_for_frame(index: int, fps: Fraction) -> int:
    return index * SAMPLE_RATE * fps.denominator // fps.numerator


def duration_samples(count: int, fps: Fraction) -> int:
    return (count * SAMPLE_RATE * fps.denominator + fps.numerator - 1) // fps.numerator


def serialize_header(values: dict) -> bytes:
    try:
        data = HEADER.pack(MAGIC, *(values[name] for name in HEADER_FIELDS))
    except struct.error as e:
        raise MediaError(f"header exceeds uint32 range: {e}") from e
    return data + bytes(SECTOR - len(data))


def _hash_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as src:
        for block in iter(lambda: src.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def _output_file(path: str | Path) -> Path:
    value = str(path).replace("\\", "/")
    if value.startswith(("//./", "//?/", "/dev/")):
        raise MediaError("output must be an ordinary .img file")
    p = Path(path).resolve()
    if p.suffix.lower() != ".img":
        raise MediaError("card image output must end with .img")
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


def wav_frames(path: Path) -> int:
    with wave.open(str(path), "rb") as source:
        if (source.getframerate(), source.getnchannels(), source.getsampwidth(), source.getcomptype()) != (
            SAMPLE_RATE, CHANNELS, SAMPLE_BYTES, "NONE"
        ):
            raise MediaError("audio WAV must be 48000 Hz stereo signed PCM16")
        return source.getnframes()


def bandwidth(entries: list[dict], header: dict, budget: int) -> dict:
    count = header["frame_count"]
    fps = Fraction(header["fps_num"], header["fps_den"])
    duration = header["duration_pcm_samples"] / SAMPLE_RATE
    audio_bytes = header["audio_sample_frames"] * CHANNELS * SAMPLE_BYTES
    audio_rate = audio_bytes / duration
    index_bytes = header["index_sectors"] * SECTOR
    frame_bytes = sum(e["sector_count"] * SECTOR for e in entries)
    max_jpeg = max(e["jpeg_bytes"] for e in entries)
    peak = max(e["sector_count"] * SECTOR * float(fps) + audio_rate for e in entries)
    average = (frame_bytes + audio_bytes + index_bytes) / duration
    return {
        "duration_seconds": duration,
        "frames_per_second": float(fps),
        "jpeg_payload_bytes": sum(e["jpeg_bytes"] for e in entries),
        "jpeg_average_bytes": sum(e["jpeg_bytes"] for e in entries) / count,
        "jpeg_max_bytes": max_jpeg,
        "video_sector_bytes": frame_bytes,
        "audio_bytes": audio_bytes,
        "audio_bytes_per_second": audio_rate,
        "index_bytes": index_bytes,
        "average_media_bytes_per_second": average,
        "peak_frame_interval_bytes_per_second": peak,
        "budget_bytes_per_second": budget,
        "average_within_budget": average <= budget,
        "every_frame_interval_within_budget": peak <= budget,
        "note": "Budget arithmetic includes sector padding and PCM, not CMD17/card stalls or measured hardware speed.",
    }


def pack_sequence(frames_dir: str | Path, output: str | Path, fps=30,
                  wav_path: str | Path | None = None, budget=DEFAULT_BUDGET) -> dict:
    """Pack sorted independent JPEGs; normalize optional PCM duration by truncation/zero padding."""
    folder = Path(frames_dir)
    files = sorted((p for p in folder.iterdir() if p.is_file() and p.suffix.lower() in (".jpg", ".jpeg")),
                   key=lambda p: p.name)
    if not files:
        raise MediaError("frame directory has no JPEG files")
    rate = rate_value(fps)
    samples = duration_samples(len(files), rate)
    index_sectors = sectors(len(files) * ENTRY.size)
    cursor = 1 + index_sectors
    entries = []
    for i, p in enumerate(files):
        data = p.read_bytes()
        profile = inspect_jpeg(data, WIDTH, HEIGHT)
        n = len(data)
        entries.append({"frame": i, "name": p.name, "start_lba": cursor, "jpeg_bytes": n,
                        "pts_pcm48k": pts_for_frame(i, rate), "jpeg_crc32": zlib.crc32(data),
                        "sector_count": sectors(n), "sha256": hashlib.sha256(data).hexdigest(),
                        "profile": profile})
        cursor += sectors(n)
    audio = Path(wav_path).resolve() if wav_path else None
    original_audio_samples = wav_frames(audio) if audio else 0
    audio_start = cursor if audio else 0
    audio_samples = samples if audio else 0
    total = cursor + sectors(audio_samples * 4)
    header = dict(zip(HEADER_FIELDS, (
        VERSION, SECTOR, int(audio is not None), WIDTH, HEIGHT, rate.numerator, rate.denominator,
        len(files), 1, index_sectors, 1 + index_sectors, audio_start, audio_samples, SAMPLE_RATE,
        CHANNELS, SAMPLE_BYTES * 8, total, max(e["jpeg_bytes"] for e in entries), samples, ENTRY.size,
    )))
    target = _output_file(output)
    if target in {p.resolve() for p in files} or target == audio:
        raise MediaError("output and source must differ")
    with target.open("wb") as sink:
        sink.write(serialize_header(header))
        for entry in entries:
            sink.write(ENTRY.pack(entry["start_lba"], entry["jpeg_bytes"],
                                  entry["pts_pcm48k"], entry["jpeg_crc32"]))
        sink.write(bytes(index_sectors * SECTOR - len(entries) * ENTRY.size))
        for p, entry in zip(files, entries):
            data = p.read_bytes()
            if hashlib.sha256(data).hexdigest() != entry["sha256"]:
                raise MediaError(f"input changed during packing: {p}")
            sink.write(data)
            sink.write(bytes((-len(data)) % SECTOR))
        if audio:
            with wave.open(str(audio), "rb") as source:
                left = audio_samples
                while left:
                    take = min(left, 16384)
                    block = source.readframes(take)
                    sink.write(block)
                    if len(block) < take * 4:
                        sink.write(bytes(take * 4 - len(block)))
                    left -= take
            sink.write(bytes((-audio_samples * 4) % SECTOR))
    report = {"format": "HXJV v1", "header": header, "frames": entries,
              "audio": {"path": str(audio) if audio else None,
                        "input_sample_frames": original_audio_samples,
                        "output_sample_frames": audio_samples,
                        "duration_adjustment": audio_samples - original_audio_samples if audio else 0},
              "bandwidth": bandwidth(entries, header, budget),
              "output": {"path": str(target), "size_bytes": target.stat().st_size,
                         "sha256": _hash_file(target)}}
    Path(str(target) + ".json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    return report


def inspect_image(path: str | Path, budget=DEFAULT_BUDGET, verify_profiles=True) -> dict:
    """Read/check every indexed JPEG without loading the whole card image into memory."""
    p = Path(path)
    with p.open("rb") as source:
        raw = source.read(SECTOR)
        if len(raw) != SECTOR:
            raise MediaError("truncated header")
        unpacked = HEADER.unpack_from(raw)
        if unpacked[0] != MAGIC:
            raise MediaError("not HXJV")
        h = dict(zip(HEADER_FIELDS, unpacked[1:]))
        if (h["version"], h["header_bytes"], h["index_entry_bytes"]) != (VERSION, SECTOR, ENTRY.size):
            raise MediaError("unsupported HXJV version/header/index entry size")
        if raw[HEADER.size:] != bytes(SECTOR - HEADER.size):
            raise MediaError("nonzero reserved header")
        rate = rate_value(Fraction(h["fps_num"], h["fps_den"]))
        if (h["width"], h["height"], h["sample_rate"], h["channels"], h["bits_per_sample"]) != (WIDTH, HEIGHT, 48000, 2, 16):
            raise MediaError("unsupported geometry/audio profile")
        count = h["frame_count"]
        if count == 0 or h["index_lba"] != 1 or h["index_sectors"] != sectors(count * ENTRY.size):
            raise MediaError("invalid frame index layout")
        if h["video_start_lba"] != 1 + h["index_sectors"]:
            raise MediaError("invalid video start")
        if h["total_sectors"] * SECTOR != p.stat().st_size:
            raise MediaError("image size/total_sectors mismatch")
        if h["duration_pcm_samples"] != duration_samples(count, rate):
            raise MediaError("duration/fps mismatch")
        entries = []
        cursor = h["video_start_lba"]
        for i in range(count):
            source.seek(SECTOR + i * ENTRY.size)
            record = source.read(ENTRY.size)
            if len(record) != ENTRY.size:
                raise MediaError("truncated frame directory")
            lba, n, pts, crc = ENTRY.unpack(record)
            if lba != cursor or n == 0 or lba + sectors(n) > h["total_sectors"]:
                raise MediaError(f"frame {i}: invalid LBA/length")
            if pts != pts_for_frame(i, rate):
                raise MediaError(f"frame {i}: incorrect timestamp")
            source.seek(lba * SECTOR)
            data = source.read(n)
            if len(data) != n or zlib.crc32(data) != crc:
                raise MediaError(f"frame {i}: CRC mismatch/truncated JPEG")
            if verify_profiles:
                inspect_jpeg(data, WIDTH, HEIGHT)
            padding = source.read((-n) % SECTOR)
            if padding != bytes((-n) % SECTOR):
                raise MediaError(f"frame {i}: nonzero padding")
            entries.append({"frame": i, "start_lba": lba, "jpeg_bytes": n,
                            "pts_pcm48k": pts, "jpeg_crc32": crc, "sector_count": sectors(n)})
            cursor += sectors(n)
        if h["max_jpeg_bytes"] != max(e["jpeg_bytes"] for e in entries):
            raise MediaError("max_jpeg_bytes mismatch")
        if h["flags"] == 1:
            if h["audio_start_lba"] != cursor or h["audio_sample_frames"] != h["duration_pcm_samples"]:
                raise MediaError("invalid PCM layout/duration")
            cursor += sectors(h["audio_sample_frames"] * 4)
        elif h["flags"] == 0:
            if h["audio_start_lba"] or h["audio_sample_frames"]:
                raise MediaError("audio fields present without PCM flag")
        else:
            raise MediaError("unsupported flags")
        if cursor != h["total_sectors"]:
            raise MediaError("unexpected gap/trailing sectors")
    return {"format": "HXJV v1", "header": h, "frames": entries,
            "bandwidth": bandwidth(entries, h, budget),
            "output": {"path": str(p.resolve()), "size_bytes": p.stat().st_size,
                       "sha256": _hash_file(p)}}


def encode_rgb(image: Image.Image, quality=75, max_bytes=50_000, min_quality=25) -> tuple[bytes, int]:
    """Choose the highest tested quality in [min_quality, quality] fitting max_bytes."""
    if not 1 <= min_quality <= quality <= 95 or max_bytes < 1024:
        raise MediaError("need 1<=min_quality<=quality<=95 and max_bytes>=1024")
    image = image.convert("RGB")
    if image.size != (WIDTH, HEIGHT):
        image = image.resize((WIDTH, HEIGHT), Image.Resampling.BICUBIC)
    def encode(q):
        b = io.BytesIO()
        image.save(b, format="JPEG", quality=q, subsampling=2, optimize=False, progressive=False)
        return b.getvalue()
    data = encode(quality)
    if len(data) <= max_bytes:
        return data, quality
    best = encode(min_quality)
    if len(best) > max_bytes:
        raise MediaError(f"frame still needs {len(best)} bytes at quality {min_quality}; exceeds {max_bytes}")
    chosen = min_quality
    low, high = min_quality + 1, quality - 1
    while low <= high:
        q = (low + high) // 2
        candidate = encode(q)
        if len(candidate) <= max_bytes:
            best, chosen, low = candidate, q, q + 1
        else:
            high = q - 1
    return best, chosen


def ffmpeg_path(explicit=None) -> str:
    found = explicit or shutil.which("ffmpeg")
    if not found:
        # Optional local wheel installation leaves the user's PATH untouched.
        binaries = Path(__file__).parent / "_deps" / "imageio_ffmpeg" / "binaries"
        candidates = list(binaries.glob("ffmpeg*.exe"))
        if candidates:
            found = str(candidates[0])
    if not found or not Path(found).is_file():
        raise MediaError("ffmpeg was not found; pass --ffmpeg FILE")
    return found


def encode_video(input_path, frames_dir, fps=30, quality=75, max_bytes=50_000,
                 min_quality=25, ffmpeg=None, limit_frames=0, stretch=False) -> dict:
    """ffmpeg decodes/resizes on the computer; Pillow emits fixed Huffman baseline420.

    By default the source aspect ratio is preserved and the 640x480 frame is
    padded with black bars, so non-4:3 videos are not stretched.
    """
    rate = rate_value(fps)
    target = Path(frames_dir)
    target.mkdir(parents=True, exist_ok=True)
    if any(p.suffix.lower() in (".jpg", ".jpeg") for p in target.iterdir()):
        raise MediaError("use an empty/new JPEG directory to avoid mixing clips")
    video_filter = f"fps={rate.numerator}/{rate.denominator},"
    if stretch:
        video_filter += f"scale={WIDTH}:{HEIGHT}:flags=bicubic"
    else:
        video_filter += (f"scale={WIDTH}:{HEIGHT}:force_original_aspect_ratio=decrease:flags=bicubic,"
                         f"pad={WIDTH}:{HEIGHT}:(ow-iw)/2:(oh-ih)/2:black")
    command = [ffmpeg_path(ffmpeg), "-hide_banner", "-nostdin", "-v", "error", "-i", str(input_path),
               "-map", "0:v:0", "-vf", video_filter,
               "-an", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"]
    if limit_frames:
        command[-1:-1] = ["-frames:v", str(limit_frames)]
    counts = []
    with tempfile.TemporaryFile() as errors:
        proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=errors)
        try:
            frame_size = WIDTH * HEIGHT * 3
            while True:
                data = bytearray()
                while len(data) < frame_size:
                    block = proc.stdout.read(frame_size - len(data))
                    if not block:
                        break
                    data.extend(block)
                if not data:
                    break
                if len(data) != frame_size:
                    raise MediaError("ffmpeg ended in the middle of a raw frame")
                jpeg, q = encode_rgb(Image.frombytes("RGB", (WIDTH, HEIGHT), bytes(data)), quality, max_bytes, min_quality)
                inspect_jpeg(jpeg, WIDTH, HEIGHT)
                index = len(counts)
                (target / f"frame_{index:08d}.jpg").write_bytes(jpeg)
                counts.append({"frame": index, "quality": q, "jpeg_bytes": len(jpeg)})
            code = proc.wait()
            if code:
                errors.seek(0)
                raise MediaError(f"ffmpeg failed ({code}): {errors.read().decode(errors='replace')[-3000:]}")
        finally:
            if proc.poll() is None:
                proc.terminate()
                proc.wait()
            proc.stdout.close()
    if not counts:
        raise MediaError("input produced no video frames")
    report = {"source": str(Path(input_path).resolve()), "fps_num": rate.numerator,
              "fps_den": rate.denominator, "width": WIDTH, "height": HEIGHT,
              "max_frame_bytes": max_bytes, "quality_range": [min_quality, quality], "frames": counts,
              "preserve_aspect": not stretch, "ffmpeg_command": command}
    (target / "encoding.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    return report


def demo_frames(folder: Path, count=60, fps=30) -> Path:
    """Generate our own moving test card; not a natural-video bandwidth guarantee."""
    folder.mkdir(parents=True, exist_ok=True)
    if any(p.suffix.lower() in (".jpg", ".jpeg") for p in folder.iterdir()):
        raise MediaError("use a new/empty demo frame directory to avoid leftover frames")
    for i in range(count):
        image = Image.new("RGB", (WIDTH, HEIGHT))
        d = ImageDraw.Draw(image)
        for y in range(0, HEIGHT, 16):
            for x in range(0, WIDTH, 16):
                d.rectangle((x, y, x + 15, y + 15), fill=((x // 3 + i * 3) % 256,
                             (y // 2 + i * 2) % 256, (x + y + i) % 256))
        x = (i * 11) % (WIDTH - 80)
        y = (i * 7) % (HEIGHT - 80)
        d.rectangle((x, y, x + 79, y + 79), fill="white", outline="black", width=4)
        d.text((16, 16), f"HXJV 640x480 frame {i:04d} / {count}  {fps} fps", fill="white",
               stroke_width=1, stroke_fill="black")
        jpeg, _ = encode_rgb(image)
        (folder / f"frame_{i:08d}.jpg").write_bytes(jpeg)
    samples = duration_samples(count, rate_value(fps))
    wav = folder / "demo.wav"
    with wave.open(str(wav), "wb") as out:
        out.setparams((2, 2, 48000, 0, "NONE", "not compressed"))
        for start in range(0, samples, 4800):
            data = bytearray()
            for n in range(start, min(start + 4800, samples)):
                envelope = .12 + .60 * (.5 + .5 * math.sin(2 * math.pi * n / 48000))
                left = round(26000 * envelope * math.sin(2 * math.pi * 440 * n / 48000))
                right = round(26000 * envelope * math.sin(2 * math.pi * 660 * n / 48000))
                data.extend(struct.pack("<hh", left, right))
            out.writeframes(data)
    return wav


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="action", required=True)
    pack = sub.add_parser("pack", help="Pack a JPEG sequence plus optional PCM WAV")
    pack.add_argument("--frames", required=True)
    pack.add_argument("--output", required=True)
    pack.add_argument("--fps", default="30")
    pack.add_argument("--wav")
    pack.add_argument("--budget", type=int, default=DEFAULT_BUDGET)
    verify = sub.add_parser("inspect", help="Verify header, all frame CRCs, timestamps and JPEG profile")
    verify.add_argument("image")
    encode = sub.add_parser("encode", help="Convert a source video to controlled baseline JPEG frames on the computer")
    encode.add_argument("input")
    encode.add_argument("--frames", required=True)
    encode.add_argument("--fps", default="30")
    encode.add_argument("--quality", type=int, default=75)
    encode.add_argument("--min-quality", type=int, default=25)
    encode.add_argument("--max-frame-bytes", type=int, default=50_000)
    encode.add_argument("--ffmpeg")
    encode.add_argument("--limit-frames", type=int, default=0)
    encode.add_argument("--stretch", action="store_true",
                        help="Stretch to 640x480 instead of preserving the source aspect ratio with black padding")
    demo = sub.add_parser("demo", help="Generate and pack an original moving test card with stereo PCM")
    demo.add_argument("--dir", required=True)
    demo.add_argument("--count", type=int, default=60)
    demo.add_argument("--fps", default="30")
    a = p.parse_args(argv)
    try:
        if a.action == "pack":
            r = pack_sequence(a.frames, a.output, a.fps, a.wav, a.budget)
        elif a.action == "inspect":
            r = inspect_image(a.image)
        elif a.action == "encode":
            r = encode_video(a.input, a.frames, a.fps, a.quality, a.max_frame_bytes,
                             a.min_quality, a.ffmpeg, a.limit_frames, a.stretch)
        else:
            if a.count < 1:
                raise MediaError("demo count must be positive")
            d = Path(a.dir)
            wav = demo_frames(d / "frames", a.count, a.fps)
            r = pack_sequence(d / "frames", d / "HXJV_DEMO.img", a.fps, wav)
        summary = {k: v for k, v in r.items() if k not in ("frames",)}
        summary["frame_count"] = len(r.get("frames", []))
        print(json.dumps(summary, indent=2))
        return 0
    except (MediaError, ProfileError, OSError, wave.Error, ValueError) as e:
        print(f"ERROR: {e}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
