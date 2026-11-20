extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 135: a falling lava stream is drawn attached to the lava it pours
# from, the flow is goopy (it necks down and breaks into drops as it thins),
# and steam rises off lava that is cooling.
#
# A cavern with a lava shelf on each side: the left shelf pours off its ledge
# to the right (source on the left), the right shelf to the left (source on
# the right). Both fall three cells into a basin. Then the sources stop, the
# streams thin to drips, and the films left behind cool away.
#
#   LLL.......LLL     L lava shelf   # rock   . open
#   ###.......###
#   ###.......###
#   ###.......###
#   .............     the basin
#
# Frame bursts for the eye; each burst's screen rect is logged ("crops") for cropping.

var OX := 3
var OY := 30
const TILE := 24.0


func boot() -> Dictionary:
	return {"seed": 12345}


var field
var td
var crops: Array = []


func _c(x: int, y: int) -> Vector2i:
	return Vector2i(OX + x, OY + y)


# Is the cavern's whole rect (with a margin) solid, breakable rock?
func _fits(ox: int, oy: int) -> bool:
	for y in range(oy - 3, oy + 8):
		for x in range(ox - 3, ox + 16):
			var c := Vector2i(x, y)
			if td.get_biomev(c) < 0 or td.get_resourcev(c) == Data.TILE_EMPTY or td.get_resourcev(c) == Data.TILE_BORDER or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE:
				return false
	return true


# A burst, plus an enlarged crop of each frame around the cells a..b.
func _burst(h, label: String, count: int, every: int, a: Vector2i, b: Vector2i) -> void:
	var first: int = h.shot_index
	await h.burst(label, count, every)
	var cam: Transform2D = Level.map.get_global_transform_with_canvas()
	var p0: Vector2 = cam * Level.map.to_local(Level.map.getTilePos(Vector2(a)) - Vector2(TILE, TILE) * 0.5)
	var p1: Vector2 = cam * Level.map.to_local(Level.map.getTilePos(Vector2(b)) + Vector2(TILE, TILE) * 0.5)
	crops.append({"index": first, "label": label, "count": count, "rect": [p0.x, p0.y, p1.x, p1.y]})


func _streams(cells: Array) -> int:
	var n: int = 0
	for c: Vector2i in cells:
		var sh: Dictionary = field._lava_shape(c)
		if sh["stream"] and sh["rect"].size.x > 0.0:
			n += 1
	return n


func run(h) -> void:
	h.disable_waves()
	field = Level.map.get_node("StoryLavaField")
	td = Level.map.tileData
	field.magma.clear()
	field.mass.clear()
	field.shown.clear()
	field.sources.clear()

	# Somewhere with solid rock all round, turned to plain rock, then the cavern.
	var found: bool = false
	for oy in range(24, 60):
		for ox in range(-12, 6):
			if not found and _fits(ox, oy):
				OX = ox
				OY = oy
				found = true
	h.check("found solid rock for the cavern", found, [OX, OY])
	var around: Array = []
	for y in range(-3, 8):
		for x in range(-3, 16):
			var c: Vector2i = _c(x, y)
			around.append(c)
			td.set_resourcev(c, Data.TILE_DIRT_START)
	await h.reveal(around)
	var open: Array = []
	for x in 13:
		open.append(_c(x, 0))
		open.append(_c(x, 4))
		if x >= 3 and x <= 9:
			for y in range(1, 4):
				open.append(_c(x, y))
	await h.clear_tiles(open)
	await h.teleport_tile(_c(6, 1))
	h.keeper().set("gravity_scale", 0.0)
	h.snap_camera()
	await h.wait(3.0)   # the camera's opening zoom settles
	h.snap_camera()
	h.check("no steam before any lava", field.get("_puffs") == null or field._puffs.is_empty())

	var left_fall: Array = [_c(3, 1), _c(3, 2), _c(3, 3)]     # source on the left
	var right_fall: Array = [_c(9, 1), _c(9, 2), _c(9, 3)]    # source on the right
	var view_a: Vector2i = _c(0, 0)
	var view_b: Vector2i = _c(12, 4)

	# ---- 1. the pour: each shelf is full and fed from its outer end
	for x in 3:
		field.mass[_c(x, 0)] = 1.0
		field.mass[_c(12 - x, 0)] = 1.0
	field.sources[_c(0, 0)] = 3.0
	field.sources[_c(12, 0)] = 3.0
	field.wake_all()
	await _burst(h, "pour_start", 20, 2, view_a, view_b)
	await h.wait(1.2)
	await _burst(h, "pour_steady", 24, 2, view_a, view_b)
	var le: Array = []
	var re: Array = []
	var attached: bool = field.has_method("stream_edges")
	if attached:
		for c: Vector2i in left_fall:
			var e: Vector2 = field.stream_edges(c, 0.5)
			le.append([e.x, e.y])
			attached = attached and e.x <= 1.0 and e.y < TILE - 2.0
		for c: Vector2i in right_fall:
			var e: Vector2 = field.stream_edges(c, 0.5)
			re.append([e.x, e.y])
			attached = attached and e.y >= TILE - 1.0 and e.x > 2.0
	h.check("both falls draw as streams", _streams(left_fall) == 3 and _streams(right_fall) == 3, {"left": _streams(left_fall), "right": _streams(right_fall),
		"widths": (left_fall + right_fall).map(func(c): return snappedf(field._stream_width(c), 0.1)), "fill": (left_fall + right_fall).map(func(c): return snappedf(field.shown.get(c, 0.0), 0.01))})
	h.check("each stream runs down the side its lava comes from (left fall on its left edge, right fall on its right edge)", attached, {"left": le, "right": re})
	# The lip cells (over the drop, beside the shelf) start at the shelf's surface.
	var lip_ok: bool = true
	var lips: Dictionary = {}
	for pair: Array in [[_c(3, 0), _c(2, 0)], [_c(9, 0), _c(10, 0)]]:
		var lip: Dictionary = field._lava_shape(pair[0])
		var src: Dictionary = field._lava_shape(pair[1])
		lips[str(pair[0])] = {"lip": lip["rect"], "source": src["rect"], "stream": lip["stream"]}
		var touching: bool = lip["rect"].position.x <= src["rect"].end.x and lip["rect"].end.x >= src["rect"].position.x
		lip_ok = lip_ok and lip["stream"] and touching and absf(lip["rect"].position.y - src["rect"].position.y) <= 3.0
	h.check("the stream starts at its source: the lip touches the shelf lava at the shelf's surface height", lip_ok, lips)

	# ---- 2. the tail: the sources stop, the shelves drain, the streams thin to drips
	field.sources.clear()
	await _burst(h, "tail", 36, 4, view_a, view_b)
	h.check("steam rises while the thin lava left on the shelves cools", field.get("_puffs") != null and field._puffs.size() > 0, {"puffs": field._puffs.size() if field.get("_puffs") != null else -1, "cooling": field.cooling_cells().size()})
	await _burst(h, "tail_late", 24, 4, view_a, view_b)

	# ---- 3. cooling: films of lava on a floor cool away under rising steam
	await h.wait(1.0)
	for c in field.mass.keys():
		field.mass.erase(c)
	field.shown.clear()
	for x in 13:
		field.mass[_c(x, 4)] = 0.11 if x % 3 != 1 else 0.07
	field.wake_all()
	await h.wait(0.6)
	await _burst(h, "cooling", 30, 4, _c(0, 2), _c(12, 4))
	var puffs_mid: int = field._puffs.size() if field.get("_puffs") != null else -1
	h.check("steam rises off the cooling films", puffs_mid > 5, puffs_mid)
	await h.wait(3.0)
	await _burst(h, "cooled", 12, 4, _c(0, 2), _c(12, 4))
	var films_left: int = 0
	for x in 13:
		if field.mass.has(_c(x, 4)):
			films_left += 1
	h.check("the films cooled away", films_left == 0, films_left)

	# ---- 4. cost: physics time with streams, drops and steam on screen
	field.phys_us = 0
	field.phys_frames = 0
	field.sources[_c(0, 0)] = 2.0
	field.sources[_c(12, 0)] = 2.0
	await h.wait(4.0)
	var us: float = float(field.phys_us) / maxf(1.0, float(field.phys_frames))
	h.check("lava physics stays cheap while pouring and steaming (< 300 us a frame)", us < 300.0, snappedf(us, 0.1))
	await h.shot("end")
	h.note("crops", crops)
