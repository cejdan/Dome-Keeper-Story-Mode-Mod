extends RefCounted

# Pixel-art drawing helpers for the boss (#160): everything Velle is made of is
# drawn in code from whole-pixel rectangles, so it sits with the game's sprites.

const FLESH := Color("1b1030")
const FLESH_MID := Color("2f1b52")
const FLESH_LIGHT := Color("513085")
const SUCKER := Color("8a4fc4")
const EDGE := Color("0a0612")
const VIOLET := Color("6b5cff")
const VIOLET_LIGHT := Color("b8b0ff")
const SCLERA := Color("e9e2ff")
const IRIS := Color("ff9a1f")
const IRIS_DEEP := Color("c2500c")
const PUPIL := Color("14060a")
const WARN := Color("ff3b30")

const EYE_SHEET := "res://content/caves/teleportcave/teleporteye-mine-Sheet.png"
const EYE_FRAMES := 8
const EYE_SIZE := 24


# A filled disc of radius r, from three rectangles (two for tiny ones).
static func disc(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var ri: float = maxf(1.0, round(r))
	var cx: float = round(c.x)
	var cy: float = round(c.y)
	if ri <= 2.0:
		ci.draw_rect(Rect2(cx - ri, cy - ri, ri * 2.0, ri * 2.0), col)
		return
	var a: float = round(ri * 0.72)
	var b: float = maxf(1.0, round(ri * 0.42))
	ci.draw_rect(Rect2(cx - ri, cy - b, ri * 2.0, b * 2.0), col)
	ci.draw_rect(Rect2(cx - b, cy - ri, b * 2.0, ri * 2.0), col)
	ci.draw_rect(Rect2(cx - a, cy - a, a * 2.0, a * 2.0), col)


# A filled ellipse, one rectangle per pixel row. `cut` keeps only the rows from
# -ry up to ry * cut (1.0 = whole), for lids and domes.
static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, y_from: float = -1.0, y_to: float = 1.0) -> void:
	if rx < 1.0 or ry < 1.0:
		return
	var cx: float = round(c.x)
	var cy: float = round(c.y)
	var r: int = int(round(ry))
	for y in range(int(round(r * y_from)), int(round(r * y_to)) + 1):
		var f: float = 1.0 - (float(y) / ry) * (float(y) / ry)
		if f <= 0.0:
			continue
		var hw: float = round(rx * sqrt(f))
		if hw > 0.0:
			ci.draw_rect(Rect2(cx - hw, cy + y, hw * 2.0, 1.0), col)


# The points of a tentacle from a to b: a line with a travelling wave, pinned
# at both ends, shown up to `ext` (0..1) of its length.
static func tentacle_points(a: Vector2, b: Vector2, t: float, wave: float, phase: float, ext: float = 1.0, bend: float = 0.0) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var d: Vector2 = b - a
	var length: float = d.length()
	if length < 1.0 or ext <= 0.0:
		pts.append(a)
		return pts
	var n: Vector2 = d.orthogonal() / length
	var steps: int = maxi(3, int(length * ext / 3.0))
	for i in steps + 1:
		var u: float = float(i) / float(steps) * ext
		var env: float = sin(u * PI)
		var off: float = sin(u * 6.5 - t * 2.4 + phase) * wave * env + bend * env
		pts.append(a + d * u + n * off)
	return pts


# Draws a tentacle along `pts`, tapering from w0 to w1, with a dark outline, a
# lighter ridge and suckers. Returns its tip.
static func tentacle(ci: CanvasItem, pts: PackedVector2Array, w0: float, w1: float, col: Color = FLESH_MID, alpha: float = 1.0) -> Vector2:
	var n: int = pts.size()
	if n == 0:
		return Vector2.ZERO
	var edge: Color = Color(EDGE, alpha)
	var body: Color = Color(col, alpha)
	for i in n:
		var u: float = float(i) / float(maxi(1, n - 1))
		disc(ci, pts[i], lerpf(w0, w1, u) + 1.0, edge)
	for i in n:
		var u: float = float(i) / float(maxi(1, n - 1))
		disc(ci, pts[i], lerpf(w0, w1, u), body)
	# Ridge highlight and suckers, every few points.
	for i in range(2, n - 1, 3):
		var u: float = float(i) / float(maxi(1, n - 1))
		var w: float = lerpf(w0, w1, u)
		if w < 2.0:
			continue
		var dir: Vector2 = (pts[i + 1] - pts[i - 1]).normalized()
		var side: Vector2 = dir.orthogonal()
		var p: Vector2 = (pts[i] - side * (w * 0.45)).round()
		ci.draw_rect(Rect2(p, Vector2(2, 1)), Color(FLESH_LIGHT, alpha))
		if i % 2 == 0:
			var q: Vector2 = (pts[i] + side * (w * 0.5)).round()
			ci.draw_rect(Rect2(q, Vector2(1, 1)), Color(SUCKER, alpha))
	return pts[n - 1]


static var _eye_tex: Texture2D = null


static func eye_texture() -> Texture2D:
	if _eye_tex == null:
		_eye_tex = load(EYE_SHEET)
	return _eye_tex


# One of the game's teleport-cave eyes, centred on c. `frame` 0..7 (it looks
# around through the frames), `scale` whole numbers keep it crisp.
static func eye(ci: CanvasItem, c: Vector2, frame: int, scale: float = 1.0, mod: Color = Color.WHITE) -> void:
	var tex: Texture2D = eye_texture()
	if tex == null:
		disc(ci, c, 6.0 * scale, IRIS)
		return
	var s: float = EYE_SIZE * scale
	var f: int = posmod(frame, EYE_FRAMES)
	ci.draw_texture_rect_region(tex, Rect2((c - Vector2(s, s) * 0.5).round(), Vector2(s, s)), Rect2(f * EYE_SIZE, 0, EYE_SIZE, EYE_SIZE), mod)


# The eye frame that looks from `from` toward `to` (frames 4-7 glance sideways,
# 0-3 stare; picked by angle so a crowd of eyes all track the keeper).
static func eye_frame_toward(from: Vector2, to: Vector2, t: float, seed: float) -> int:
	var blink: float = fposmod(t * 0.37 + seed, 1.0)
	if blink < 0.06:
		return 0
	var d: Vector2 = to - from
	if d.length() < 30.0:
		return 2 + (int(t * 6.0 + seed * 10.0) % 2)
	return 4 + int(fposmod(d.angle() / TAU + seed * 0.1, 1.0) * 4.0) % 4


# A small pixel heart, top-left at p. `fill` 1.0 full, 0.0 empty (an outline).
const HEART_ROWS: Array = [
	[1, 2, 4, 5],
	[0, 1, 2, 3, 4, 5, 6],
	[0, 1, 2, 3, 4, 5, 6],
	[1, 2, 3, 4, 5],
	[2, 3, 4],
	[3],
]


static func heart(ci: CanvasItem, p: Vector2, full: bool, col: Color = Color("ff3b4f"), flash: bool = false) -> void:
	var o: Vector2 = p.round()
	ci.draw_rect(Rect2(o + Vector2(-1, -1), Vector2(9, 8)), Color(0, 0, 0, 0.0))
	for y in HEART_ROWS.size():
		for x: int in HEART_ROWS[y]:
			ci.draw_rect(Rect2(o + Vector2(x, y + 1), Vector2(1, 1)), Color(0.04, 0.02, 0.06, 0.95))
	for y in HEART_ROWS.size():
		for x: int in HEART_ROWS[y]:
			var c: Color = col if full else Color("3a2230")
			if flash:
				c = Color.WHITE
			ci.draw_rect(Rect2(o + Vector2(x, y), Vector2(1, 1)), c)
	if full and not flash:
		ci.draw_rect(Rect2(o + Vector2(1, 1), Vector2(1, 1)), Color("ffb3bd"))
