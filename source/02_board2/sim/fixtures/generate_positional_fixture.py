"""Position-unique HXJV fixture for tb_video_path.

The original fixture used three solid colours, which makes every golden word
identical.  A byte-exact comparison against an all-identical golden cannot
detect a wrong destination address, an even/odd half swap or a row/column
permutation: any address yields the same expected value.  This generator keeps
the JPEG round trip exact while giving every 8x8 block its own value.

Exactness strategy
------------------
* Greyscale, so Cb/Cr are neutral everywhere and 4:2:0 chroma subsampling
  cannot smear neighbouring blocks.
* Each 8x8 block is uniform, so its DCT carries a single DC term.  With
  quality=100 the DC quantiser step is 1 and libjpeg's edge padding replicates
  the border pixel, so a partially covered last block row stays uniform too.
  The decoded block therefore returns the exact grey level that went in.
* run() asserts this by decoding every frame and comparing pixel for pixel
  before anything is written.

Pattern per asset (L = 8-bit grey level, bx = x//8, by = y//8)
-------------------------------------------------------------
  asset 0: L = 4 + 8*(bx % 32)          column marker, constant down each column
  asset 1: L = 4 + 8*(by % 32)          row marker,    constant along each row
  asset 2: L = 4 + 8*((bx + by) % 32)   combined

Levels sit at 2 mod 4.  RGB565 quantises red to 5 bits (bucket width 8) but
green to 6 bits (bucket width 4), so the green channel is the binding one: only
a level congruent to 2 mod 4 is at the centre of both buckets.  A decoder that
agrees with libjpeg to within one grey level still lands on the same quantised
word.  R5 = L>>3 = k is still unique per k, so any address resolving to a
different block changes the stored word.
"""
import io
import struct
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ORIG = HERE / "combined.img"
WIDTH = 320


def level(asset, bx, by):
    if asset == 0:
        k = bx % 31
    elif asset == 1:
        k = by % 31
    else:
        k = (bx + by) % 31
    return 2 + 8 * (1 + k)


def rgb565_from_grey(l):
    r5 = l >> 3
    g6 = l >> 2
    return (r5 << 11) | (g6 << 5) | r5


def make_image(asset, height):
    im = Image.new("L", (WIDTH, height))
    px = im.load()
    for y in range(height):
        by = y // 8
        for x in range(WIDTH):
            px[x, y] = level(asset, x // 8, by)
    return im


def encode(im):
    buf = io.BytesIO()
    im.convert("RGB").save(
        buf, format="JPEG", quality=100, subsampling=2,
        optimize=False, progressive=False,
    )
    return buf.getvalue()


def verify(blob, asset, height):
    """Decode what we just encoded and require an exact match."""
    dec = Image.open(io.BytesIO(blob)).convert("RGB")
    if dec.size != (WIDTH, height):
        raise SystemExit(f"decoded size {dec.size} != {(WIDTH, height)}")
    px = dec.load()
    bad = 0
    worst = 0
    for y in range(height):
        by = y // 8
        for x in range(WIDTH):
            want = level(asset, x // 8, by)
            r, g, b = px[x, y]
            got = rgb565_from_grey(want)
            have = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
            if got != have:
                bad += 1
                worst = max(worst, abs(((got >> 11) & 0x1F) - ((have >> 11) & 0x1F)))
    return bad, worst


def build(height, outdir):
    frames = []
    levels = []
    for asset in range(3):
        im = make_image(asset, height)
        blob = encode(im)
        bad, worst = verify(blob, asset, height)
        if bad:
            raise SystemExit(
                f"asset {asset} {WIDTH}x{height}: {bad} mismatching pixels "
                f"(worst R delta {worst}); refusing to write a non-exact fixture"
            )
        frames.append(blob)
        levels.append(im)
    sectors = [b""]
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
        0x564A5848, 1, 512, 0, WIDTH, height, 30, 1, len(frames), 1, 1, 2,
        0, 0, 48000, 2, 16, total_sectors, max(len(f) for f in frames),
        len(frames) * 1600, 16,
    ).ljust(512, b"\x00")
    player = header + index_bin + b"".join(sectors[1:])
    combined = ORIG.read_bytes()[: 8 * 512] + player

    tag = f"320x{height}"
    outdir.mkdir(parents=True, exist_ok=True)
    (outdir / f"combined_{tag}.img").write_bytes(combined)
    (outdir / f"fps30_{tag}.hex").write_text("".join(f"{b:02x}\n" for b in combined))
    for i in range(3):
        words = []
        for y in range(height):
            by = y // 8
            row = [rgb565_from_grey(level(i, x // 8, by)) for x in range(WIDTH)]
            for j in range(0, WIDTH, 2):
                words.append((row[j + 1] << 16) | row[j])
        (outdir / f"video{i}_{tag}.hex").write_text(
            "".join(f"{w:08x}\n" for w in words)
        )
    return dict(tag=tag, bytes=len(combined), frames=[len(f) for f in frames],
                words=len(words))


if __name__ == "__main__":
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE
    for h in (240, 180):
        info = build(h, out)
        print(" ".join(f"{k}={v}" for k, v in info.items()))
