extends RefCounted

# The ship's placeholder art (#368, real art in #371): a Halcyon Minerals
# pickup vessel, drawn in code from flat polygons in the game's chunky pixel
# style, and the third ocean tentacle's coil around it.
#
# Ship space: x toward the nose, y down, the origin in the middle of the hull.
# The hull runs from the engine bells (x -146) to the nose (x 124), the fin's
# top is at y -56, and with its legs out the feet stand at y FOOT_Y.
#
#   ShipArt.draw_ship(ci, legs, visor, lights, scorched, rim)
#       legs 0 folded .. 1 out; visor 0 shut .. 1 open (the nose door lifts);
#       lights on/off (windows lit); scorched: the ocean's burns, a crack and
#       dark windows; rim: a magenta silhouette under it all that the ocean's
#       shader turns into the hot rim under the lava (never draw it elsewhere).
#   ShipArt.coil_pieces() -> the coil's path, split into the pieces drawn
#       behind the ship and in front of it.

const ShipData = preload("res://mods-unpacked/flantor-StoryMode/data/ship.gd")

const RIM_KEY := Color(1, 0, 1)   # the ocean shader's rim marker

const HULL := [Vector2(-116, -22), Vector2(-104, -28), Vector2(-40, -30), Vector2(36, -30), Vector2(70, -26), Vector2(94, -18), Vector2(96, 18), Vector2(-100, 20), Vector2(-116, 12)]
const VISOR := [Vector2(94, -18), Vector2(112, -10), Vector2(121, -2), Vector2(124, 4), Vector2(118, 12), Vector2(106, 17), Vector2(96, 18)]
const VISOR_HINGE := Vector2(94, -18)
const DOORWAY := [Vector2(88, -14), Vector2(95, -15), Vector2(96, 17), Vector2(88, 17)]
const BRIDGE := [Vector2(30, -30), Vector2(42, -43), Vector2(74, -43), Vector2(90, -29)]
const SCREEN := [Vector2(75, -41), Vector2(85, -31), Vector2(80, -31), Vector2(72, -41)]
const FIN := [Vector2(-112, -24), Vector2(-126, -56), Vector2(-108, -56), Vector2(-86, -29)]
const ENG_TOP := [Vector2(-138, -24), Vector2(-104, -24), Vector2(-102, -17), Vector2(-104, -10), Vector2(-138, -10)]
const ENG_BOT := [Vector2(-138, 2), Vector2(-104, 2), Vector2(-102, 9), Vector2(-104, 16), Vector2(-138, 16)]
const NOZ_TOP := [Vector2(-147, -27), Vector2(-138, -23), Vector2(-138, -11), Vector2(-147, -7)]
const NOZ_BOT := [Vector2(-147, -1), Vector2(-138, 3), Vector2(-138, 15), Vector2(-147, 19)]
const POD := [Vector2(-78, 19), Vector2(34, 19), Vector2(30, 30), Vector2(-74, 30)]
const LEGS := [-94.0, 66.0]       # leg hinges' x, on the hull's belly (y 20)
const LEG_TOP := 20.0
const FOOT_Y := 20.0 + ShipData.LEG_PX + 2.0
# Nozzle mouths (ship space), for the plume.
const PLUMES := [Vector2(-147, -17), Vector2(-147, 9)]
# The nose door's opening (where the tube meets the ship).
const DOOR := Vector2(96, 2)
const DOOR_HALF_H := 15.0
# Running lights.
const NAV_TOP := Vector2(-117, -56)
const NAV_NOSE := Vector2(118, -6)
const BEACON_AT := Vector2(58, -44)

static var _font: FontFile = null
static var _cut: Dictionary = {}


static func _font_small() -> FontFile:
	if _font == null:
		_font = (load("res://gui/fonts/small_pixel.ttf") as FontFile).duplicate()
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.hinting = TextServer.HINTING_NONE
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return _font


static func _pv(a: Array) -> PackedVector2Array:
	var p := PackedVector2Array()
	for v in a:
		p.append(v)
	return p


static func _grow(poly: Array, by: float) -> Array:
	return Geometry2D.offset_polygon(_pv(poly), by, Geometry2D.JOIN_MITER)


# The hull's polygon cut by a band of rows y0..y1 (cached).
static func _band(y0: float, y1: float, x0: float = -200.0, x1: float = 200.0) -> Array:
	var key: String = "%s|%s|%s|%s" % [y0, y1, x0, x1]
	if not _cut.has(key):
		var r := PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])
		_cut[key] = Geometry2D.intersect_polygons(_pv(HULL), r)
	return _cut[key]


static func _fill(ci: CanvasItem, polys: Array, col: Color) -> void:
	for p in polys:
		if p is PackedVector2Array and p.size() >= 3:
			ci.draw_colored_polygon(p, col)


static func visor_points(visor: float) -> PackedVector2Array:
	var a: float = -1.15 * clampf(visor, 0.0, 1.0)
	var out := PackedVector2Array()
	for v: Vector2 in VISOR:
		out.append(VISOR_HINGE + (v - VISOR_HINGE).rotated(a))
	return out


const PARTS := [FIN, NOZ_TOP, NOZ_BOT, ENG_TOP, ENG_BOT, POD, HULL, BRIDGE]
# The body's box in ship space (everything but the legs, the visor and the plume).
const BODY_RECT := Rect2(-152, -62, 282, 98)


# The whole ship in one go (the ocean's bake): rim, legs, body, nose.
static func draw_ship(ci: CanvasItem, legs: float, visor: float, lights: bool, scorched: bool, rim: bool) -> void:
	var vis: PackedVector2Array = visor_points(visor)
	# The ocean's hot rim, under everything.
	if rim:
		for p in PARTS:
			_fill(ci, _grow(p, 2.5), RIM_KEY)
		_fill(ci, Geometry2D.offset_polygon(vis, 2.5, Geometry2D.JOIN_MITER), RIM_KEY)
	_draw_legs(ci, legs, rim)
	draw_body(ci, lights, scorched)
	draw_nose(ci, visor, lights)


static func draw_legs(ci: CanvasItem, legs: float) -> void:
	_draw_legs(ci, legs, false)


# Everything that never moves (baked once into a texture by endgame/ship.gd).
static func draw_body(ci: CanvasItem, lights: bool, scorched: bool) -> void:
	# Outlines, then fills.
	for p in PARTS:
		_fill(ci, _grow(p, 1.0), ShipData.OUTLINE)
	# Fin with the company sun.
	ci.draw_colored_polygon(_pv(FIN), ShipData.HULL_MID)
	ci.draw_colored_polygon(_pv([Vector2(-112, -24), Vector2(-118, -38), Vector2(-100, -38), Vector2(-94, -27)]), ShipData.HULL_DARK)
	ci.draw_rect(Rect2(-122, -52, 14, 2), ShipData.BRAND)
	_sun(ci, Vector2(-113, -44), 4.0)
	# Engines and bells.
	for p in [NOZ_TOP, NOZ_BOT]:
		ci.draw_colored_polygon(_pv(p), ShipData.HULL_DARK)
	ci.draw_rect(Rect2(-146, -22, 2, 10), ShipData.OUTLINE)
	ci.draw_rect(Rect2(-146, 4, 2, 10), ShipData.OUTLINE)
	for p in [ENG_TOP, ENG_BOT]:
		ci.draw_colored_polygon(_pv(p), ShipData.HULL_MID)
	ci.draw_rect(Rect2(-138, -24, 34, 3), ShipData.HULL)
	ci.draw_rect(Rect2(-138, 2, 34, 3), ShipData.HULL)
	for x in [-130, -122, -114]:
		ci.draw_rect(Rect2(x, -21, 1, 11), ShipData.HULL_DARK)
		ci.draw_rect(Rect2(x, 5, 1, 11), ShipData.HULL_DARK)
	# The cargo pod under the belly, hazard ends.
	ci.draw_colored_polygon(_pv(POD), ShipData.HULL_DARK)
	for x in range(-68, 30, 12):
		ci.draw_rect(Rect2(x, 21, 1, 8), ShipData.OUTLINE)
	_hazard(ci, Rect2(-76, 21, 10, 8))
	_hazard(ci, Rect2(20, 21, 10, 8))
	# The hull: dark belly, mid sides, light top.
	ci.draw_colored_polygon(_pv(HULL), ShipData.HULL_MID)
	_fill(ci, _band(-40.0, -15.0), ShipData.HULL)
	_fill(ci, _band(9.0, 40.0), ShipData.HULL_DARK)
	_fill(ci, _band(-40.0, -27.0), Color(ShipData.HULL.lightened(0.25)))
	# Halcyon's stripe along the hull and the seams.
	_fill(ci, _band(1.0, 6.0, -114.0, 95.0), ShipData.BRAND)
	_fill(ci, _band(6.0, 7.0, -114.0, 95.0), ShipData.BRAND_DARK)
	for x in [-84, -56, -26, 4, 32, 60]:
		ci.draw_rect(Rect2(x, -27 if x < 36 else -24, 1, 27 if x < 36 else 24), ShipData.HULL_DARK)
		ci.draw_rect(Rect2(x, 8, 1, 11), ShipData.OUTLINE)
	# The name, and the tail number on the upper engine.
	var f: FontFile = _font_small()
	# In two words, so the coil's bands round the hull in the ocean leave both readable.
	ci.draw_string(f, Vector2(-106, -17), "HALCYON", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, ShipData.BRAND)
	ci.draw_string(f, Vector2(-31, -17), "MINERALS", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, ShipData.BRAND)
	ci.draw_string(f, Vector2(-135, -12), "HM-07", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, ShipData.OUTLINE)
	# Portholes along the side.
	for x in [-6, 8, 22]:
		ci.draw_rect(Rect2(x, -10, 5, 4), ShipData.OUTLINE)
		ci.draw_rect(Rect2(x + 1, -9, 3, 2), ShipData.WINDOW_LIT if lights and not scorched else ShipData.GLASS_DARK)
	# The bridge and its glass.
	ci.draw_colored_polygon(_pv(BRIDGE), ShipData.HULL)
	ci.draw_rect(Rect2(42, -43, 32, 2), ShipData.HULL.lightened(0.25))
	for i in 4:
		ci.draw_rect(Rect2(45 + i * 7, -39, 5, 5), ShipData.OUTLINE)
		ci.draw_rect(Rect2(46 + i * 7, -38, 3, 3), (ShipData.WINDOW_LIT if lights and not scorched else ShipData.GLASS_DARK))
	ci.draw_colored_polygon(_pv(SCREEN), ShipData.GLASS if not scorched else ShipData.GLASS_DARK)
	ci.draw_line(Vector2(75, -40), Vector2(78, -37), Color(1, 1, 1, 0.8), 1.0)
	if scorched:
		_scorch(ci)


# The nose: the doorway behind the visor, and the visor (the door) itself.
static func draw_nose(ci: CanvasItem, visor: float, lights: bool) -> void:
	var vis: PackedVector2Array = visor_points(visor)
	if visor > 0.02:
		ci.draw_colored_polygon(_pv(DOORWAY), Color("0e1218"))
		ci.draw_rect(Rect2(88, 12, 8, 4), ShipData.WINDOW_LIT if lights else ShipData.HULL_DARK)
		ci.draw_rect(Rect2(88, -14, 8, 2), ShipData.HULL_DARK)
	ci.draw_colored_polygon(Geometry2D.offset_polygon(vis, 1.0, Geometry2D.JOIN_MITER)[0], ShipData.OUTLINE)
	ci.draw_colored_polygon(vis, ShipData.HULL)
	_visor_detail(ci, visor)


static func _visor_detail(ci: CanvasItem, visor: float) -> void:
	var a: float = -1.15 * clampf(visor, 0.0, 1.0)
	var h: Vector2 = VISOR_HINGE
	var stripe := PackedVector2Array()
	for v in [Vector2(96, 1), Vector2(122, 1), Vector2(123, 6), Vector2(97, 6)]:
		stripe.append(h + (v - h).rotated(a))
	ci.draw_colored_polygon(stripe, ShipData.BRAND)
	var dark := PackedVector2Array()
	for v in [Vector2(97, 9), Vector2(118, 9), Vector2(112, 15), Vector2(98, 17)]:
		dark.append(h + (v - h).rotated(a))
	ci.draw_colored_polygon(dark, ShipData.HULL_MID)
	var seam: Array = [h + (Vector2(97, -16) - h).rotated(a), h + (Vector2(97, 17) - h).rotated(a)]
	ci.draw_line(seam[0], seam[1], ShipData.HULL_DARK, 1.0)


static func _draw_legs(ci: CanvasItem, legs: float, rim: bool) -> void:
	var l: float = clampf(legs, 0.0, 1.0)
	for x: float in LEGS:
		var dir: float = -1.0 if x < 0.0 else 1.0
		var top := Vector2(x, LEG_TOP)
		var a: float = lerpf(dir * 1.35, 0.0, l)          # folded: along the belly
		var foot: Vector2 = top + Vector2(0, ShipData.LEG_PX).rotated(-a)
		if rim:
			ci.draw_line(top, foot, RIM_KEY, 7.0)
		ci.draw_line(top, foot, ShipData.OUTLINE, 5.0)
		ci.draw_line(top, foot, ShipData.HULL_MID, 3.0)
		ci.draw_line(top + Vector2(0, 3), top.lerp(foot, 0.5), ShipData.HULL, 1.0)
		var pad := Rect2(foot + Vector2(-7, 0), Vector2(14, 3))
		ci.draw_rect(pad.grow(1.0), ShipData.OUTLINE)
		ci.draw_rect(pad, ShipData.HULL_DARK)


static func _sun(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r + 2.0, ShipData.OUTLINE)
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		ci.draw_line(c + Vector2(r + 0.5, 0).rotated(a), c + Vector2(r + 3.0, 0).rotated(a), ShipData.BRAND, 1.0)
	ci.draw_circle(c, r, ShipData.BRAND)
	ci.draw_circle(c, r - 2.0, ShipData.BRAND_DARK)


static func _hazard(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r, ShipData.BRAND)
	var x: float = r.position.x - r.size.y
	while x < r.end.x:
		var p := PackedVector2Array([Vector2(x, r.end.y), Vector2(x + 3, r.end.y), Vector2(x + 3 + r.size.y, r.position.y), Vector2(x + r.size.y, r.position.y)])
		var clipped: Array = Geometry2D.intersect_polygons(p, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))
		_fill(ci, clipped, ShipData.OUTLINE)
		x += 6.0


# Years in the lava: burns over the hull, a crack, a bent fin.
static func _scorch(ci: CanvasItem) -> void:
	var burn := Color(0.08, 0.05, 0.06, 0.55)
	for b in [[Vector2(-60, 12), 20.0, 8.0], [Vector2(10, 14), 26.0, 7.0], [Vector2(-96, -4), 12.0, 10.0], [Vector2(70, -14), 14.0, 6.0], [Vector2(-20, -26), 16.0, 4.0]]:
		var c: Vector2 = b[0]
		var p := PackedVector2Array()
		for i in 10:
			var a: float = TAU * float(i) / 10.0
			var k: float = 0.75 + 0.25 * sin(a * 3.0 + c.x)
			p.append(c + Vector2(cos(a) * b[1] * k, sin(a) * b[2] * k))
		_fill(ci, Geometry2D.intersect_polygons(p, _pv(HULL)), burn)
	var crack: PackedVector2Array = PackedVector2Array([Vector2(-36, -29), Vector2(-31, -20), Vector2(-35, -12), Vector2(-28, -3), Vector2(-31, 6)])
	ci.draw_polyline(crack, ShipData.OUTLINE, 1.0)


# A blinking light's glow (drawn by the lights overlay).
static func draw_lights(ci: CanvasItem, blink: bool, beacon: float) -> void:
	ci.draw_rect(Rect2(NAV_TOP - Vector2(1, 1), Vector2(3, 3)), ShipData.NAV_RED if blink else ShipData.NAV_RED.darkened(0.6))
	ci.draw_rect(Rect2(NAV_NOSE - Vector2(1, 1), Vector2(3, 3)), ShipData.NAV_GREEN if not blink else ShipData.NAV_GREEN.darkened(0.6))
	if beacon > 0.0:
		ci.draw_rect(Rect2(BEACON_AT - Vector2(1, 2), Vector2(3, 3)), ShipData.BEACON)
		ci.draw_circle(BEACON_AT, 3.0 + 4.0 * beacon, Color(ShipData.BEACON, 0.25 * beacon))


# ---------------------------------------------------------------- the coil

# The coil's path in ship space, from the deep up round the hull twice and
# out to its tip over the bridge. Each control point: [position, width share
# (0 = the tip's width .. 1 = the root's), drawn in front of the ship].
# Wrapping round a hull seen side-on, a turn shows as a band across the front
# of the hull, an arc over its top and one under its belly; the part behind
# the hull is hidden by it.
const COIL := [
	[Vector2(10, 380), 1.00, false],
	[Vector2(-6, 250), 0.85, false],
	[Vector2(-34, 130), 0.58, false],
	[Vector2(-58, 56), 0.36, false],
	[Vector2(-62, 30), 0.31, true],
	[Vector2(-47, -4), 0.29, true],
	[Vector2(-36, -36), 0.29, true],
	[Vector2(-25, -50), 0.28, false],
	[Vector2(-12, -42), 0.28, false],
	[Vector2(-5, 0), 0.27, false],
	[Vector2(2, 36), 0.27, false],
	[Vector2(13, 46), 0.27, true],
	[Vector2(24, 8), 0.26, true],
	[Vector2(33, -34), 0.24, true],
	[Vector2(45, -50), 0.20, true],
]
# The free tip, from the coil's end, waving (ship space, at rest).
const TIP := [Vector2(45, -50), Vector2(61, -62), Vector2(79, -66), Vector2(93, -60), Vector2(97, -50)]
const TIP_SHARE := [0.20, 0.15, 0.10, 0.05, 0.0]


static func width_at(share: float) -> float:
	if share >= ShipData.COIL_BAND_W / ShipData.COIL_ROOT_W:
		return lerpf(ShipData.COIL_BAND_W, ShipData.COIL_ROOT_W, inverse_lerp(ShipData.COIL_BAND_W / ShipData.COIL_ROOT_W, 1.0, share))
	return lerpf(ShipData.COIL_TIP_W, ShipData.COIL_BAND_W, share / (ShipData.COIL_BAND_W / ShipData.COIL_ROOT_W))


# Catmull-Rom through `pts`, about every `step` px; returns [points, t] where
# t is each sample's position along the control points (0..n-1).
static func spline(pts: Array, step: float) -> Array:
	var out := PackedVector2Array()
	var ts := PackedFloat32Array()
	var n: int = pts.size()
	for i in n - 1:
		var p0: Vector2 = pts[maxi(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[mini(i + 2, n - 1)]
		var k: int = maxi(2, int(ceil(p1.distance_to(p2) / step)))
		for j in k:
			var t: float = float(j) / float(k)
			out.append(p1.cubic_interpolate(p2, p0, p3, t))
			ts.append(float(i) + t)
	out.append(pts[n - 1])
	ts.append(float(n - 1))
	return [out, ts]


# The coil split into runs drawn behind or in front of the ship:
# [{"pts", "widths": PackedFloat32Array, "front": bool}], neighbours sharing
# their joint so the runs meet.
static func coil_pieces(step: float = 6.0) -> Array:
	var ctrl: Array = COIL.map(func(c): return c[0])
	var sp: Array = spline(ctrl, step)
	var pts: PackedVector2Array = sp[0]
	var ts: PackedFloat32Array = sp[1]
	var pieces: Array = []
	var cur: Dictionary = {}
	for i in pts.size():
		var t: float = ts[i]
		var ci: int = clampi(int(floor(t)), 0, COIL.size() - 1)
		var cj: int = mini(ci + 1, COIL.size() - 1)
		var share: float = lerpf(float(COIL[ci][1]), float(COIL[cj][1]), t - float(ci))
		var front: bool = bool(COIL[ci][2])
		if cur.is_empty() or bool(cur["front"]) != front:
			var nxt := {"pts": PackedVector2Array(), "widths": PackedFloat32Array(), "front": front}
			if not cur.is_empty():
				# Share the joint.
				nxt["pts"].append(cur["pts"][cur["pts"].size() - 1])
				nxt["widths"].append(cur["widths"][cur["widths"].size() - 1])
			pieces.append(nxt)
			cur = nxt
		cur["pts"].append(pts[i])
		cur["widths"].append(width_at(share))
	return pieces
