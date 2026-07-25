#!/usr/bin/env python3
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


PINK = (251, 114, 153, 255)
WHITE = (255, 255, 255, 255)


def draw_round_line(draw, points, fill, width):
    radius = width // 2
    draw.line(points, fill=fill, width=width, joint="curve")
    for x, y in (points[0], points[-1]):
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=fill)


def make_brand_mark(color):
    scale = 4
    width = 144 * scale
    height = 56 * scale
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    stroke = 5 * scale

    def point(x, y):
        return x * scale, y * scale

    def draw_half(offset):
        draw_round_line(
            draw,
            [
                point(offset + 20, 7),
                point(offset + 11, 5),
                point(offset + 5, 9),
                point(offset + 6, 16),
                point(offset + 17, 22),
                point(offset + 20, 29),
                point(offset + 17, 39),
                point(offset + 10, 45),
                point(offset + 4, 43),
            ],
            color,
            stroke,
        )
        for x in (29, 51):
            draw.ellipse(
                (
                    (offset + x - 3) * scale,
                    6 * scale,
                    (offset + x + 3) * scale,
                    12 * scale,
                ),
                fill=color,
            )
            draw_round_line(
                draw,
                [point(offset + x, 21), point(offset + x - 1, 44)],
                color,
                stroke,
            )
        draw_round_line(
            draw,
            [point(offset + 40, 7), point(offset + 40, 43), point(offset + 43, 45)],
            color,
            stroke,
        )

    draw_half(10)
    draw_half(76)
    return image.resize((144, 56), Image.Resampling.LANCZOS)


def fit_center(image, size, bounds):
    left, top, right, bottom = bounds
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise RuntimeError("brand mark has no visible pixels")
    image = image.crop(bbox)
    scale = min((right - left) / image.width, (bottom - top) / image.height)
    image = image.resize(
        (round(image.width * scale), round(image.height * scale)),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.alpha_composite(
        image,
        (left + (right - left - image.width) // 2, top + (bottom - top - image.height) // 2),
    )
    return canvas


def make_wordmark():
    return fit_center(make_brand_mark(PINK), (180, 48), (5, 2, 175, 46))


def make_mark():
    return make_brand_mark(WHITE)


def remove_upstream_wordmark(image):
    pixels = image.load()
    mask = Image.new("L", image.size, 0)
    mask_pixels = mask.load()
    for y in range(60, 196):
        for x in range(24, 232):
            red, green, blue, alpha = pixels[x, y]
            if alpha > 0 and red > 220 and green > 220 and blue > 220:
                mask_pixels[x, y] = 255
    mask = mask.filter(ImageFilter.MaxFilter(5))
    mask_pixels = mask.load()
    remaining = {(x, y) for y in range(60, 196) for x in range(24, 232) if mask_pixels[x, y]}

    while remaining:
        filled = []
        for x, y in remaining:
            neighbors = []
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < image.width and 0 <= ny < image.height and not mask_pixels[nx, ny]:
                    neighbors.append(pixels[nx, ny])
            if neighbors:
                pixels[x, y] = tuple(sum(value[i] for value in neighbors) // len(neighbors) for i in range(4))
                filled.append((x, y))
        if not filled:
            raise RuntimeError("could not reconstruct the upstream icon background")
        for x, y in filled:
            mask_pixels[x, y] = 0
            remaining.remove((x, y))
    return image


def make_icon(upstream_icon):
    image = Image.open(upstream_icon).convert("RGBA")
    if image.size != (256, 256):
        raise RuntimeError(f"unexpected upstream icon size: {image.size}")
    image = remove_upstream_wordmark(image.copy())
    image.alpha_composite(fit_center(make_mark(), image.size, (36, 76, 220, 184)))
    return image


def save(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=False, compress_level=9)


def main():
    parser = argparse.ArgumentParser(description="Generate reproducible silisili bitmap branding")
    parser.add_argument("--upstream-icon", type=Path, required=True)
    parser.add_argument("--wordmark", type=Path, required=True)
    parser.add_argument("--mark", type=Path, required=True)
    parser.add_argument("--icon", type=Path, required=True)
    args = parser.parse_args()

    save(make_wordmark(), args.wordmark)
    save(make_mark(), args.mark)
    save(make_icon(args.upstream_icon), args.icon)


if __name__ == "__main__":
    main()
