"""Velle's chamber (#361): living stone and stone stalactites.

Writes, into mods-unpacked/flantor-StoryMode/art/chamber/:
  stone.png     the still living stone (walls, floor, wall steps, stumps) and the
                stone stalactites, real colours, pixel for pixel in world px
  tendrils.png  FRAMES animation frames of the purple tentacles that dive in and
                out of the stone (only the pixels that differ from stone.png),
                in a COLS x ROWS grid
  shapes.json   the frame layout, and the collision outline of every wall step,
                stump and stalactite (arena-local world px)
and art/preview/chamber.png (stone + frame 0 on the chamber's dark backdrop).

Coordinates are arena-local: the chamber's open inside is x 0..480, y 0..240
(20 x 10 tiles of 24 px); its roof row is y -24..0; the undrillable wall ring
is 2 tiles thick on the sides and under the floor. The images start at
(-48, -24), so they cover the ring.

Run from the Dome Keeper folder:  python art/tools/make_chamber_art.py
The design was agreed on the concept canvas (#361, "round 4" + the final still).
"""
import json, math, os, random
from collections import defaultdict
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "mods-unpacked", "flantor-StoryMode", "art", "chamber")
PREVIEW = os.path.join(ROOT, "art", "preview", "chamber.png")

TILE = 24
AW, AH = 480, 240            # the chamber's inside
WALL = 48                    # the undrillable ring: 2 tiles
OX, OY = WALL, TILE          # image origin offset: arena (0,0) is image (OX,OY)
IW, IH = AW + 2 * WALL, AH + WALL + TILE
FRAMES, COLS, FPS = 20, 5, 11
ENTRY_TILES = [3, 4, 15, 16]  # roof tiles left as normal drillable rock (data/boss.gd)


def hexc(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# ---------------------------------------------------------------- noise

def _h(ix, iy, salt=0):
    n = (ix * 374761393 + iy * 668265263 + salt * 2147483647) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def vnoise(x, y, salt=0):
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = _h(ix, iy, salt), _h(ix + 1, iy, salt)
    c, d = _h(ix, iy + 1, salt), _h(ix + 1, iy + 1, salt)
    return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy


def fbm(x, y, salt=0):
    return 0.6 * vnoise(x, y, salt) + 0.3 * vnoise(x * 2.1, y * 2.1, salt + 7) + 0.1 * vnoise(x * 4.3, y * 4.3, salt + 13)


# ---------------------------------------------------------------- shapes (signed distance, negative inside)

def sd_box(px, py, cx, cy, hw, hh, r):
    qx, qy = abs(px - cx) - hw + r, abs(py - cy) - hh + r
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def sd_seg(px, py, ax, ay, bx, by, ra, rb):
    pax, pay, bax, bay = px - ax, py - ay, bx - ax, by - ay
    h = max(0.0, min(1.0, (pax * bax + pay * bay) / (bax * bax + bay * bay)))
    return math.hypot(pax - bax * h, pay - bay * h) - (ra + (rb - ra) * h)


def smin(a, b, k):
    h = max(0.0, min(1.0, 0.5 + 0.5 * (b - a) / k))
    return b + (a - b) * h - k * h * (1 - h)


def step_sdf(x, y, side):
    """A wall step: 3 tiles tall against the wall, a lower step at 1.5 tiles,
    flat tops with a slight lip."""
    wx = 0 if side < 0 else AW
    lx = (x - wx) if side < 0 else (wx - x)
    k = max(0.0, (y - 168) / 72.0)
    tall = sd_box(lx, y, 10 + 4 * k, 207, 20 + 5 * k, 37, 5)
    lip = sd_box(lx, y, 13, 172, 22, 4, 3)
    step = sd_box(lx, y, 34, 225, 25 + 4 * k, 19, 6)
    lip2 = sd_box(lx, y, 38, 208, 22, 3, 3)
    foot = sd_box(lx, y, 52, 238, 20, 6, 5)
    d = smin(smin(tall, lip, 3.0), smin(step, lip2, 3.0), 6.0)
    d = smin(d, foot, 9.0)
    d += (fbm(lx * 0.11, y * 0.11, 31 if side < 0 else 37) - 0.5) * 3.5 * min(1.0, max(0.0, (y - 178) / 8.0)) * (0.0 if abs(y - 208) < 4 else 1.0)
    return d


def stump_sdf(x, y, side):
    """A stump beside Velle's lobes: 2 tiles tall, pinched waist, flat top."""
    cx = AW / 2 + side * 104
    k = max(0.0, (y - 196) / 44.0)
    waist = 2.0 * math.sin(k * math.pi)
    d = sd_box(x, y, cx, 220, 13 - waist, 22, 5)
    lip = sd_box(x, y, cx, 199, 16, 3, 3)
    base = sd_box(x, y, cx, 240, 22, 7, 5)
    d = smin(smin(d, lip, 3.0), base, 9.0)
    d += (fbm(x * 0.12, y * 0.12, 41 if side < 0 else 43) - 0.5) * 2.5 * min(1.0, max(0.0, (y - 204) / 8.0))
    return d


def wall_sdf(x, y, side):
    cx = -WALL / 2 if side < 0 else AW + WALL / 2
    d = sd_box(x, y, cx, (0 + AH + WALL) / 2, WALL / 2 + 0.5, (AH + WALL) / 2 + 2, 1)
    if y < 168:
        d += (fbm(x * 0.1, y * 0.1, 301 if side < 0 else 303) - 0.5) * 4.0
    return max(d, -y)


def floor_sdf(x, y):
    return sd_box(x, y, AW / 2, AH + WALL / 2, AW / 2 + WALL + 1, WALL / 2 + 1, 1)


def side_sdf(side):
    return lambda x, y: smin(wall_sdf(x, y, side), step_sdf(x, y, side), 5.0)


def shell_sdf(x, y):
    d = smin(side_sdf(-1)(x, y), side_sdf(1)(x, y), 5.0)
    d = smin(d, floor_sdf(x, y), 6.0)
    for s in (-1, 1):
        d = smin(d, stump_sdf(x, y, s), 6.0)
    return d


# (x at the roof, length, root half-width, lean over its length, seed). Four reach
# down near the wall steps and stumps for the Beastmaster to climb; one hangs
# about 4 tiles above the eye. None touches an entry tile.
STALACTITES = [(22, 34, 13, 4, 1), (46, 84, 14, 5, 2), (138, 26, 9, -2, 4), (184, 104, 17, -6, 5),
               (222, 40, 11, 3, 6), (266, 116, 18, 5, 7), (306, 34, 10, -2, 8), (338, 100, 16, -7, 9),
               (428, 80, 15, -5, 11), (462, 30, 11, -3, 12)]


def one_stalactite_sdf(x, y, st):
    sx, ln, hw, lean, seed = st
    if abs(x - sx) > hw + abs(lean) + 6 or y > ln + 4:
        return 1e9
    d = 1e9
    n = 4
    for i in range(n):
        u0, u1 = i / n, (i + 1) / n
        ax, ay = sx + lean * u0 * u0 + (_h(seed, i, 3) - 0.5) * 3, -8 + (ln + 8) * u0
        bx, by = sx + lean * u1 * u1 + (_h(seed, i + 1, 3) - 0.5) * 3, -8 + (ln + 8) * u1
        ra = hw * (1 - u0) ** 0.85 + 1.2 + (_h(seed, i, 4) - 0.5) * 3 * (1 - u0)
        rb = hw * (1 - u1) ** 0.85 + 1.2
        d = min(d, sd_seg(x, y, ax, ay, bx, by, ra, rb))
    return d + (fbm(x * 0.18, y * 0.18, 101) - 0.5) * 2.2


def stal_sdf(x, y):
    return min(one_stalactite_sdf(x, y, st) for st in STALACTITES)


# ---------------------------------------------------------------- colours

STONE = [hexc(c) for c in ("070d1a", "10203c", "1a2f52", "29466f", "44648f")]   # the chamber's own rock
EDGE = hexc("03060c")
STAL = [hexc(c) for c in ("070d1a", "10203c", "1c3358", "2c4a78", "4a6c9e")]
TEN = [hexc(c) for c in ("1b1030", "2f1b52", "513085", "7450b0", "a582e0")]          # Velle's purples
TEN_EDGE = hexc("0a0514")
LIGHT = (-0.5, -0.86)
BAYER = [[0.0, 0.5], [0.75, 0.25]]


def lambert(nx, ny):
    return max(0.0, nx * LIGHT[0] + ny * LIGHT[1])


def ramp(cols, v, x, y, dither=0.25):
    f = v * (len(cols) - 1) + (BAYER[y & 1][x & 1] - 0.4) * dither
    return cols[max(0, min(len(cols) - 1, int(round(f))))]


def grad(f, x, y):
    e = 0.75
    nx = f(x + e, y) - f(x - e, y)
    ny = f(x, y + e) - f(x, y - e)
    l = math.hypot(nx, ny) or 1.0
    return nx / l, ny / l


# ---------------------------------------------------------------- the still stone

def shell_field():
    """{(x, y): (d, nx, ny)} for every arena-local pixel of the living stone."""
    out = {}
    for y in range(0, AH + WALL):
        for x in range(-WALL, AW + WALL):
            d = shell_sdf(x + 0.5, y + 0.5)
            if d < 0.5:
                nx, ny = grad(shell_sdf, x + 0.5, y + 0.5)
                out[(x, y)] = (d, nx, ny)
    return out


def stone_px(x, y, d, nx, ny):
    if d > -1.2:
        return EDGE
    lit = lambert(nx, ny)
    strata = 0.5 + 0.5 * math.sin(y * 0.42 + fbm(x * 0.08, y * 0.08, 201) * 4.0)
    v = 0.15 + 0.55 * lit + 0.12 * strata + 0.12 * (fbm(x * 0.25, y * 0.25, 203) - 0.5)
    if abs(fbm(x * 0.07, y * 0.09, 205) - 0.5) < 0.016:
        return STONE[0]
    if -d < 2.4 and ny < -0.6:
        return STONE[4]          # a light rim on every top you can stand on
    return ramp(STONE, max(0.0, min(1.0, v)), x, y)


def draw_stalactites(img):
    px = img.load()
    for y in range(-1, 130):
        for x in range(0, AW):
            d = stal_sdf(x + 0.5, y + 0.5)
            if d >= 0.5:
                continue
            if d > -1.0:
                c = EDGE
            else:
                nx, ny = grad(stal_sdf, x + 0.5, y + 0.5)
                lit = lambert(nx, ny)
                strata = 0.5 + 0.5 * math.sin(y * 0.55 + fbm(x * 0.1, y * 0.1, 103) * 5)
                v = 0.15 + 0.6 * lit + 0.12 * strata
                crack = abs(fbm(x * 0.09, y * 0.06, 105) - 0.5) < 0.02
                c = STAL[0] if crack else ramp(STAL, max(0, min(1, v)), x, y)
            px[x + OX, y + OY] = c + (255,)


# ---------------------------------------------------------------- tentacles

def catmull(pts, steps):
    out = []
    for i in range(len(pts) - 1):
        p0, p1, p2, p3 = pts[max(0, i - 1)], pts[i], pts[i + 1], pts[min(len(pts) - 1, i + 2)]
        for k in range(steps):
            t = k / steps
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2 +
                                    (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in (0, 1)))
    out.append(pts[-1])
    return out


def make_tendrils(sdf, bbox, seed, n, curls):
    """n paths through one region that enter and leave through its outline (no
    tips show); the first `curls` loop round once and cross themselves."""
    rnd = random.Random(seed)
    x0, y0, x1, y1 = bbox

    def edge():
        for _ in range(4000):
            p = (rnd.uniform(x0, x1), rnd.uniform(y0, y1))
            if abs(sdf(p[0], p[1])) < 1.0:
                gx, gy = grad(sdf, p[0], p[1])
                return (p[0] + gx * 6, p[1] + gy * 6)
        return (x0, y1)

    tens = []
    for k in range(n):
        a, b = edge(), edge()
        inside = []
        while len(inside) < 2:
            p = (rnd.uniform(x0, x1), rnd.uniform(y0, y1))
            if sdf(p[0], p[1]) < -8:
                inside.append(p)
        ctrl = [a, inside[0]]
        if k < curls:
            cx, cy = inside[0]
            rr = rnd.uniform(6, 9)
            a0 = math.atan2(a[1] - cy, a[0] - cx)
            for j in range(1, 9):
                ang = a0 + j * (2 * math.pi * 1.15) / 8
                q = (cx + math.cos(ang) * rr, cy + math.sin(ang) * rr)
                if sdf(q[0], q[1]) < -3:
                    ctrl.append(q)
        ctrl += [inside[1], b]
        pts = catmull(ctrl, 16)
        s = [0.0]
        for i in range(1, len(pts)):
            s.append(s[-1] + math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]))
        r = [5.2, 4.0, 3.1, 2.4][k % 4] + rnd.uniform(-0.2, 0.3)
        tens.append({"pts": pts, "s": s, "r": r, "ph": rnd.uniform(0, 6.28), "dir": rnd.choice((-1, 1))})
    return tens


REGIONS = [   # (sdf, bbox, seed, tentacles, curls): 2 per side wall, 3 along the floor, 1 per stump
    (side_sdf(-1), (-WALL - 2, 0, 84, AH + 4), 1500, 2, 1),
    (side_sdf(1), (AW - 84, 0, AW + WALL + 2, AH + 4), 1513, 2, 1),
    (floor_sdf, (-4, AH - 2, AW + 4, AH + WALL + 2), 1526, 3, 1),
    (lambda x, y: stump_sdf(x, y, -1), (AW / 2 - 136, 190, AW / 2 - 72, AH + 4), 1539, 1, 0),
    (lambda x, y: stump_sdf(x, y, 1), (AW / 2 + 72, 190, AW / 2 + 136, AH + 4), 1552, 1, 0),
]


def buried(ten, si):
    b = math.sin(si * 0.055 + ten["ph"] * 1.7)
    return max(0.0, min(1.0, (-b - 0.15) / 0.3))   # 0 on the surface .. 1 under the stone


def tentacle_frame(field, stone_img, tens, t):
    """The frame at loop time t (0..1): pixels that differ from the still stone."""
    zb, seam, groove = {}, {}, set()
    for k, ten in enumerate(tens):
        pts, s, r0 = ten["pts"], ten["s"], ten["r"]
        for i in range(len(pts) - 1):
            ax, ay = pts[i]
            bx, by = pts[i + 1]
            dx, dy = bx - ax, by - ay
            l = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / l, dx / l
            sub = max(1, int(l / 0.7))
            for j in range(sub):
                u = j / sub
                si = s[i] + (s[i + 1] - s[i]) * u
                off = math.sin(si * 0.14 - ten["dir"] * t * 2 * math.pi + ten["ph"]) * 1.3
                pulse = max(0.0, math.sin(si * 0.06 - t * 2 * math.pi + ten["ph"])) ** 4
                r = r0 * (1 + 0.28 * pulse)
                cx, cy = ax + dx * u + nx * off, ay + dy * u + ny * off
                bur = buried(ten, si)
                z = math.sin(si * 0.045 + ten["ph"]) + k * 0.01
                along = si - ten["dir"] * t * (2 * math.pi / 0.14)
                for yy in range(int(cy - r - 3), int(cy + r + 4)):
                    for xx in range(int(cx - r - 3), int(cx + r + 4)):
                        if (xx, yy) not in field:
                            continue
                        dd = math.hypot(xx + 0.5 - cx, yy + 0.5 - cy)
                        if bur > 0.5:
                            if dd <= r * 0.8:
                                seam[(xx, yy)] = max(seam.get((xx, yy), 0.0), (1 - dd / (r * 0.8)) * (0.4 + 0.6 * pulse))
                            continue
                        if dd <= r:
                            q = dd / r
                            cur = zb.get((xx, yy))
                            same = cur is not None and cur[6] is ten and abs(cur[8] - si) < r0 * 4
                            if cur is None or (same and q < cur[1]) or (not same and z > cur[0]):
                                zb[(xx, yy)] = (z, q, (xx + 0.5 - cx) / (dd or 1), (yy + 0.5 - cy) / (dd or 1), pulse, along, ten, bur, si)
                        elif dd <= r + 1.6:
                            groove.add((xx, yy))
    frame = Image.new("RGBA", (IW, IH), (0, 0, 0, 0))
    fp, sp = frame.load(), stone_img.load()
    for (x, y), (d, nx, ny) in field.items():
        e = zb.get((x, y))
        c = None
        if e is not None:
            z, q, tnx, tny, pulse, along, ten, bur, _si = e
            if q > 0.84:
                c = TEN_EDGE
            else:
                tube = math.cos(q * math.pi / 2)
                v = 0.12 + 0.4 * tube + 0.2 * lambert(tnx, tny) + 0.3 * pulse - 0.3 * bur
                if (along % 6.0) < 1.0 and q < 0.75:
                    v -= 0.18
                c = ramp(TEN, max(0.0, min(1.0, v)), x, y)
                if ten["r"] > 4.5 and q < 0.3 and int(along / 3.0) % 5 == 0:
                    c = TEN[3]
        elif d > -1.2:
            continue
        elif (x, y) in groove:
            c = STONE[0]
        else:
            sv = seam.get((x, y), 0.0)
            if sv > 0.15:
                base = sp[x + OX, y + OY][:3]
                kk = min(1.0, sv) * 0.55
                c = tuple(int(base[i] + (TEN[2][i] - base[i]) * kk) for i in range(3))
        if c is not None:
            fp[x + OX, y + OY] = c + (255,)
    return frame


# ---------------------------------------------------------------- collision outlines

def outline(mask):
    """The outer loop of a set of filled pixels, along pixel edges, as corner points."""
    edges = {}
    for (x, y) in mask:
        if (x, y - 1) not in mask:
            edges[(x, y)] = (x + 1, y)
        if (x + 1, y) not in mask:
            edges[(x + 1, y)] = (x + 1, y + 1)
        if (x, y + 1) not in mask:
            edges[(x + 1, y + 1)] = (x, y + 1)
        if (x - 1, y) not in mask:
            edges[(x, y + 1)] = (x, y)
    # the loop through the top-left-most corner is the outer one
    start = min(edges, key=lambda p: (p[1], p[0]))
    loop, p = [start], edges[start]
    while p != start and len(loop) < 100000:
        loop.append(p)
        p = edges[p]
    return loop


def rdp(pts, eps):
    if len(pts) < 3:
        return pts
    a, b = pts[0], pts[-1]
    dx, dy = b[0] - a[0], b[1] - a[1]
    l = math.hypot(dx, dy) or 1.0
    best, idx = 0.0, 0
    for i in range(1, len(pts) - 1):
        d = abs(dy * pts[i][0] - dx * pts[i][1] + b[0] * a[1] - b[1] * a[0]) / l
        if d > best:
            best, idx = d, i
    if best > eps:
        return rdp(pts[:idx + 1], eps)[:-1] + rdp(pts[idx:], eps)
    return [a, b]


def simplify_loop(loop, eps=0.8):
    # split the closed loop at its two farthest-apart points, simplify each half
    i0 = 0
    i1 = max(range(len(loop)), key=lambda i: (loop[i][0] - loop[0][0]) ** 2 + (loop[i][1] - loop[0][1]) ** 2)
    a = rdp(loop[i0:i1 + 1], eps)
    b = rdp(loop[i1:] + [loop[0]], eps)
    return a[:-1] + b[:-1]


def body_outline(sdf, x0, y0, x1, y1):
    mask = set()
    for y in range(y0, y1):
        for x in range(x0, x1):
            if sdf(x + 0.5, y + 0.5) < 0:
                mask.add((x, y))
    if not mask:
        return []
    return [[float(p[0]), float(p[1])] for p in simplify_loop(outline(mask))]


def bodies():
    out = []
    for side, name in ((-1, "step_left"), (1, "step_right")):
        x0, x1 = (-8, 90) if side < 0 else (AW - 90, AW + 8)
        out.append({"name": name, "points": body_outline(lambda x, y, s=side: step_sdf(x, y, s), x0, 150, x1, AH + 2)})
    for side, name in ((-1, "stump_left"), (1, "stump_right")):
        cx = int(AW / 2 + side * 104)
        out.append({"name": name, "points": body_outline(lambda x, y, s=side: stump_sdf(x, y, s), cx - 32, 188, cx + 32, AH + 2)})
    for i, st in enumerate(STALACTITES):
        sx, ln, hw = st[0], st[1], st[2]
        out.append({"name": "stalactite_%d" % i, "points": body_outline(lambda x, y, st=st: max(one_stalactite_sdf(x, y, st), -2 - y),
                                                                     int(sx - hw - 14), -3, int(sx + hw + 14), ln + 6)})
    return out


# ---------------------------------------------------------------- main

def main():
    os.makedirs(OUT, exist_ok=True)
    for st in STALACTITES:
        for t in ENTRY_TILES:
            for x in range(t * TILE, (t + 1) * TILE):
                assert one_stalactite_sdf(x + 0.5, 0.5, st) >= 0, "a stalactite root touches entry tile %d" % t
    field = shell_field()
    stone = Image.new("RGBA", (IW, IH), (0, 0, 0, 0))
    px = stone.load()
    for (x, y), (d, nx, ny) in field.items():
        px[x + OX, y + OY] = stone_px(x, y, d, nx, ny) + (255,)
    draw_stalactites(stone)
    stone.save(os.path.join(OUT, "stone.png"))
    print("stone.png", stone.size)

    tens = []
    for sdf, bbox, seed, n, curls in REGIONS:
        tens += make_tendrils(sdf, bbox, seed, n, curls)
    rows = (FRAMES + COLS - 1) // COLS
    atlas = Image.new("RGBA", (IW * COLS, IH * rows), (0, 0, 0, 0))
    first = None
    for i in range(FRAMES):
        fr = tentacle_frame(field, stone, tens, i / FRAMES)
        atlas.paste(fr, ((i % COLS) * IW, (i // COLS) * IH))
        if first is None:
            first = fr
        print("frame", i, flush=True)
    atlas.save(os.path.join(OUT, "tendrils.png"), optimize=True)

    shapes = {"origin": [-OX, -OY], "size": [IW, IH], "frames": FRAMES, "cols": COLS, "fps": FPS,
              "entry_tiles": ENTRY_TILES, "bodies": bodies()}
    with open(os.path.join(OUT, "shapes.json"), "w") as f:
        json.dump(shapes, f, indent=1)
    print("bodies", [(b["name"], len(b["points"])) for b in shapes["bodies"]])

    prev = Image.new("RGBA", (IW, IH), (11, 19, 34, 255))
    prev.alpha_composite(stone)
    prev.alpha_composite(first)
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    prev.resize((IW * 2, IH * 2), Image.NEAREST).convert("RGB").save(PREVIEW)
    print("done")


if __name__ == "__main__":
    main()
