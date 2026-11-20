"""Story item sprites (#93 translators, #94 miner bones), palette-encoded.

Writes into mods-unpacked/cejdan-StoryMode/art/items/:
  translator.png      18 x 18  the monsters' translator: a carved bone-stone horn
                               with a red rune-eye (drop and chamber socket)
  minerbones.png      10 x 10  a miner's skull with a cracked visor lamp (drop)
  datalog_icon.png    14 x 14  the log box's corner icon (a cracked suit pad)
plus art/preview/story_items.png in real colors at 8x.

Colors are mod-owned palette cells in row 0 (empty in all 24 vanilla
palettes); util/palette.gd fills them at runtime. They are listed in
art/palette/mineral_cells.json next to the minerals.

Run from the Dome Keeper folder: python art/tools/make_story_items.py
"""
import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_mineral_art as mm  # noqa: E402

OUT = os.path.join(mm.ROOT, "mods-unpacked", "cejdan-StoryMode", "art", "items")

# key -> (cell name in mineral_cells.json, index 0 dark / 1 mid / 2 light)
KEYS = {
    "s": ("translator", 0), "S": ("translator", 1), "W": ("translator", 2),
    "r": ("rune_eye", 0), "R": ("rune_eye", 1), "Y": ("rune_eye", 2),
    "b": ("bones", 0), "B": ("bones", 1), "H": ("bones", 2),
    "g": ("datalog", 0), "G": ("datalog", 1), "V": ("datalog", 2),
}

TRANSLATOR = [
    "......KKK.........",
    ".....KWWSK........",
    "....KWWSSK........",
    "....KWSSsK........",
    "...KWWSsK.........",
    "...KWSSsKKKKK.....",
    "..KWWSSsSSWWWKK...",
    "..KWSSSSSSSSWWSK..",
    ".KWSSKKKSSSSSSSSK.",
    ".KWSKRRRKSsSSSSsK.",
    "KWSKRYYRrKsSsSSsK.",
    "KWSKRYRRrKsSSsSsK.",
    "KWSKrRRrrKSSsSSsK.",
    ".KSSKrrrKSSSsSssK.",
    ".KsSSKKKSSsSSsssK.",
    "..KssSSSSSssssKK..",
    "...KKssssssssK....",
    ".....KKKKKKKK.....",
]

BONES = [
    "..KKKKKK..",
    ".KHHHBBBK.",
    "KHHGVGBBbK",
    "KHGVGgKBbK",
    "KHBKKKBKbK",
    "KHBKbKBbbK",
    ".KBBHBBbK.",
    "..KHKHKbK.",
    "..KBKBKK..",
    "...KKK....",
]

DATALOG = [
    ".KKKKKKKKKKKK.",
    "KbbbbbbbbbbbbK",
    "KbKKKKKKKKKKbK",
    "KbKggggGggKKbK",
    "KbKgVVgggKgKbK",
    "KbKgggggKggKbK",
    "KbKgVVVKgggKbK",
    "KbKggKggggVKbK",
    "KbKgKgVVVggKbK",
    "KbKKggggggKKbK",
    "KbKKKKKKKKKKbK",
    "KbbbbHbbbbbbbK",
    "KbbbbbbbbbbbbK",
    ".KKKKKKKKKKKK.",
]


# Bone decals for the minerbones tile (drawn over the rock like ore): five
# variants of a miner's remains half-buried, 24 x 24 each.
TILE_BONES = [
    [
        "........................",
        "........................",
        "........................",
        "......KKKKK.............",
        ".....KHHHBBK............",
        "....KHGVGBBbK...........",
        "....KHBKKBKbK...........",
        "....KHBKbBbbK...........",
        ".....KBHBBbK............",
        "......KHKHKK..KK........",
        ".......KK.K..KHBK.......",
        "............KHBK..KK....",
        "...KKK.....KHBK..KHBK...",
        "..KHBBKKKKKHBK..KHBK....",
        "..KBbBHHHBBBK..KHBK.....",
        "...KKKBBBBBK..KHBK......",
        "......KKKKK...KBK.......",
        "...............K........",
    ],
    [
        "........................",
        "........................",
        "...........KKKKK........",
        "..........KHHHBBK.......",
        ".........KHGVGBBbK......",
        ".........KHBKKBKbK......",
        ".........KHBKbBbbK......",
        "..........KBHBBbK.......",
        "...........KHKHKK.......",
        "....KK......K.K.........",
        "...KHBK.................",
        "....KHBK....KKKKKKK.....",
        ".....KHBK..KHBHBHBHK....",
        "......KHBK.KBbBbBbBK....",
        ".......KBK..KKKKKKK.....",
        "........K...............",
    ],
    [
        "........................",
        "........................",
        "........................",
        "........................",
        "....KKK...........KKK...",
        "...KHBBK.........KHBBK..",
        "....KHBBK.......KHBBK...",
        ".....KHBBKKKKKKKHBBK....",
        "......KHBBBBBBBBBBK.....",
        ".......KKKKKKKKKKK......",
        "...........KKKKK........",
        "..........KHHHBBK.......",
        ".........KHGVGBBbK......",
        ".........KHBKKBKbK......",
        "..........KBHBBbK.......",
        "...........KKKKK........",
    ],
    [
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "............KKKK........",
        "...........KGVGbK.......",
        "..........KGVVGbbK......",
        "..........KGGGGbbK......",
        "...........KKKKKK.......",
        "........................",
        "....KK.KK.KK.KK.........",
        "...KHBKHBKHBKHBK........",
        "...KBbKBbKBbKBbK........",
        "....KK.KK.KK.KK.........",
    ],
    [
        "........................",
        "........................",
        ".........KKKKK..........",
        "........KHHHBBK.........",
        ".......KHGVGBBbK........",
        ".......KHBKKBKbK........",
        ".......KHBKbBbbK........",
        "........KBHBBbK.........",
        ".........KHKHK..........",
        "..........KKK...........",
        "........................",
        "........................",
        ".....KKKKKKKKKKKKKK.....",
        "....KHBHBHBHBHBHBHBK....",
        ".....KKKKKKKKKKKKKK.....",
    ],
]


def tile_sheet(pal):
    sheet = Image.new("RGBA", (24 * 12, 24 * 12), (0, 0, 0, 0))
    for i, rows in enumerate(TILE_BONES):
        rows = [r.ljust(24, ".") for r in rows]
        mm.stamp(sheet, rows, i * 24, 5 * 24, pal)
    return sheet


def palettes(cells):
    enc, real = {"K": mm.enc(mm.K)}, {"K": (0x12, 0x12, 0x1a, 255)}
    for k, (name, i) in KEYS.items():
        c = cells[name]
        enc[k] = mm.enc((c["cols"][i], c["row"]))
        h = c["colors"][i]
        real[k] = tuple(int(h[j:j + 2], 16) for j in (1, 3, 5)) + (255,)
    return enc, real


def draw(rows, pal):
    img = Image.new("RGBA", (len(rows[0]), len(rows)), (0, 0, 0, 0))
    mm.stamp(img, rows, 0, 0, pal)
    return img


def main():
    cells = json.load(open(os.path.join(mm.ROOT, "art", "palette", "mineral_cells.json")))
    enc, real = palettes(cells)
    os.makedirs(OUT, exist_ok=True)
    sprites = {"translator": TRANSLATOR, "minerbones": BONES, "datalog_icon": DATALOG}
    for name, rows in sprites.items():
        assert all(len(r) == len(rows[0]) for r in rows), name
        draw(rows, enc).save(os.path.join(OUT, name + ".png"))
    tile_sheet(enc).save(os.path.join(OUT, "sheet_minerbones.png"))
    tile_sheet(real).crop((0, 5 * 24, 5 * 24, 6 * 24)).resize((5 * 24 * 6, 24 * 6), Image.NEAREST).save(
        os.path.join(mm.ROOT, "art", "preview", "minerbones_tiles.png"))
    s = 8
    sheet = Image.new("RGBA", (sum(len(r[0]) + 2 for r in sprites.values()) * s, 20 * s), (40, 36, 44, 255))
    x = s
    for rows in sprites.values():
        big = draw(rows, real).resize((len(rows[0]) * s, len(rows) * s), Image.NEAREST)
        sheet.alpha_composite(big, (x, s))
        x += (len(rows[0]) + 2) * s
    sheet.save(os.path.join(mm.ROOT, "art", "preview", "story_items.png"))
    print("wrote", ", ".join(sprites))


if __name__ == "__main__":
    main()
