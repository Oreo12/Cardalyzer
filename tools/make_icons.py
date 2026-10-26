#!/usr/bin/env python3
"""Draw the UI's counter symbols: coin, reticle, heart and shield.

Usage: python tools/make_icons.py [-o assets/icons]

Each is a 128 x 128 PNG with a transparent background and a plain middle,
because the UI lays the counter's number over it. They're simple shapes
drawn here, so the engine ships no one else's artwork.
"""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 128
SCALE = 4  # draw large, then shrink, for smooth edges


def canvas():
    img = Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def finish(img):
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def s(v):
    return int(v * SCALE)


def coin():
    img, d = canvas()
    d.ellipse([s(6), s(6), s(122), s(122)], fill=(122, 84, 16, 255))       # rim shadow
    d.ellipse([s(10), s(10), s(118), s(118)], fill=(232, 178, 44, 255))    # gold
    d.ellipse([s(22), s(22), s(106), s(106)], fill=(201, 146, 26, 255))    # inner face
    d.arc([s(14), s(14), s(114), s(114)], 200, 290, fill=(255, 226, 130, 255), width=s(5))  # shine
    return finish(img)


def reticle():
    img, d = canvas()
    red, dark = (214, 48, 38, 255), (90, 14, 10, 255)
    d.ellipse([s(8), s(8), s(120), s(120)], fill=(40, 8, 6, 170))          # backing for the number
    for color, grow in ((dark, 3), (red, 0)):
        d.ellipse([s(14 - grow), s(14 - grow), s(114 + grow), s(114 + grow)], outline=color, width=s(9 + grow * 2))
        for box in ([60 - grow, 0, 68 + grow, 34], [60 - grow, 94, 68 + grow, 128],
                    [0, 60 - grow, 34, 68 + grow], [94, 60 - grow, 128, 68 + grow]):
            d.rectangle([s(v) for v in box], fill=color)
    return finish(img)


def heart():
    img, d = canvas()
    def shape(color, inset):
        i = inset
        d.ellipse([s(8 + i), s(14 + i), s(68 - i), s(74 - i)], fill=color)
        d.ellipse([s(60 + i), s(14 + i), s(120 - i), s(74 - i)], fill=color)
        d.polygon([(s(12 + i), s(56)), (s(116 - i), s(56)), (s(64), s(120 - i * 1.6))], fill=color)
    shape((110, 14, 26, 255), 0)
    shape((214, 40, 62, 255), 5)
    d.ellipse([s(24), s(26), s(44), s(42)], fill=(255, 140, 156, 200))      # shine
    return finish(img)


def shield():
    img, d = canvas()
    def shape(color, inset):
        i = inset
        top, bottom = 8 + i, 122 - i * 1.4
        d.polygon([(s(14 + i), s(top + 10)), (s(64), s(top)), (s(114 - i), s(top + 10)),
                   (s(110 - i), s(70)), (s(64), s(bottom)), (s(18 + i), s(70))], fill=color)
    shape((30, 44, 66, 255), 0)
    shape((86, 116, 156, 255), 6)
    shape((62, 90, 128, 255), 14)
    return finish(img)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("-o", "--out", type=Path, default=Path("assets/icons"))
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    for name, draw in (("coin", coin), ("reticle", reticle), ("heart", heart), ("shield", shield)):
        draw().save(args.out / f"{name}.png")
    print(f"wrote coin, reticle, heart and shield to {args.out}")


if __name__ == "__main__":
    main()
