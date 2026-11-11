extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 41: lava cools only at a 1-tall open surface. Builds the ticket's two
# example layouts, a sealed pool and a pool drained by a tunnel, in plain rock,
# then runs 10 minutes of lava time.

const SIM_MINUTES := 10.0


func boot() -> Dictionary:
	return {"seed": 12345}


var field
var td


func _f():
	return Level.map.get_node_or_null("StoryLavaField")


# Turns the rect into plain rock (so no ore or holes get in the way).
func _rock(x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			td.set_resourcev(Vector2i(x, y), Data.TILE_DIRT_START)
			if td.get_hardnessv(Vector2i(x, y)) < 0:
				td.set_hardnessv(Vector2i(x, y), 1)


func _fits(x0: int, y0: int, x1: int, y1: int) -> bool:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c := Vector2i(x, y)
			if td.get_biomev(c) < 0 or td.get_resourcev(c) == Data.TILE_BORDER or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE:
				return false
	return true


func _find_x(w: int, y0: int, y1: int, used: Array) -> int:
	for x in range(-30, 30):
		var free: bool = true
		for u: Array in used:
			if x + w + 2 >= u[0] and x - 2 <= u[1]:
				free = false
		if free and _fits(x - 1, y0, x + w, y1):
			used.append([x - 1, x + w])
			return x
	return 9999


# Carves `rows` (top row first; "L" lava, "." open, anything else rock) at
# (x0, y0), with an open air row above it when `air_above`. Returns lava cells.
func _layout(x0: int, y0: int, rows: Array, air_above: bool) -> Array:
	var w: int = rows[0].length()
	_rock(x0 - 1, y0 - 2, x0 + w, y0 + rows.size())
	var open: Array = []
	var lava: Array = []
	if air_above:
		for x in w:
			open.append(Vector2i(x0 + x, y0 - 1))
	for r in rows.size():
		for x in w:
			var ch: String = rows[r][x]
			if ch == "L" or ch == ".":
				open.append(Vector2i(x0 + x, y0 + r))
			if ch == "L":
				lava.append(Vector2i(x0 + x, y0 + r))
	var around: Array = []
	for y in range(y0 - 2, y0 + rows.size() + 1):
		for x in range(x0 - 1, x0 + w + 1):
			around.append(Vector2i(x, y))
	await h_ref.reveal(around)
	await h_ref.clear_tiles(open)
	for c in lava:
		field.mass[c] = 1.0
		field.shown[c] = 1.0
	return lava


var h_ref


func _total(cells: Dictionary) -> float:
	var t: float = 0.0
	for c in field.mass:
		if cells.has(c):
			t += field.mass[c]
	return t


func _region(x0: int, y0: int, x1: int, y1: int) -> Dictionary:
	var d: Dictionary = {}
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			d[Vector2i(x, y)] = true
	return d


func _avg_physics_ms(h, sec: float) -> float:
	var sum: float = 0.0
	var n: int = 0
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await h.frames(1)
		sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		n += 1
	return sum / maxf(1.0, n)


func run(h) -> void:
	h_ref = h
	h.disable_waves()
	td = Level.map.tileData
	field = _f()
	h.check("the run has a lava field", field != null)
	if field == null:
		return
	# Leave only the lava this test builds.
	field.magma.clear()
	field.mass.clear()
	field.sources.clear()
	field.shown.clear()

	var used: Array = []
	var Y: int = 30
	var ax: int = _find_x(4, Y - 2, Y + 4, used)
	var bx: int = _find_x(5, Y - 2, Y + 3, used)
	var px: int = _find_x(5, Y + 8, Y + 12, used)
	var tx: int = _find_x(16, Y + 8, Y + 15, used)
	h.note("layout x", {"A": ax, "B": bx, "pool": px, "tunnel": tx, "y": Y})
	h.check("found room for the four layouts", ax != 9999 and bx != 9999 and px != 9999 and tx != 9999)

	# Example 1 and 2 from the ticket, with open air above the top row.
	await _layout(ax, Y, ["xxLL", "LLLx", "LLLx", "xxxx"], true)
	await _layout(bx, Y, ["LLLLx", "xxLxx", "LLLLL"], true)
	# A sealed pool: 5 x 3, rock all round.
	var pool: Array = await _layout(px, Y + 9, ["LLLLL", "LLLLL", "LLLLL"], false)
	# A deep pool (3 x 5) with a 1-tall tunnel out of its bottom row, sealed at the end.
	var deep_rows: Array = []
	for r in 4:
		deep_rows.append("LLL" + "x".repeat(13))
	deep_rows.append("LLL" + ".".repeat(12) + "x")
	await _layout(tx, Y + 9, deep_rows, false)

	var cool_a: Array = []
	var cool_b: Array = []
	var cools: Array = field.cooling_cells()
	for c in cools:
		if c.x >= ax and c.x < ax + 4 and c.y >= Y and c.y < Y + 4:
			cool_a.append(c - Vector2i(ax, Y))
		if c.x >= bx and c.x < bx + 5 and c.y >= Y and c.y < Y + 3:
			cool_b.append(c - Vector2i(bx, Y))
	h.note("cooling cells (column, row from the layout's top-left)", {"A": cool_a, "B": cool_b})
	h.check("example 1: only the top-right L cools", cool_a == [Vector2i(3, 0)], cool_a)
	h.check("example 2: top row columns 1, 2 and 4 cool, nothing else", cool_b == [Vector2i(0, 0), Vector2i(1, 0), Vector2i(3, 0)], cool_b)

	var pool_cells: Dictionary = _region(px, Y + 9, px + 4, Y + 11)
	var deep_cells: Dictionary = _region(tx, Y + 9, tx + 2, Y + 13)
	var tunnel_cells: Dictionary = _region(tx + 3, Y + 13, tx + 14, Y + 13)
	var pool0: float = _total(pool_cells)
	var deep0: float = _total(deep_cells)
	await h.teleport_tile(Vector2i(bx + 2, Y - 1))
	await h.wait(1.5)
	await h.shot("start_examples")
	await h.teleport_tile(Vector2i(tx + 5, Y + 7))
	await h.wait(1.5)
	await h.shot("start_pools")

	# Run 10 minutes of lava time, logging every 30 s.
	h.speed(8.0)
	var t0: float = field._time
	var next_log: float = 0.0
	var pool_min: float = pool0
	var pool_max: float = pool0
	var tunnel_cooled: int = 0
	while field._time - t0 < SIM_MINUTES * 60.0:
		await h.frames(5)
		var t: float = field._time - t0
		for c in field.cooling_cells():
			if tunnel_cells.has(c):
				tunnel_cooled += 1
				break
		if t >= next_log:
			var p: float = _total(pool_cells)
			pool_min = minf(pool_min, p)
			pool_max = maxf(pool_max, p)
			h.note("lava at %ds" % int(t), {"sealed pool": snappedf(p, 0.001), "deep pool": snappedf(_total(deep_cells), 0.001),
				"tunnel": snappedf(_total(tunnel_cells), 0.001), "cooling cells": field.cooling_cells().size()})
			if int(t) == 60:
				h.speed(1.0)
				await h.teleport_tile(Vector2i(px + 2, Y + 7))
				await h.wait(1.0)
				await h.shot("pool_1min")
				h.speed(8.0)
			next_log += 30.0
	h.speed(1.0)
	h.check("the sealed pool keeps its lava within 1% over 10 min", (pool0 - pool_min) / pool0 <= 0.01 and (pool_max - pool0) / pool0 <= 0.01, {"start": pool0, "min": pool_min, "max": pool_max})
	var bottom_ok: bool = true
	var bottom: Array = []
	for x in 5:
		var m: float = field.mass.get(Vector2i(bx + x, Y + 2), 0.0)
		bottom.append(snappedf(m, 0.01))
		bottom_ok = bottom_ok and m >= 0.8
	h.check("example 2's bottom row is still there after 10 min", bottom_ok, bottom)
	var deep1: float = _total(deep_cells)
	h.check("lava in the tunnel cooled", tunnel_cooled > 0, tunnel_cooled)
	h.check("the deep pool drained into the tunnel and shrank", deep1 < deep0 * 0.9, {"start": deep0, "end": deep1})
	await h.teleport_tile(Vector2i(px + 2, Y + 7))
	await h.wait(1.5)
	await h.shot("pool_10min")
	await h.teleport_tile(Vector2i(bx + 2, Y - 1))
	await h.wait(1.5)
	await h.shot("end_examples")
	await h.teleport_tile(Vector2i(tx + 5, Y + 7))
	await h.wait(1.5)
	await h.shot("end_pools")

	# Physics time with pools on screen, new rule against the old one.
	var new_ms: float = await _avg_physics_ms(h, 5.0)
	field.legacy_cooling = true
	var old_ms: float = await _avg_physics_ms(h, 5.0)
	field.legacy_cooling = false
	h.note("physics frame ms", {"surface rule": snappedf(new_ms, 0.001), "old rule": snappedf(old_ms, 0.001)})
	h.check("physics time isn't measurably worse", new_ms <= old_ms * 1.25 + 0.05, {"new": new_ms, "old": old_ms})
