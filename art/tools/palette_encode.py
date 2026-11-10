"""Encode real-color sprites into Dome Keeper's palette-index format, and decode them back.

The game draws sprites through systems/style/materials/palette_swap_shader.gdshader:
    color = palette[u = 0.5/32 + R, v = 0.5/12 + B]
so a sprite pixel's red channel picks the palette column (R = column * 8) and blue picks
the row (B = row * 20). systems/style/palettes/index_palette.png holds the exact encoded
color for every cell; palette_1_1.png holds the default real colors.

Usage (from the Dome Keeper folder):
    python art/tools/palette_encode.py encode <real.png> <game.png> --rows 3,11,12
    python art/tools/palette_encode.py decode <game.png> <out.png> [--palette palette_1_1]

--rows is the order in which palette rows are searched for each real color. The same
real color appears in several rows; the row chosen matters when the game swaps to
another palette, so pick the row family the sprite belongs to (drops: 3, icons: 12).
"""
import argparse
import json
import sys
from pathlib import Path

from PIL import Image

GAME = Path(__file__).resolve().parents[2]
PALETTES = GAME / "systems" / "style" / "palettes"
MOD_CELLS = GAME / "art" / "palette" / "mineral_cells.json"
CELL, COLS, ROWS = 10, 32, 13


def mod_cells():
    """Mod-owned cells (empty in every vanilla palette): {(row, col): (r, g, b, 255)}."""
    if not MOD_CELLS.exists():
        return {}
    out = {}
    for name, m in json.loads(MOD_CELLS.read_text()).items():
        if name.startswith("_"):
            continue
        for col, h in zip(m["cols"], m["colors"]):
            out[(m["row"], col)] = (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16), 255)
    return out


def palette_image(name):
    """A palette as the mod would hand it to the shader: vanilla cells plus the mod-owned cells."""
    im = Image.open(PALETTES / f"{name}.png").convert("RGBA")
    for (row, col), c in mod_cells().items():
        for y in range(row * CELL, row * CELL + CELL):
            for x in range(col * CELL, col * CELL + CELL):
                im.putpixel((x, y), c)
    return im


def cells(path):
    im = path if isinstance(path, Image.Image) else Image.open(path).convert("RGBA")
    return {(row, col): im.getpixel((col * CELL + CELL // 2, row * CELL + CELL // 2))
            for row in range(ROWS) for col in range(COLS)}


def encode(src, dst, rows):
    real = cells(PALETTES / "palette_1_1.png")
    index = cells(PALETTES / "index_palette.png")
    lookup = {}
    # mod-owned cells win: their colors never change between palettes
    for (row, col), c in mod_cells().items():
        lookup.setdefault(c[:3], (row, col))
        index[(row, col)] = (col * 8, c[1], row * 20, 255)
    for row in rows:
        for col in range(COLS):
            c = real[(row, col)]
            if c[3] and c[:3] not in lookup:
                lookup[c[:3]] = (row, col)
    im = Image.open(src).convert("RGBA")
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    missing = set()
    for y in range(im.height):
        for x in range(im.width):
            p = im.getpixel((x, y))
            if p[3] == 0:
                continue
            cell = lookup.get(p[:3])
            if cell is None:
                missing.add("#%02x%02x%02x" % p[:3])
                continue
            out.putpixel((x, y), index[cell][:3] + (p[3],))
    if missing:
        sys.exit(f"{src}: colors not in palette rows {rows}: {sorted(missing)}")
    out.save(dst)
    return out


def decode(src, dst, palette="palette_1_1"):
    pal = palette_image(palette)
    im = Image.open(src).convert("RGBA")
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = im.getpixel((x, y))
            if a == 0:
                continue
            u = 0.5 / 32 + r / 255
            v = 0.5 / 12 + b / 255
            c = pal.getpixel((min(pal.width - 1, int(u * pal.width)), min(pal.height - 1, int(v * pal.height))))
            out.putpixel((x, y), c[:3] + (a,))
    if dst:
        out.save(dst)
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["encode", "decode"])
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--rows", default="3,11,12")
    ap.add_argument("--palette", default="palette_1_1")
    a = ap.parse_args()
    if a.mode == "encode":
        rows = [int(r) for r in a.rows.split(",")]
        encode(a.src, a.dst, rows)
        back = decode(a.dst, None)
        orig = Image.open(a.src).convert("RGBA")
        bad = sum(1 for p, q in zip(orig.getdata(), back.getdata()) if p[3] and p != q)
        print(f"{a.dst}: encoded, round-trip mismatches: {bad}")
        sys.exit(1 if bad else 0)
    decode(a.src, a.dst, a.palette)
