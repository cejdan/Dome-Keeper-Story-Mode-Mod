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

const RED := Color("d42a3c")


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


# A soft round glow of radius GLOW_R centred on c: rings that brighten in
# whole-pixel steps toward the middle (a radial gradient with constant bands,
# one draw). `strength` 1.0 is about 0.45 alpha at the core.
const GLOW_R := 20
static var _glow_tex: Texture2D = null


static func glow(ci: CanvasItem, c: Vector2, col: Color, strength: float = 1.0) -> void:
	if _glow_tex == null:
		var g := Gradient.new()
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		g.offsets = PackedFloat32Array([0.0, 0.3, 0.5, 0.68, 0.84, 0.97])
		g.colors = PackedColorArray([Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.34), Color(1, 1, 1, 0.24),
			Color(1, 1, 1, 0.15), Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = GLOW_R * 2
		t.height = GLOW_R * 2
		_glow_tex = t
	ci.draw_texture(_glow_tex, c.round() - Vector2(GLOW_R, GLOW_R), Color(col, clampf(strength, 0.0, 2.0)))


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


# ---------------------------------------------------------------- eyes (#382)
#
# Velle's eyes come in three kinds:
#   cave_eye()   the game's red cave eye (the FollowEye cave ornament) reused:
#                cracked dark socket, a red glow that heats up as the keeper
#                comes close, a black pupil that follows the keeper. Every
#                eye that only watches: the body, the walls (the laser eyes),
#                the chase.
#   small_eye()  a few pixels of the same red eye, strung along tentacles.
#   great_mini() a little copy of the great eye, on what can be hurt: the
#                chamber's tentacle tips, the finale's tentacle eyes and the
#                flyers they tear free as; and the health bar.
const CAVE_SHEET := "res://content/map/decorations/ornaments/halloweeneyes_sheet.png"
const CAVE_W := 22
const CAVE_H := 25
static var _cave_tex: Texture2D = null


static func _cave_texture() -> Texture2D:
	if _cave_tex == null:
		_cave_tex = load(CAVE_SHEET)
	return _cave_tex


# 0 open .. 1 shut: each eye blinks now and then, on its own clock.
static func _blink(t: float, seed: float) -> float:
	var b: float = fposmod(t * 0.37 + seed, 1.0)
	if b >= 0.06:
		return 0.0
	return 1.0 - absf(b / 0.03 - 1.0)


# The ornament's three layers (socket glow, pupil, cracked rim) the way the map
# places them, the glow lit the way FollowEye.gd lights it (redder as the
# keeper comes near), but always lit hard enough to show on the dark flesh.
# `seed` picks one of its five variants.
static func cave_eye(ci: CanvasItem, c: Vector2, to: Vector2, t: float, seed: float, mod: Color = Color.WHITE) -> void:
	var tex: Texture2D = _cave_texture()
	var v: int = posmod(int(floor(seed * 7.31 + 0.5)), 5)
	var o: Vector2 = (c - Vector2(CAVE_W * 0.5, CAVE_H * 0.5)).round()
	var d: Vector2 = to - c
	var heat: float = clampf(1200.0 / maxf(1.0, d.length()), 5.0, 8.0)
	var lit: Color = Color(heat, 1.15, 1.15) * mod
	if mod.r > 1.5 and mod.g > 1.5:
		lit = Color(9, 9, 9, mod.a)  # a hit flash: the socket goes white
	ci.draw_texture_rect_region(tex, Rect2(o, Vector2(CAVE_W, CAVE_H)), Rect2(v * CAVE_W, 0, CAVE_W, CAVE_H), lit)
	if _blink(t, seed) < 0.5:
		var look: Vector2 = (d * 0.1).limit_length(3.0).round()
		ci.draw_texture_rect_region(tex, Rect2(o + look, Vector2(CAVE_W, CAVE_H)), Rect2(v * CAVE_W, CAVE_H, CAVE_W, CAVE_H), mod)
	else:
		ci.draw_rect(Rect2((c + Vector2(-5, 0)).round(), Vector2(10, 1)), Color(EDGE, mod.a))
	ci.draw_texture_rect_region(tex, Rect2(o, Vector2(CAVE_W, CAVE_H)), Rect2(v * CAVE_W, CAVE_H * 2, CAVE_W, CAVE_H), mod)


# A tiny red eye in a dark ring, for rows of eyes along a tentacle.
static func small_eye(ci: CanvasItem, c: Vector2, to: Vector2, t: float, seed: float, mod: Color = Color.WHITE) -> void:
	disc(ci, c, 4.0, EDGE * mod)
	if _blink(t, seed) > 0.5:
		disc(ci, c, 3.0, FLESH_MID * mod)
		ci.draw_rect(Rect2((c + Vector2(-3, 0)).round(), Vector2(6, 1)), EDGE * mod)
		return
	disc(ci, c, 3.0, RED * mod)
	var ic: Vector2 = c + (to - c).limit_length(60.0) / 60.0
	ci.draw_rect(Rect2((ic + Vector2(-1, -1)).round(), Vector2(2, 2)), PUPIL * mod)


# A little great eye: dark almond outline, flesh lids, pale eyeball, orange
# iris with a slit pupil and a glint; it blinks. Sizes vary a little by seed.
static func great_mini(ci: CanvasItem, c: Vector2, to: Vector2, t: float, seed: float, scale: float = 1.0, mod: Color = Color.WHITE) -> void:
	var k: float = scale * (0.85 + 0.3 * fposmod(seed * 3.7, 1.0))
	var rx: float = maxf(3.0, round(8.0 * k))
	var ry: float = maxf(2.0, round(6.0 * k))
	var open: float = 1.0 - _blink(t, seed)
	ellipse(ci, c, rx + 1.0, ry + 1.0, EDGE * mod)
	ellipse(ci, c, rx, ry, FLESH_LIGHT * mod)
	var oy: float = ry * open
	if oy < 1.0:
		ci.draw_rect(Rect2((c + Vector2(-rx, 0)).round(), Vector2(rx * 2.0, 1)), EDGE * mod)
		return
	ellipse(ci, c, rx - 1.0, oy, SCLERA * mod)
	var ic: Vector2 = c + (to - c).limit_length(60.0) / 60.0 * Vector2(rx * 0.35, ry * 0.25)
	var irx: float = round(4.5 * k)
	var ir: float = minf(irx, oy)
	ellipse(ci, ic, irx, ir, IRIS_DEEP * mod)
	ellipse(ci, ic, maxf(1.0, irx - 1.0), maxf(1.0, ir - 1.0), IRIS * mod)
	var ph: float = maxf(1.0, round(ir * 1.4))
	ci.draw_rect(Rect2((ic + Vector2(0, -ph * 0.5)).round(), Vector2(1 if k < 0.8 else 2, ph)), PUPIL * mod)
	if k >= 0.8:
		ci.draw_rect(Rect2((ic + Vector2(-2, -ir * 0.5)).round(), Vector2(1, 1)), Color.WHITE * mod)


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
