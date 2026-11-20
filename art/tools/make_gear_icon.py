"""Shop icons for the New Gadget I-IV chain (#132): a cog with a spark, in the
vanilla tech-icon style (36 x 36 art doubled to 72 x 72, warm orange on the
icon row), with one to four pips along the bottom for the tier.

Writes mods-unpacked/cejdan-StoryMode/art/icons/newgadget<n>.png (palette-
encoded, row 12) and art/preview/newgadget_icons.png (real colors, 4x).

Run from the Dome Keeper folder: python art/tools/make_gear_icon.py
"""
import math
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if len(sys.argv) > 1:
    ROOT = sys.argv[1]
OUT = os.path.join(ROOT, "mods-unpacked", "cejdan-StoryMode", "art", "icons")
PREVIEW = os.path.join(ROOT, "art", "preview", "newgadget_icons.png")
PALETTE = os.path.join(ROOT, "systems", "style", "palettes", "palette_1_1.png")

N = 36
ROW = 12
# Row 12 columns: 0 near-black, 3/4 dark violet, 20/21 deep orange, 24 orange,
# 27 light orange, 31 cream, 10 pink spark.
OUTLINE, SHADOW, DARK, MID, LIGHT, HI, SPARK, PIP_OFF = 0, 4, 21, 24, 27, 31, 10, 3

TEETH = 8


def inside(x, y):
    """Cog shape around the centre, with a round hole in the hub."""
    cx, cy = 17.5, 16.5
    dx, dy = x + 0.5 - cx, y + 0.5 - cy
    r = math.hypot(dx, dy)
    a = math.atan2(dy, dx) + math.pi / TEETH / 2
    tooth = (a * TEETH / (2 * math.pi)) % 1.0
    outer = 13.2 if 0.18 < tooth < 0.62 else 10.4
    return 4.2 < r <= outer


def build(tier):
    cols = [[None] * N for _ in range(N)]
    def m(x, y):
        return 0 <= x < N and 0 <= y < N and inside(x, y)
    for y in range(N):
        for x in range(N):
            if m(x, y):
                edge = not (m(x - 1, y) and m(x + 1, y) and m(x, y - 1) and m(x, y + 1))
                if edge:
                    cols[y][x] = OUTLINE
                    continue
                # Lit from the upper left.
                lit = not m(x - 1, y - 1) or not m(x - 2, y - 1)
                dark = not m(x + 1, y + 1) or not m(x + 2, y + 1)
                cx, cy = x + 0.5 - 17.5, y + 0.5 - 16.5
                if lit:
                    cols[y][x] = HI if cx + cy < -6 else LIGHT
                elif dark:
                    cols[y][x] = DARK
                else:
                    cols[y][x] = LIGHT if cx + cy < -4 else MID
            elif any(m(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                cols[y][x] = OUTLINE
    # A soft shadow under the cog.
    for y in range(N):
        for x in range(N):
            if cols[y][x] is None and y > 0 and x > 0 and cols[y - 1][x - 1] in (OUTLINE,) and m(x - 2, y - 2):
                cols[y][x] = SHADOW
    # Spark: a small four-point star at the upper right.
    sx, sy = 30, 4
    for (dx, dy) in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, 2), (0, -2)):
        cols[sy + dy][sx + dx] = SPARK if abs(dx) + abs(dy) <= 1 else HI
    # Tier pips along the bottom.
    for i in range(4):
        px = 11 + i * 4
        for dx in (0, 1):
            for dy in (0, 1):
                cols[32 + dy][px + dx] = (LIGHT if dy == 0 else MID) if i < tier else PIP_OFF
    return cols


def main():
    os.makedirs(OUT, exist_ok=True)
    pal = Image.open(PALETTE).convert("RGBA")
    sheet = Image.new("RGBA", (4 * (N * 2 + 8), N * 2 + 8), (46, 40, 62, 255))
    for tier in range(1, 5):
        cols = build(tier)
        enc = Image.new("RGBA", (N, N), (0, 0, 0, 0))
        real = Image.new("RGBA", (N, N), (0, 0, 0, 0))
        for y in range(N):
            for x in range(N):
                c = cols[y][x]
                if c is not None:
                    enc.putpixel((x, y), (c * 8, 0, ROW * 20, 255))
                    real.putpixel((x, y), pal.getpixel((c * 10 + 5, ROW * 10 + 5)))
        enc.resize((N * 2, N * 2), Image.NEAREST).save(os.path.join(OUT, "newgadget%d.png" % tier))
        sheet.alpha_composite(real.resize((N * 2, N * 2), Image.NEAREST), ((tier - 1) * (N * 2 + 8) + 4, 4))
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(PREVIEW)
    print("wrote", OUT, "and", PREVIEW)


if __name__ == "__main__":
    main()
