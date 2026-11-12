"""The monsters' rune alphabet (#92): one glyph per letter, a real cipher.

Every rune is built on a 5 x 7 grid around a central spine, from a small set of
strokes (bars, arms, ticks, a broken spine), so the alphabet reads as one
script. Each letter gets a different stroke set, chosen so any two runes differ
by at least three pixels.

Writes:
  mods-unpacked/cejdan-StoryMode/art/runes/runes.png   glyph atlas, white on clear
  mods-unpacked/cejdan-StoryMode/art/runes/runes.json  letter -> atlas cell + codepoint
  art/preview/runes.png                                key sheet: rune above letter, 8x

Runes live at Private Use Area codepoints (U+E000 + cipher index), so a runed
line holds no Latin letters at all. The cipher order is shuffled with a fixed
seed, so the atlas order gives nothing away.

Run from the Dome Keeper folder: python art/tools/make_rune_font.py
"""
import itertools
import json
import os
import random

from PIL import Image

W, H = 5, 7
PAD = 1
SPINE = [(2, y) for y in range(H)]

STROKES = {
    "top_bar": [(1, 0), (3, 0)],
    "crown": [(0, 0), (4, 0)],
    "base_bar": [(1, 6), (3, 6)],
    "feet": [(0, 6), (4, 6)],
    "l_up": [(1, 2), (0, 1)],
    "r_up": [(3, 2), (4, 1)],
    "l_down": [(1, 4), (0, 5)],
    "r_down": [(3, 4), (4, 5)],
    "l_tick": [(0, 3), (1, 3)],
    "r_tick": [(3, 3), (4, 3)],
    "l_hook": [(1, 1), (0, 2)],
    "r_hook": [(3, 5), (4, 4)],
}
# Strokes that remove spine pixels.
CUTS = {"gap": [(2, 3)], "short": [(2, 0), (2, 6)]}

LETTERS = "abcdefghijklmnopqrstuvwxyz"
PUNCT = {".": [(2, 6)], ",": [(2, 5), (1, 6)], "!": [(2, 0), (2, 1), (2, 2), (2, 3), (2, 6)],
         "?": [(1, 0), (2, 0), (3, 1), (2, 2), (2, 3), (2, 6)], "'": [(2, 0), (2, 1)]}


def glyph(strokes):
    px = set(SPINE)
    for s in strokes:
        if s in CUTS:
            px -= set(CUTS[s])
        else:
            px |= set(STROKES[s])
    return frozenset(px)


def build():
    names = list(STROKES) + list(CUTS)
    combos = []
    for n in (2, 3):
        for c in itertools.combinations(names, n):
            if "gap" in c and "short" in c:
                continue
            combos.append(c)
    rnd = random.Random(1729)
    rnd.shuffle(combos)
    chosen = []
    for c in combos:
        g = glyph(c)
        # Readable as distinct: at least 3 pixels apart from every other rune,
        # and left-right mirror images count as the same rune.
        mirror = frozenset((W - 1 - x, y) for x, y in g)
        if all(len(g ^ o) >= 3 and len(mirror ^ o) >= 3 for o in chosen):
            chosen.append(g)
        if len(chosen) == len(LETTERS):
            break
    assert len(chosen) == len(LETTERS), len(chosen)
    order = list(range(len(LETTERS)))
    rnd.shuffle(order)
    return {LETTERS[i]: (chosen[i], order[i]) for i in range(len(LETTERS))}


def main():
    runes = build()
    cells = list(LETTERS) + list(PUNCT)
    cw, ch = W + PAD * 2, H + PAD * 2
    atlas = Image.new("RGBA", (cw * len(cells), ch), (0, 0, 0, 0))
    meta = {"cell": [cw, ch], "glyph": [W, H], "pad": PAD, "base": 0xE000, "letters": {}, "punct": {}}
    for i, key in enumerate(cells):
        px = runes[key][0] if key in runes else PUNCT[key]
        for x, y in px:
            atlas.putpixel((i * cw + PAD + x, PAD + y), (255, 255, 255, 255))
        if key in runes:
            meta["letters"][key] = {"cell": i, "code": 0xE000 + runes[key][1]}
        else:
            meta["punct"][key] = {"cell": i}
    out = "mods-unpacked/cejdan-StoryMode/art/runes"
    os.makedirs(out, exist_ok=True)
    atlas.save(os.path.join(out, "runes.png"))
    with open(os.path.join(out, "runes.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(meta, f, indent=1, sort_keys=True)
    # Key sheet: rune over its letter, 8x, for the preview and the curious.
    s = 8
    sheet = Image.new("RGB", (len(LETTERS) * (W + 3) * s, (H + 12) * s), (18, 6, 10))
    from PIL import ImageDraw
    d = ImageDraw.Draw(sheet)
    for i, key in enumerate(LETTERS):
        ox = i * (W + 3) * s + s
        for x, y in runes[key][0]:
            d.rectangle([ox + x * s, s + y * s, ox + x * s + s - 1, s + y * s + s - 1], fill=(255, 59, 48))
        d.text((ox + s, (H + 3) * s), key, fill=(230, 230, 230))
    os.makedirs("art/preview", exist_ok=True)
    sheet.save("art/preview/runes.png")
    print("runes:", len(LETTERS), "letters,", len(PUNCT), "marks")


if __name__ == "__main__":
    main()
