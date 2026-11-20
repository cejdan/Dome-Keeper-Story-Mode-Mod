extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 296: water that touches lava drawn in the next cell (the cell beside
# it, or the top of a pool just under it) used to be used up while hardening
# nothing ("Water hardened 0 lava cells"), because the search started from the
# drop's own, empty cell. Now it starts from the lava it touched.
# Before the fix, both "used-up water hardens lava" checks failed.

const TILE := 24.0


func boot() -> Dictionary:
	return {"seed": 12345}


var field
var td


func _rock(c: Vector2i) -> void:
	td.set_resourcev(c, Data.TILE_DIRT_START)
	if td.get_hardnessv(c) < 0 or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE:
		td.set_hardnessv(c, Data.HARDNESS_MEDIUM)
	Level.map.visibleTileCoords.erase(Vector2(c))


# Rock round the box, then `lava` cells open and full and `air` cells open.
func _setup(lava: Array, air: Array) -> void:
	var around: Array = []
	for c in lava + air:
		for oy in range(-2, 3):
			for ox in range(-2, 3):
				var n: Vector2i = c + Vector2i(ox, oy)
				if not around.has(n):
					around.append(n)
	for c in around:
		_rock(c)
	await h_ref.reveal(around)
	await h_ref.clear_tiles(lava + air)
	for c in lava:
		field.mass[c] = 1.0
	field.wake_all()


var h_ref


# Spawns a water drop in a dry spot and waits for it.
func _spawn_water(h, at: Vector2):
	var before: Array = Level.drops.get_children()
	Level.drops.network_spawn({"type": CONST.WATER, "position": at, "team": "team1"})
	var found: Array = []   # a lambda captures by value; it fills this
	await h.until(func():
		for n in Level.drops.get_children():
			if not before.has(n) and "type" in n and n.type == CONST.WATER:
				found.append(n)
				return true
		return false, 3.0)
	return found[0] if not found.is_empty() else null


# Puts `d` at `pos` and runs the water check in the same frame, so gravity
# can't move it into the lava first. Returns {consumed, hardened}.
func _touch(d, pos: Vector2) -> Dictionary:
	var h0: int = field.hardened
	d.linear_velocity = Vector2.ZERO
	d.global_position = pos
	var touches: bool = field.lava_overlaps(Rect2(pos - Vector2(2, 2), Vector2(4, 4)))
	field._check_water()
	return {"consumed": d.is_queued_for_deletion() or not is_instance_valid(d) or d.get_parent() == null, "hardened": field.hardened - h0,
		"cell of drop": Level.map.getTileCoord(pos), "touches lava": touches}


func run(h) -> void:
	h_ref = h
	h.disable_waves()
	field = Level.map.get_node("StoryLavaField")
	td = Level.map.tileData
	field.magma.clear()
	field.freeze_flow = true

	# ---- beside: a 1-wide lava column with an open column to its right
	var x: int = 8
	var y: int = 16
	var lava: Array = []
	var air: Array = []
	for i in 4:
		lava.append(Vector2i(x, y + i))
		air.append(Vector2i(x + 1, y + i))
	for i in 3:
		air.append(Vector2i(x + 1, y - 1 - i))
	await _setup(lava, air)
	await h.teleport_tile(Vector2i(x + 1, y - 3))
	await h.wait(1.0)
	await h.shot("beside_before")
	var d = await _spawn_water(h, Level.map.getTilePos(Vector2(x + 1, y - 2)))
	h.check("a water drop spawned", d != null)
	# The lava cell's right edge is the open cell's left edge; the drop's centre
	# sits 0.3 px inside the open cell, its 4 px box over the edge.
	var edge_x: float = Level.map.getTilePos(Vector2(x + 1, y + 1)).x - TILE * 0.5
	var r: Dictionary = _touch(d, Vector2(edge_x + 0.3, Level.map.getTilePos(Vector2(x + 1, y + 1)).y))
	h.note("beside", r)
	h.check("beside: the drop touches lava from the open cell", r["touches lava"] and r["cell of drop"] == Vector2i(x + 1, y + 1), r)
	h.check("beside: used-up water hardens lava", r["consumed"] and r["hardened"] > 0, r)
	await h.wait(0.5)
	await h.shot("beside_after")

	# ---- above: a 3-wide pool, the drop just over its surface
	var px: int = -13
	var py: int = 15
	var pool: Array = []
	for yy in range(py, py + 2):
		for xx in range(px, px + 3):
			pool.append(Vector2i(xx, yy))
	var over: Array = [Vector2i(px + 1, py - 1), Vector2i(px + 1, py - 2), Vector2i(px + 1, py - 3)]
	await _setup(pool, over)
	await h.teleport_tile(Vector2i(px + 1, py - 3))
	await h.wait(1.0)
	await h.shot("above_before")
	d = await _spawn_water(h, Level.map.getTilePos(Vector2(px + 1, py - 2)))
	var top_y: float = Level.map.getTilePos(Vector2(px + 1, py)).y - TILE * 0.5
	r = _touch(d, Vector2(Level.map.getTilePos(Vector2(px + 1, py)).x, top_y - 0.3))
	h.note("above", r)
	h.check("above: the drop touches the pool from the cell over it", r["touches lava"] and r["cell of drop"] == Vector2i(px + 1, py - 1), r)
	h.check("above: used-up water hardens lava", r["consumed"] and r["hardened"] > 0, r)
	await h.wait(0.5)
	await h.shot("above_after")

	# ---- water that touches no lava is left alone
	d = await _spawn_water(h, Level.map.getTilePos(Vector2(px + 1, py - 2)))
	r = _touch(d, Level.map.getTilePos(Vector2(px + 1, py - 2)))
	h.check("water clear of lava is not used up", not r["consumed"] and r["hardened"] == 0, r)
	field.freeze_flow = false
