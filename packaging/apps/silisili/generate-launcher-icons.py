#!/usr/bin/env python3
import argparse
from pathlib import Path

from PIL import Image, ImageDraw


def main():
    parser = argparse.ArgumentParser(
        description="Generate reproducible Sailfish silisili launcher icons"
    )
    parser.add_argument("--template", type=Path, required=True)
    parser.add_argument("--mark", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    template = Image.open(args.template).convert("RGBA")
    if template.size != (150, 150):
        raise RuntimeError(f"unexpected Sailfish template size: {template.size}")

    mark = Image.open(args.mark).convert("RGBA")
    bbox = mark.getchannel("A").getbbox()
    if bbox is None:
        raise RuntimeError("silisili mark has no visible pixels")
    mark = mark.crop(bbox)
    scale = min(90 / mark.width, 40 / mark.height)
    mark = mark.resize(
        (round(mark.width * scale), round(mark.height * scale)),
        Image.Resampling.LANCZOS,
    )

    master = template.copy()
    ImageDraw.Draw(master).rectangle((54, 46, 106, 104), fill=(255, 166, 163, 255))
    master.alpha_composite(
        mark, ((150 - mark.width) // 2, (150 - mark.height) // 2)
    )

    for size in (16, 24, 32, 48, 64, 86, 108, 128, 172, 256):
        path = args.output / f"{size}x{size}" / "apps" / "silisili-sailfish.png"
        path.parent.mkdir(parents=True, exist_ok=True)
        master.resize((size, size), Image.Resampling.LANCZOS).save(
            path, format="PNG", optimize=False, compress_level=9
        )


if __name__ == "__main__":
    main()
