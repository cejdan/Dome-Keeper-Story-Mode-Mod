"""Story Mode's mode icon (#134): the horror in the deep, a dark tentacled
silhouette with two glowing eyes, rim-lit in violet.

Writes, from one drawing:
  art/loadout_storymode.png  70 x 40, real colors: the mode-select screen
                             draws loadout icons as they are
  art/icons/storymode.png    72 x 72, palette-encoded on row 12 (the tech-icon
                             row): the shop's Story Mode track root, drawn
                             through the palette shader like vanilla tech icons
                             (mod_main.gd provides it)
  art/preview/story_icon.png real colors at 6x
Colors are row 12 of palette_1_1.

Run from the Dome Keeper folder: python art/tools/make_horror_icon.py
"""
import math
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if len(sys.argv) > 1:
    ROOT = sys.argv[1]
OUT = os.path.join(ROOT, "mods-unpacked", "cejdan-StoryMode", "art", "loadout_storymode.png")
OUT_TECH = os.path.join(ROOT, "mods-unpacked", "cejdan-StoryMode", "art", "icons", "storymode.png")
PREVIEW = os.path.join(ROOT, "art", "preview", "story_icon.png")
PALETTE = os.path.join(ROOT, "systems", "style", "palettes", "palette_1_1.png")

W, H = 70, 40
ROW = 12
# Row 12 columns: 0 near-black, 1/2 night violet, 4/6/8 violet rim, 9 orchid, 10 pink glow.
OUTLINE, BODY, BODY2, RIM1, RIM2, RIM3, GLOW, EYE = 0, 1, 2, 4, 6, 8, 9, 10


def tentacle(mask, x0, y0, ang, length, r0, curl, wiggle, phase):
    """A tapering tentacle from (x0, y0), heading `ang` (radians), curling."""
    x, y, a = x0, y0, ang
    steps = int(length * 3)
    for i in range(steps):
        t = i / steps
        r = r0 * (1.0 - t) ** 0.9 + 0.35
        a += curl * t * t / steps * 6.0 + math.sin(phase + t * 7.0) * wiggle / steps
        x += math.cos(a) / 3.0
        y += math.sin(a) / 3.0
        disc(mask, x, y, r)


def disc(mask, cx, cy, r):
    for yy in range(int(cy - r - 1), int(cy + r + 2)):
        for xx in range(int(cx - r - 1), int(cx + r + 2)):
            if 0 <= xx < W and 0 <= yy < H and (xx + 0.5 - cx) ** 2 + (yy + 0.5 - cy) ** 2 <= r * r:
                mask[yy][xx] = True


def build():
    mask = [[False] * W for _ in range(H)]
    cx = 35
    # Head: a tall hooded dome narrowing to a crown, rising out of the dark.
    for yy in range(H):
        for xx in range(W):
            dx = (xx + 0.5 - cx) / 9.0
            dy = (yy + 0.5 - 16.0) / 14.0
            if dy < 0:
                dx *= 1.0 + (-dy) * 0.55
            if dx * dx + dy * dy <= 1.0 and yy < 30:
                mask[yy][xx] = True
    # Mantle flaring into the tentacle roots.
    for yy in range(21, 32):
        half = 7.5 + (yy - 21) * 1.0
        for xx in range(W):
            if abs(xx + 0.5 - cx) <= half:
                mask[yy][xx] = True
    # (x, y, heading, length, root radius, curl, wiggle, phase), mirrored left/right.
    half = [
        (29, 26, math.pi - 0.05, 36, 2.4, 2.1, 1.6, 0.0),     # long sweeper, curls up
        (30, 29, math.pi - 0.55, 24, 2.0, -1.6, 1.8, 2.1),    # low, curls under
        (32, 30, math.pi * 0.5 + 0.45, 9, 2.0, 0.9, 0.9, 1.9),  # short, hangs
        (28, 22, math.pi + 0.70, 22, 1.7, 2.8, 1.6, 2.7),     # rises along the side
        (29, 19, math.pi + 1.30, 15, 1.2, 2.6, 2.0, 0.9),     # reaches over the brow
    ]
    for (x, y, a, l, r, c, w, ph) in half:
        tentacle(mask, x, y, a, l, r, c, w, ph)
        tentacle(mask, 2 * cx - x, y, math.pi - a, l, r, -c, w, ph + 1.1)
    for yy in range(H):
        for xx in range(W):
            if xx in (0, W - 1) or yy in (0, H - 1):
                mask[yy][xx] = False
    return mask


def shade(mask):
    """Palette column per pixel (None = transparent)."""
    def m(x, y):
        return 0 <= x < W and 0 <= y < H and mask[y][x]
    out = [[None] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            if m(x, y):
                edge = not (m(x - 1, y) and m(x + 1, y) and m(x, y - 1) and m(x, y + 1))
                if edge:
                    out[y][x] = OUTLINE
                    continue
                lit = (not m(x - 2, y - 1)) or (not m(x - 1, y - 2)) or (not m(x, y - 2))
                lit2 = (not m(x - 3, y - 2)) or (not m(x - 2, y - 3))
                if lit:
                    out[y][x] = RIM3 if y < 12 else (RIM2 if y < 24 else RIM1)
                elif lit2 and y < 22:
                    out[y][x] = RIM1
                else:
                    # Lit from above: the crown a shade lighter, dithered into the dark below.
                    top = y < 14 or (y < 19 and (x + y) % 2 == 0)
                    out[y][x] = BODY2 if top else BODY
            elif any(m(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out[y][x] = OUTLINE
    # Eyes: narrow slits slanting down towards the middle, with a violet halo.
    for side in (-1, 1):
        pts = [(35 + side * 7, 14), (35 + side * 6, 14), (35 + side * 5, 15), (35 + side * 4, 15), (35 + side * 3, 16)]
        for (px, py) in pts:
            for gx in (-1, 0, 1):
                for gy in (-1, 0, 1):
                    if out[py + gy][px + gx] in (BODY, BODY2, RIM1):
                        out[py + gy][px + gx] = RIM2
        for (px, py) in pts:
            out[py][px] = GLOW
        for (px, py) in pts[1:4]:
            out[py][px] = EYE
    # A third eye, barely open, on the brow.
    out[9][35] = GLOW
    out[10][34] = RIM3
    out[10][36] = RIM3
    return out


def main():
    cols = shade(build())
    enc = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    pal = Image.open(PALETTE).convert("RGBA")
    real = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for y in range(H):
        for x in range(W):
            c = cols[y][x]
            if c is None:
                continue
            enc.putpixel((x, y), (c * 8, 0, ROW * 20, 255))
            real.putpixel((x, y), pal.getpixel((c * 10 + 5, ROW * 10 + 5)))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    real.save(OUT)
    tech = Image.new("RGBA", (72, 72), (0, 0, 0, 0))
    tech.paste(enc, ((72 - W) // 2, (72 - H) // 2 + 2))
    os.makedirs(os.path.dirname(OUT_TECH), exist_ok=True)
    tech.save(OUT_TECH)
    bg = Image.new("RGBA", (W + 8, H + 8), (46, 40, 62, 255))
    bg.alpha_composite(real, (4, 4))
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    bg.resize((bg.width * 6, bg.height * 6), Image.NEAREST).save(PREVIEW)
    print("wrote", OUT, OUT_TECH, "and", PREVIEW)


if __name__ == "__main__":
    main()
