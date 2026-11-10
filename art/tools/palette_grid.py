"""Show game-encoded sprites under every in-game palette, one row per palette, plus a true-size strip.

Usage (from the Dome Keeper folder):
    python art/tools/palette_grid.py <out.png> label=path.png label=path.png | label=path.png ...
A bare "|" adds a gap between groups.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
from palette_encode import PALETTES, decode  # noqa: E402

BG, PANEL, INK = (18, 18, 26, 255), (40, 40, 48, 255), (230, 230, 230, 255)
S, GAP = 5, 14


def main(out, specs):
    cols = [None if s == "|" else tuple(s.split("=", 1)) for s in specs]
    pals = sorted(p.stem for p in PALETTES.glob("palette_*.png") if "exp" not in p.stem)
    size = max(Image.open(c[1]).height for c in cols if c)
    cw = size * S + 8
    W = 60 + sum(cw if c else GAP for c in cols) + 8
    H = 22 + (len(pals) + 1) * (size * S + 6) + 10
    im = Image.new("RGBA", (W, H), PANEL)
    d = ImageDraw.Draw(im)
    x = 60
    for c in cols:
        if c:
            d.text((x, 4), c[0], fill=INK)
        x += cw if c else GAP
    for i, p in enumerate(pals + ["1x"]):
        y = 20 + i * (size * S + 6)
        d.text((6, y + size * S // 2 - 6), p.replace("palette_", "") if p != "1x" else "true size", fill=INK)
        x = 60
        for c in cols:
            if not c:
                x += GAP
                continue
            d.rectangle([x - 3, y - 2, x + cw - 6, y + size * S + 2], fill=BG)
            sp = decode(c[1], None, "palette_1_1" if p == "1x" else p)
            if p == "1x":
                im.alpha_composite(sp, (x + (size * S - sp.width) // 2, y + (size * S - sp.height) // 2))
            else:
                big = sp.resize((sp.width * S, sp.height * S), Image.NEAREST)
                im.alpha_composite(big, (x, y + (size - sp.height) * S // 2))
            x += cw
    im.save(out)
    print("wrote", out, im.size, len(pals), "palettes")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
