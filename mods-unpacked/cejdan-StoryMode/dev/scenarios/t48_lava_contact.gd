extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 48: the keeper burns only where its body overlaps lava as drawn.


func boot() -> Dictionary:
	return {"seed": 12345}


var field
var td


func _room(h, a: Vector2i, b: Vector2i) -> void:
	for y in range(a.y - 2, b.y + 3):
		for x in range(a.x - 2, b.x + 3):
			if td.get_resourcev(Vector2i(x, y)) != Data.TILE_EMPTY:
				td.set_resourcev(Vector2i(x, y), Data.TILE_DIRT_START)
	await h.dig_room(a, b)


# A column near the centre with solid ground (no holes, no border) around a
# w x hgt block at row y.
func _solid_x(y: int, w: int, hgt: int) -> int:
	for dx in range(4, 30):
		for x in [dx, -dx]:
			var ok: bool = true
			for yy in range(y - 4, y + hgt):
				for xx in range(x - 3, x + w):
					var c := Vector2i(xx, yy)
					ok = ok and td.get_biomev(c) >= 0 and td.get_resourcev(c) != Data.TILE_EMPTY and td.get_resourcev(c) != Data.TILE_BORDER
			if ok:
				return x
	return 0


func _put(c: Vector2i, m: float) -> void:
	field.mass[c] = m
	field.shown[c] = m


# Holds the keeper at `world` for `sec` seconds (re-placing it each frame, as
# it would drift) and returns the heat gained.
func _hold_at(h, world: Vector2, sec: float) -> float:
	field.heat = 0.0
	var t0: float = h.now()
	while h.now() - t0 < sec:
		h.keeper().teleport(world)
		await h.frames(1)
	return field.heat


func run(h) -> void:
	h.disable_waves()
	field = Level.map.get_node("StoryLavaField")
	td = Level.map.tileData
	field.magma.clear()
	field.mass.clear()
	field.shown.clear()
	field.freeze_flow = true
	field.debug_boxes = true

	# ---- a shallow cell: 0.4 of a tile of lava, rock below and beside
	var c: Vector2i = Vector2i(6, 14)
	await _room(h, c + Vector2i(-2, -3), c + Vector2i(2, -1))
	await h.clear_tiles([c])
	_put(c, 0.4)
	var o: Vector2 = Level.map.getTilePos(Vector2(c)) - Vector2(12, 12)  # cell top-left, world
	var surface_y: float = o.y + 24.0 - round(0.4 * 24.0)
	h.snap_camera()
	# Feet (box bottom) 4 px above the drawn surface.
	var above: Vector2 = Vector2(o.x + 12, surface_y - 4 - field.KEEPER_BOX.y * 0.5)
	await h.teleport_tile(c + Vector2i(0, -1))
	await h.wait(1.0)
	var g1: float = await _hold_at(h, above, 2.0)
	h.keeper().teleport(above)
	await h.frames(2)
	await h.shot("hover_above_shallow")
	h.note("hover", {"keeper": h.keeper().global_position, "set": above, "lava rect (field space)": field._lava_shape(c)["rect"], "keeper box": field.keeper_rect(h.keeper())})
	h.check("hovering above a 0.4 cell's drawn surface: no heat", g1 == 0.0, g1)
	var into: Vector2 = Vector2(o.x + 12, surface_y + 4)
	var g2: float = await _hold_at(h, into, 1.0)
	h.keeper().teleport(into)
	await h.frames(2)
	await h.shot("down_in_shallow")
	h.check("dropping into the drawn lava: heat rises", g2 > 10.0, g2)

	# ---- a pouring stream: a 0.3 cell over an open, empty cell
	var s: Vector2i = Vector2i(_solid_x(26, 5, 8), 26)
	await _room(h, s + Vector2i(-2, -3), s + Vector2i(2, 3))
	_put(s, 0.3)
	await h.frames(3)
	var sh: Dictionary = field._lava_shape(s)
	h.note("stream shape", {"cell": s, "stream": sh["stream"], "rect": sh["rect"], "below open": field._is_open(s + Vector2i.DOWN)})
	h.check("the cell draws as a pouring stream", sh["stream"])
	var so: Vector2 = Level.map.getTilePos(Vector2(s)) - Vector2(12, 12)
	var beside: Vector2 = Vector2(so.x + 1, so.y + 12)   # inside the cell, left of the column
	var g3: float = await _hold_at(h, beside, 2.0)
	h.keeper().teleport(beside)
	h.snap_camera()
	await h.frames(2)
	await h.shot("beside_stream")
	h.check("beside the stream in the same cell: no heat", g3 == 0.0, g3)
	var through: Vector2 = Vector2(so.x + 12, so.y + 12)
	var g4: float = await _hold_at(h, through, 1.0)
	h.keeper().teleport(through)
	h.snap_camera()
	await h.frames(2)
	await h.shot("through_stream")
	h.check("flying through the column: heat", g4 > 10.0, g4)

	# ---- a full pool over several cells: the normal rate
	field.freeze_flow = false
	var p: Vector2i = Vector2i(14, 20)
	await _room(h, p + Vector2i(-1, -1), p + Vector2i(1, 1))
	for y in range(-1, 2):
		for x in range(-1, 2):
			_put(p + Vector2i(x, y), 1.0 + 0.25 * (y + 1))
	field.wake_all()
	field.heat = 0.0
	var r0: int = field.recalls
	await h.teleport_tile(p)
	var t0: float = h.now()
	await h.until(func(): return field.recalls > r0, 10.0)
	var t: float = h.now() - t0
	h.check("in a full pool the suit heats at the normal rate (0 to 100 in %.2f s, expected 1.82)" % t, absf(t - 100.0 / 55.0) <= 0.2, t)
	await h.teleport_tile(p + Vector2i(0, -3))
	await h.wait(1.0)
	await h.shot("full_pool_drawn")
