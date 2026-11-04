"""Pad BMP photos to a fixed canvas, preserving aspect ratio with black bars."""
from pathlib import Path
import argparse
import json
from PIL import Image


def pad_one(src, dst, width, height):
    image = Image.open(src).convert("RGB")
    source_size = image.size
    scale = min(width / image.width, height / image.height)
    fit = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    if fit != image.size:
        image = image.resize(fit, Image.LANCZOS)
    canvas = Image.new("RGB", (width, height), (0, 0, 0))
    offset = ((width - fit[0]) // 2, (height - fit[1]) // 2)
    canvas.paste(image, offset)
    canvas.save(dst, "BMP")
    return {
        "source": str(Path(src).resolve()),
        "output": str(Path(dst).resolve()),
        "source_size": list(source_size),
        "image_size": list(fit),
        "offset": list(offset),
        "canvas": [width, height],
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="directory containing source .bmp photos")
    parser.add_argument("output", help="directory for padded 24-bit BMP photos")
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)
    args = parser.parse_args(argv)
    source = Path(args.input)
    target = Path(args.output)
    if not source.is_dir():
        raise SystemExit(f"input directory not found: {source}")
    target.mkdir(parents=True, exist_ok=True)
    photos = [pad_one(p, target / p.name, args.width, args.height)
              for p in sorted(source.glob("*.bmp"))]
    if not photos:
        raise SystemExit(f"no .bmp files under {source}")
    print(json.dumps({"output": str(target.resolve()), "photos": photos}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
