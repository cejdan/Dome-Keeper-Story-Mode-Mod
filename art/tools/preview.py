"""Render game-encoded sprites the way the game's palette shader would, next to vanilla sprites.

Usage (from the Dome Keeper folder):
    python art/tools/preview.py <out.png> --new a.png b.png --vanilla x.png y.png [--palettes palette_1_1,palette_2_1]
"""
import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
from palette_encode import decode  # noqa: E402

BG = (18, 18, 26, 255)  # #12121a, the dark mine background in the game palette
SCALE, GAP = 6, 12


def row_image(paths, palette):
    sprites = [decode(p, None, palette) for p in paths]
    big = [s.resize((s.width * SCALE, s.height * SCALE), Image.NEAREST) for s in sprites]
    h = max(b.height for b in big) + max(s.height for s in sprites) + GAP * 3
    w = sum(max(b.width, 1) + GAP for b in big) + GAP
    im = Image.new("RGBA", (w, h), BG)
    x = GAP
    for s, b in zip(sprites, big):
        im.alpha_composite(b, (x, GAP))
        im.alpha_composite(s, (x, GAP * 2 + b.height))  # true size underneath
        x += b.width + GAP
    return im


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--new", nargs="+", required=True)
    ap.add_argument("--vanilla", nargs="+", default=[])
    ap.add_argument("--palettes", default="palette_1_1")
    a = ap.parse_args()
    blocks = []
    for pal in a.palettes.split(","):
        for label, paths in (("vanilla", a.vanilla), ("new", a.new)):
            if paths:
                blocks.append((f"{pal}  {label}", row_image(paths, pal)))
    W = max(b.width for _, b in blocks) + 24
    H = sum(b.height + 22 for _, b in blocks) + 12
    sheet = Image.new("RGBA", (W, H), (40, 40, 48, 255))
    d = ImageDraw.Draw(sheet)
    y = 8
    for label, b in blocks:
        d.text((12, y), label, fill=(230, 230, 230, 255))
        sheet.alpha_composite(b, (12, y + 14))
        y += b.height + 22
    sheet.save(a.out)
    print("wrote", a.out, sheet.size)
