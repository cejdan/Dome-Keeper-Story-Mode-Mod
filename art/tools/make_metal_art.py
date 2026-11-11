# Generates the Story Mode metal tile's sprites, palette-encoded, into the mod:
#   mods-unpacked/cejdan-StoryMode/art/tiles/sheet_metal.png     tile sheet, 12x12 grid of 24 px cells
#   mods-unpacked/cejdan-StoryMode/art/tiles/particle_metal.png  tile-break debris strip
# plus art/preview/metal_sheet.png (real colors, for looking at).
#
# A metal tile is a riveted steel plate that fills the whole tile, so it reads
# as a built thing and not as rock or ore. Five frames sit at cols 0-4, row 5
# (the slot the tile sprite reads), like the mineral ore sheets. The sheet has
# no border-overlay block: metal draws no ore edges.
#
# Colors: the "metal" cells of art/palette/mineral_cells.json [dark, mid, light]
# plus the near-black outline cell that is the same in every palette.
#
# Run from the Dome Keeper folder:  python art/tools/make_metal_art.py
import os, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_mineral_art as mm  # noqa: E402

OUT = os.path.join(mm.ROOT, "mods-unpacked", "cejdan-StoryMode", "art", "tiles")
RIVETS = [(3, 3), (19, 3), (3, 19), (19, 19)]


def plate(pal, variant):
    img = Image.new("RGBA", (24, 24), pal["K"])
    for y in range(1, 23):
        for x in range(1, 23):
            img.putpixel((x, y), pal["C"])
    # Bevel: light top and left inner edge, dark bottom and right.
    for i in range(1, 23):
        img.putpixel((i, 1), pal["L"])
        img.putpixel((1, i), pal["L"])
        img.putpixel((i, 22), pal["D"])
        img.putpixel((22, i), pal["D"])
    if variant == 1:  # horizontal seam
        for x in range(2, 22):
            img.putpixel((x, 11), pal["D"])
            img.putpixel((x, 12), pal["L"])
    elif variant == 2:  # vertical seam
        for y in range(2, 22):
            img.putpixel((11, y), pal["D"])
            img.putpixel((12, y), pal["L"])
    elif variant == 3:  # a cross brace
        for i in range(5, 19):
            img.putpixel((i, i), pal["D"])
            img.putpixel((i + 1, i), pal["L"])
            img.putpixel((23 - i, i), pal["D"])
    elif variant == 4:  # scuffs
        for x, y in [(7, 8), (8, 8), (9, 9), (14, 15), (15, 15), (16, 14), (12, 6)]:
            img.putpixel((x, y), pal["D"])
    for rx, ry in RIVETS:
        img.putpixel((rx, ry), pal["L"])
        img.putpixel((rx + 1, ry), pal["C"])
        img.putpixel((rx, ry + 1), pal["C"])
        img.putpixel((rx + 1, ry + 1), pal["D"])
    return img


def sheet(pal):
    img = Image.new("RGBA", (288, 288), (0, 0, 0, 0))
    for i in range(5):
        img.paste(plate(pal, i), (i * 24, 5 * 24))
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    pal = mm.colors_of("metal")
    sheet(pal).save(os.path.join(OUT, "sheet_metal.png"))
    mm.particle(pal).save(os.path.join(OUT, "particle_metal.png"))
    real = mm.real_of("metal")
    rs = sheet(real)
    prev = Image.new("RGBA", (5 * 24 * 4 + 24, 24 * 4 + 16), (0x1a, 0x16, 0x22, 255))
    prev.alpha_composite(rs.crop((0, 120, 120, 144)).resize((480, 96), Image.NEAREST), (8, 8))
    os.makedirs(os.path.join(mm.ROOT, "art", "preview"), exist_ok=True)
    prev.save(os.path.join(mm.ROOT, "art", "preview", "metal_sheet.png"))
    print("wrote metal sheet to", OUT)


if __name__ == "__main__":
    main()
