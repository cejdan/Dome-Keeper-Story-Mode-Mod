# Generates every Story Mode mineral sprite, palette-encoded, straight into the mod:
#   mods-unpacked/cejdan-StoryMode/art/minerals/drop_<m>.png    drop sprite (8x8 metals, 9x9 gems)
#   mods-unpacked/cejdan-StoryMode/art/minerals/sheet_<m>.png   ore sheet, 12x12 grid of 24 px cells
#   mods-unpacked/cejdan-StoryMode/art/minerals/icon_<m>.png    24 px HUD/shop icon (drop sprite x3)
#   mods-unpacked/cejdan-StoryMode/art/minerals/particle_<m>.png  tile-break debris strip (4 frames of 4x4)
# plus art/preview/mineral_sheets.png (real colors, for looking at).
#
# Ore sheet layout (same grid as vanilla content/map/border/resources_sheet.png):
#   cols 0-3, rows 0-3   border-overlay block (vanilla's iron block, recoloured)
#   cols 0-4, row 5      five tile frames (one is picked per tile from its coordinate)
#
# Colors come from art/palette/mineral_cells.json: each mineral owns three palette
# cells [dark, mid, light] that the mod fills at runtime, so a pixel is stored as
# (col*8, 0, row*20), the game's palette encoding.
#
# Run from the Dome Keeper folder:  python art/tools/make_mineral_art.py
import json, os, random
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "mods-unpacked", "cejdan-StoryMode", "art", "minerals")
CELLS = json.load(open(os.path.join(ROOT, "art", "palette", "mineral_cells.json")))
VANILLA_SHEET = os.path.join(ROOT, "content", "map", "border", "resources_sheet.png")
K = (5, 3)  # near-black outline cell (#12121a), constant in every vanilla palette

SHAPES = {
    "square": ["MMMMMMMM", "MKKKKKKM", "MKLLCCKM", "MKLCCCKM", "MKCCCDKM", "MKDDDDKM", "MKKKKKKM", "MMMMMMMM"],
    "star": ["....M....", "...MLM...", "...MLM...", ".MMLLDMM.", "MLLLLDDDM", ".MMLDDMM.", "...MDM...", "...MDM...", "....M...."],
    # unobtainium: a leaning crystal shard, unlike the metal squares and gem stars
    "shard": [".....MM..", "....MLLM.", "...MLLCM.", "..MLLCDM.", ".MLLCDDM.", ".MLCDDM..", "MLCDDM...", "MCDDM....", ".MM......"],
}

# Tile-frame motifs: (shape rows) using L light, C mid, D dark.
BIG = {
    "square": ["DDDDDDD", "DLLLCCD", "DLLCCCD", "DLCCCCD", "DCCCCDD", "DCCCDDD", "DDDDDDD"],
    "star": ["...C...", "...L...", "..CLC..", "CLLLDDC", "..CDC..", "...D...", "...C..."],
    "shard": ["....CC.", "...CLC.", "..CLLD.", ".CLLDD.", ".CLDD..", "CLDD...", "CDD...."],
}
SMALL = {
    "square": [["CC", "CD"], ["LCD", "CCD", "DDD"], ["LC", "CD"], ["C"]],
    "star": [[".C.", "CLC", ".D."], ["C"], [".L.", "CLD", ".D."], ["LC"]],
    "shard": [[".C", "CL", "D."], ["C"], ["..C", ".LD", "CD."], ["L", "D"]],
}


def enc(cell):
    return (cell[0] * 8, 0, cell[1] * 20, 255)


def colors_of(m):
    c = CELLS[m]
    return {"D": enc((c["cols"][0], c["row"])), "C": enc((c["cols"][1], c["row"])), "M": enc((c["cols"][1], c["row"])),
            "L": enc((c["cols"][2], c["row"])), "K": enc(K)}


def real_of(m):
    c = CELLS[m]["colors"]
    def h(s): return tuple(int(s[i:i + 2], 16) for i in (1, 3, 5)) + (255,)
    return {"D": h(c[0]), "C": h(c[1]), "M": h(c[1]), "L": h(c[2]), "K": (0x12, 0x12, 0x1a, 255)}


def stamp(img, rows, ox, oy, pal):
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch != "." and 0 <= ox + x < img.width and 0 <= oy + y < img.height:
                img.putpixel((ox + x, oy + y), pal[ch])


def drop(shape, pal):
    rows = SHAPES[shape]
    img = Image.new("RGBA", (len(rows[0]), len(rows)), (0, 0, 0, 0))
    stamp(img, rows, 0, 0, pal)
    return img


def tile_frame(shape, pal, rng):
    img = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    bx, by = rng.randint(5, 11), rng.randint(5, 11)
    stamp(img, BIG[shape], bx, by, pal)
    placed = [(bx, by, 7, 7)]
    for _ in range(rng.randint(2, 4)):
        s = rng.choice(SMALL[shape])
        for _try in range(20):
            x, y = rng.randint(2, 20), rng.randint(2, 20)
            w, h = len(s[0]), len(s)
            if all(x + w + 1 < px or x > px + pw + 1 or y + h + 1 < py or y > py + ph + 1 for px, py, pw, ph in placed):
                stamp(img, s, x, y, pal)
                placed.append((x, y, w, h))
                break
    return img


def border_block(pal):
    # Vanilla's iron border block (cols 0-3, rows 8-11), recoloured by brightness.
    src = Image.open(VANILLA_SHEET).convert("RGBA").crop((0, 8 * 24, 4 * 24, 12 * 24))
    used = sorted({p for p in src.getdata() if p[3] > 0}, key=lambda p: p[0])
    order = ["D", "C", "L"]
    remap = {p: pal[order[min(2, i * 3 // max(1, len(used)))]] for i, p in enumerate(used)}
    out = Image.new("RGBA", src.size, (0, 0, 0, 0))
    for y in range(src.height):
        for x in range(src.width):
            p = src.getpixel((x, y))
            if p[3] > 0:
                out.putpixel((x, y), remap[p])
    return out


def particle(pal):
    # Vanilla's iron tile-break particle strip (4 frames of 4x4), recoloured.
    src = Image.open(os.path.join(ROOT, "content", "map", "tile", "tile-break-dirt-particle_iron.png")).convert("RGBA")
    used = sorted({p for p in src.getdata() if p[3] > 0}, key=lambda p: p[0])
    order = ["D", "C", "L"]
    out = Image.new("RGBA", src.size, (0, 0, 0, 0))
    for y in range(src.height):
        for x in range(src.width):
            p = src.getpixel((x, y))
            if p[3] > 0:
                out.putpixel((x, y), pal[order[min(2, used.index(p))]])
    return out


def sheet(m, shape, pal):
    rng = random.Random(hash(m) & 0xffff if False else sum(map(ord, m)))
    img = Image.new("RGBA", (288, 288), (0, 0, 0, 0))
    img.paste(border_block(pal), (0, 0))
    for i in range(5):
        img.paste(tile_frame(shape, pal, rng), (i * 24, 5 * 24))
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    shapes = {"bronze": "square", "iron": "square", "gold": "square", "mythril": "square",
              "sapphire": "star", "emerald": "star", "ruby": "star", "diamond": "star", "unobtainium": "shard"}
    names = [m for m in ["bronze", "iron", "gold", "sapphire", "emerald", "ruby", "mythril", "diamond", "unobtainium"] if m in CELLS]
    preview = Image.new("RGBA", (len(names) * 150, 150), (0x1a, 0x16, 0x22, 255))
    for i, m in enumerate(names):
        shape = shapes[m]
        pal = colors_of(m)
        d = drop(shape, pal)
        d.save(os.path.join(OUT, "drop_%s.png" % m))
        d.resize((d.width * 3, d.height * 3), Image.NEAREST).save(os.path.join(OUT, "icon_%s.png" % m))
        sheet(m, shape, pal).save(os.path.join(OUT, "sheet_%s.png" % m))
        particle(pal).save(os.path.join(OUT, "particle_%s.png" % m))
        # real-colour preview: 5 tile frames + the drop, at 2x
        real = real_of(m)
        rs = sheet(m, shape, real)
        strip = rs.crop((0, 120, 72, 144)).resize((144, 48), Image.NEAREST)
        preview.alpha_composite(strip, (i * 150 + 3, 4))
        strip2 = rs.crop((72, 120, 120, 144)).resize((96, 48), Image.NEAREST)
        preview.alpha_composite(strip2, (i * 150 + 3, 54))
        rd = drop(shape, real)
        preview.alpha_composite(rd.resize((rd.width * 4, rd.height * 4), Image.NEAREST), (i * 150 + 104, 60))
        preview.alpha_composite(rd, (i * 150 + 60, 120))
    preview.save(os.path.join(ROOT, "art", "preview", "mineral_sheets.png"))
    print("wrote", len(names), "minerals to", OUT)


if __name__ == "__main__":
    main()
