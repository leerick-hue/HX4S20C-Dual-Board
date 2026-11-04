"""Build a 320x240 (and 320x180) solid-colour HXJV fixture for tb_video_path.

The combined image keeps the original HXAU header/photos/PCM (first 8 sectors)
and replaces the embedded HXJV player with three solid-colour JPEG frames
(red, green, blue) at 30 fps. Golden hexes are uniform RGB565 words, so they are
exact regardless of IDCT rounding. audio_present=0 to keep the test focused on
the video/display path.
"""
import io
import struct
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ORIG = HERE / "combined.img"
COLORS = [(255, 0, 0), (0, 255, 0), (0, 0, 255)]
RGB565 = [0xF800, 0x07E0, 0x001F]


def jpeg_solid(rgb, w, h):
    im = Image.new("RGB", (w, h), rgb)
    buf = io.BytesIO()
    im.save(buf, format="JPEG", quality=75, subsampling=2, optimize=False, progressive=False)
    return buf.getvalue()


def build(height):
    width = 320
    frames = [jpeg_solid(c, width, height) for c in COLORS]
    sectors = []
    sectors.append(b"")  # placeholder for HXJV header
    index = []
    lba = 2
    for i, f in enumerate(frames):
        index.append((lba, len(f), i * 1600, 0))
        sectors.append(f.ljust((len(f) + 511) // 512 * 512, b"\x00"))
        lba += len(sectors[-1]) // 512
    index_bin = b"".join(struct.pack("<4I", *e) for e in index).ljust(512, b"\x00")
    total_sectors = 1 + 1 + sum(len(s) // 512 for s in sectors[1:])
    header = struct.pack(
        "<21I",
        0x564A5848, 1, 512, 0, width, height, 30, 1, len(frames), 1, 1, 2,
        0, 0, 48000, 2, 16, total_sectors, max(len(f) for f in frames),
        len(frames) * 1600, 16,
    ).ljust(512, b"\x00")
    player = header + index_bin + b"".join(sectors[1:])
    orig = ORIG.read_bytes()
    combined = orig[: 8 * 512] + player
    tag = "320x240" if height == 240 else "320x180"
    (HERE / f"combined_{tag}.img").write_bytes(combined)
    (HERE / f"fps30_{tag}.hex").write_text("".join(f"{b:02x}\n" for b in combined))
    for i, c in enumerate(RGB565):
        word = (c << 16) | c
        words = width * height // 2
        (HERE / f"video{i}_{tag}.hex").write_text("".join(f"{word:08x}\n" for _ in range(words)))
    print(tag, "combined bytes", len(combined), "sectors", len(combined) // 512,
          "frames", [len(f) for f in frames], "player_sectors", total_sectors)


if __name__ == "__main__":
    build(240)
    build(180)
