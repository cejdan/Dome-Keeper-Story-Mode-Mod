extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 348: a keeper carrying water into lava stood in the cells the water
# hardened first, and ended up inside a rock tile. Now the lava under and
# beside a keeper's body stays lava; the fill hardens the next cells instead,
# the same number as before. The keeper is checked free of every tile, and
# able to drill its way up out of the pocket.

const FieldUtil = preload("res://mods-unpacked/flantor-StoryMode/util/field_util.gd")
const LavaData = preload("res://mods-unpacked/flantor-StoryMode/data/lava.gd")
static var _FieldUtil = FieldUtil


func boot() -> Dictionary:
	return {"seed": 12345}


var field
var td
var h_ref


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


# Tiles overlapping the keeper's body (no margin): there must be none.
func _tiles_in_keeper(k) -> Array:
	var r: Rect2 = _FieldUtil.keeper_rect(k)
	var a: Vector2i = Level.map.getTileCoord(r.position)
	var b: Vector2i = Level.map.getTileCoord(r.end)
	var out: Array = []
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			var t = Level.map.getTile(Vector2(x, y))
			if t != null and is_instance_valid(t):
				out.append(Vector2i(x, y))
	return out


# The keeper stands at `at`, a water drop lands on it and the check runs.
func _case(h, label: String, pool: Array, air: Array, at: Vector2) -> void:
	var k = h.keeper()
	await _setup(pool, air)
	k.teleport(at)
	await h.wait(0.6)
	await h.snap_camera(k)
	field.set_heat_of(k, 0.0)
	await h.shot(label + "_before")
	var h0: int = field.hardened
	Level.drops.network_spawn({"type": CONST.WATER, "position": k.global_position, "team": "team1"})
	# The field's own tick finds the drop in the keeper's lava and uses it up.
	await h.until(func(): return field.hardened > h0, 3.0)
	var n: int = field.hardened - h0
	var inside: Array = _tiles_in_keeper(k)
	h.check("%s: water hardened %d cells, as before" % [label, LavaData.WATER_HARDENS_CELLS], n == LavaData.WATER_HARDENS_CELLS, {"hardened": n, "cells": field.last_hardened})
	h.check("%s: no rock tile overlaps the keeper" % label, inside.is_empty(), {"tiles": inside, "keeper": k.global_position})
	await h.wait(0.4)
	field.set_heat_of(k, 0.0)
	await h.shot(label + "_after")
	# Free to move: drill up out of the pocket.
	var y0: float = k.global_position.y
	await h.hold("ui_up", 4.0)
	field.set_heat_of(k, 0.0)
	h.check("%s: the keeper drills its way up and out" % label, k.global_position.y < y0 - 12.0, {"from": y0, "to": k.global_position.y})
	await h.shot(label + "_out")


func run(h) -> void:
	h_ref = h
	h.disable_waves()
	field = Level.map.get_node("StoryLavaField")
	td = Level.map.tileData
	field.magma.clear()
	field.freeze_flow = true

	# ---- on the floor of a 7x2 pool, in the middle
	var px: int = -13
	var py: int = 15
	var pool: Array = []
	for yy in range(py, py + 2):
		for xx in range(px, px + 7):
			pool.append(Vector2i(xx, yy))
	var over: Array = [Vector2i(px + 3, py - 1), Vector2i(px + 3, py - 2)]
	await _case(h, "floor", pool, over, Level.map.getTilePos(Vector2(px + 3, py + 1)))

	# ---- at the edge of another pool, against its left wall, half in the top row
	var qx: int = 8
	var qy: int = 16
	pool = []
	for yy in range(qy, qy + 2):
		for xx in range(qx, qx + 7):
			pool.append(Vector2i(xx, yy))
	over = [Vector2i(qx, qy - 1), Vector2i(qx, qy - 2), Vector2i(qx + 1, qy - 1)]
	var edge: Vector2 = Level.map.getTilePos(Vector2(qx, qy)) + Vector2(-6, -10)
	await _case(h, "edge", pool, over, edge)
	field.freeze_flow = false
