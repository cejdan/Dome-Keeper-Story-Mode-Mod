extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 313: crash to desktop with the Engineer's drone yard drones during
# mining and combat. A Story run with every drone yard upgrade (battle grid
# included); a metal barrier between two rooms, partly destroyed, with drops
# on the far side. While the drones fly, tiles on their paths keep changing
# the ways Story Mode changes them: rock coming back where there was a hole
# (lava hardened by water, the way lava_field._harden does it) and broken
# again, the barrier's metal broken (Map.destroyTile, as gate blasts, lava
# melt and gas bursts do), real lava hardened by a water drop, and cobalt
# going 1 -> 0. Then two combat phases with the battle grid out.
#
# Checks: no drone path crosses solid rock (the pathfinding graph follows the
# map), no drone goes off the map, and the run gets through.

const TIMEOUT := 420
const SLOT := 37
const Metal = preload("res://mods-unpacked/flantor-StoryMode/data/metal.gd")

var td
var map
var rng := RandomNumberGenerator.new()
var toggles := 0
var bad_paths: Array = []
var off_map: Array = []


func boot() -> Dictionary:
	return {"seed": 12345, "gadget": "droneyard"}


func _drones(h) -> Array:
	return h.get_tree().get_nodes_in_group("team1-transport_drones").filter(func(d): return is_instance_valid(d))


func _metal(c: Vector2i) -> void:
	td.set_resourcev(c, Metal.TILE_ID)
	if td.get_hardnessv(c) < 0 or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE:
		td.set_hardnessv(c, Data.HARDNESS_HARD)


# Rock comes back in an open cell the way lava_field._harden makes it.
func _solidify(c: Vector2i, type_id: int = Data.TILE_DIRT_START) -> void:
	if td.get_hardnessv(c) < 0 or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE:
		td.set_hardnessv(c, Data.HARDNESS_MEDIUM)
	td.set_resourcev(c, type_id)
	map.visibleTileCoords.erase(Vector2(c))
	map.revealTile(Vector2(c))
	if map.has_method("restoreTileVisually"):
		map.restoreTileVisually(Vector2(c))
	map.updateBorderSpriteOfTileCoord(Vector2(c))


func _break(c: Vector2i) -> void:
	var t = map.getTile(Vector2(c))
	if t != null and is_instance_valid(t):
		map.destroyTile("team1", "", t)


func _open(c: Vector2i) -> bool:
	return td.get_resourcev(c) == Data.TILE_EMPTY


# Every path point of every flying drone lies in an open cell.
func _audit(h, label: String) -> void:
	for d in _drones(h):
		if not d.global_position.is_finite() or d.global_position.length() > 20000:
			off_map.append([label, d.UID, d.global_position])
		if d.state != TransportDrone.State.PICKUP and d.state != TransportDrone.State.RETRIEVE:
			continue
		for i in range(d.currentPathIndex, d.currentPath.size()):
			var c: Vector2i = map.getTileCoord(d.currentPath[i])
			if c.y >= 0 and not _open(c):
				bad_paths.append([label, d.UID, c, td.get_resourcev(c)])
				break


# Changes one cell ahead on a random flying drone's path: closes it with rock
# and breaks it again a moment later.
func _toggle_on_path(h) -> void:
	var flying: Array = _drones(h).filter(func(d): return (d.state == TransportDrone.State.PICKUP or d.state == TransportDrone.State.RETRIEVE) and d.currentPath.size() > d.currentPathIndex + 2)
	if flying.is_empty():
		return
	var d = flying[rng.randi() % flying.size()]
	var i: int = mini(d.currentPathIndex + 1 + rng.randi() % 3, d.currentPath.size() - 1)
	var c: Vector2i = map.getTileCoord(d.currentPath[i])
	if c.y < 1 or not _open(c) or c == map.getTileCoord(d.global_position):
		return
	_solidify(c)
	toggles += 1
	h.get_tree().create_timer(rng.randf_range(0.2, 1.5)).timeout.connect(func(): if is_instance_valid(map): _break(c))


# The drone path graph: one point per open cell, none in rock.
func _graph_check(h) -> void:
	var pf = map.pathfinder
	var in_rock: Array = []
	for pos in pf.pointIdsByCoord:
		var c: Vector2i = map.getTileCoord(pos)
		if c.y >= 0 and not _open(c):
			in_rock.append(c)
	h.check("the path graph has one point per cell", pf.pathfinder.get_point_count() == pf.pointIdsByCoord.size(), {"points": pf.pathfinder.get_point_count(), "cells": pf.pointIdsByCoord.size()})
	h.check("no path graph point sits in rock", in_rock.is_empty(), in_rock.slice(0, 20))


func _spawn_far(n: int) -> void:
	var types := ["gold", "iron", CONST.WATER, CONST.SAND, "iron", "gold"]
	for i in n:
		Level.drops.network_spawn({"type": types[i % types.size()], "position": map.getTilePos(Vector2i(10 + i % 6, 8)) + Vector2(0, -4), "impulse": Vector2.ZERO})


func _churn(h, sec: float, label: String) -> void:
	var t_end: float = h.now() + sec
	var k := 0
	while h.now() < t_end:
		_toggle_on_path(h)
		if k % 3 == 0:
			_audit(h, label)
		if k % 10 == 0:
			# The barrier: metal comes back in the gap and is broken again.
			var gap := Vector2i(5 + rng.randi() % 2, 7 + rng.randi() % 2)
			if _open(gap):
				_solidify(gap, Metal.TILE_ID)
				h.get_tree().create_timer(rng.randf_range(0.3, 2.0)).timeout.connect(func(): if is_instance_valid(map): _break(gap))
		if k % 25 == 0 and h.get_tree().get_nodes_in_group("drops").size() < 30:
			_spawn_far(6)
		k += 1
		await h.wait(0.25)


func run(h) -> void:
	rng.seed = 313
	map = Level.map
	td = map.tileData
	h.disable_waves()
	h.set_inv("money", 1000000)
	Data.apply("team1.dome.maxHealth", 1000000)
	Data.apply("team1.dome.health", 1000000)
	await h.wait(1.0)

	# Drones (three more), their speed and the battle grid; vanilla's water
	# and cobalt costs stay in Story Mode.
	for t in [CONST.IRON, CONST.WATER, CONST.SAND]:
		h.set_inv(t, 1000)
	for id in ["droneyarddrones", "droneyarddrones", "droneyarddrones", "droneyarddronespeed1", "droneyardbattlegrid", "droneyardbattlegridquick1", "droneyardbattlegridlong1"]:
		await h.buy(id)
	await h.until(func(): return _drones(h).size() >= 3, 15.0)
	h.check("the drone yard has drones", _drones(h).size() >= 3, _drones(h).size())
	h.note("battle", {"ability": Data.ofOr("team1.droneyard.battleability", null), "count": Data.ofOr("team1.droneyard.battledronecount", null)})

	# Two rooms under the dome with a metal barrier (x 5..6) between them.
	for y in range(4, 10):
		for x in [5, 6]:
			_metal(Vector2i(x, y))
	await h.dig_room(Vector2i(0, 0), Vector2i(1, 4))
	await h.dig_room(Vector2i(-4, 5), Vector2i(4, 8))
	await h.dig_room(Vector2i(7, 5), Vector2i(16, 8))
	await h.reveal([Vector2i(5, 4), Vector2i(6, 4), Vector2i(5, 9), Vector2i(6, 9)])
	for y in range(5, 9):
		for x in [5, 6]:
			map.revealTile(Vector2(x, y))
	await h.frames(3)
	await h.teleport_tile(Vector2i(-2, 8))
	_spawn_far(6)
	await h.wait(2.0)
	await h.shot("barrier_whole")
	await h.wait(3.0)
	h.note("drones before the gap", _drones(h).map(func(d): return {"state": d.state, "path": d.currentPath.size()}))

	# Part of the barrier goes (a gate blast, lava melt or a gas burst all
	# break tiles through Map.destroyTile).
	for c in [Vector2i(5, 7), Vector2i(6, 7), Vector2i(5, 8), Vector2i(6, 8)]:
		_break(c)
	await h.wait(1.0)
	await h.shot("barrier_broken")
	var pf = map.pathfinder
	h.note("graph", {"points": pf.pathfinder.get_point_count(), "coords": pf.pointIdsByCoord.size()})

	h.speed(2.0)
	await _churn(h, 30.0, "mining")
	await h.shot("mining_churn")

	# Real lava in room B's floor, hardened by a water drop (lava_field._harden).
	var field = map.get_node_or_null("StoryLavaField")
	if field != null:
		for x in range(8, 12):
			field.mass[Vector2i(x, 8)] = 1.0
		field.wake_all()
		await h.wait(0.5)
		Level.drops.network_spawn({"type": CONST.WATER, "position": map.getTilePos(Vector2i(9, 7)), "impulse": Vector2.ZERO})
		await h.until(func(): return field.hardened > 0, 10.0)
		h.note("lava hardened", {"cells": field.last_hardened})
		await _churn(h, 10.0, "after lava")

	# Cobalt 1 -> 0, then combat.
	h.set_inv(CONST.SAND, 1)
	await h.wait(0.5)
	h.set_inv(CONST.SAND, 0)
	h.enable_waves()
	GameWorld.runStarted = true
	for wave in 2:
		Data.apply("team1.monsters.wavecooldown", 2)
		var came: bool = await h.until(func(): return Data.of("team1.monsters.wavepresent"), 60.0)
		h.check("wave %d came" % (wave + 1), came)
		await _churn(h, 4.0, "wave %d start" % (wave + 1))
		await h.shot("wave_%d" % (wave + 1))
		h.note("battle drones", h.get_tree().get_nodes_in_group("team1-battle_drones").size())
		await _churn(h, 20.0, "wave %d" % (wave + 1))
		h.set_inv(CONST.SAND, 1)
		await _churn(h, 2.0, "wave %d cobalt" % (wave + 1))
		h.set_inv(CONST.SAND, 0)
		for mm in Level.monstersByTeamId.values():
			mm.instantlyKillWave()
		await h.until(func(): return not Data.of("team1.monsters.wavepresent"), 30.0)
		await _churn(h, 5.0, "wave %d end" % (wave + 1))
		if wave == 0:
			# Saved between the waves, as the game saves (never during one);
			# t313_drone_reload loads it and plays a wave to its end.
			await SaveGame.saveGame("singleplayer", SLOT, true)
			h.note("saved slot", {"slot": SLOT, "drones": _drones(h).map(func(d): return d.state)})
	h.disable_waves()
	h.speed(1.0)
	await h.shot("end")

	h.note("graph after", {"points": pf.pathfinder.get_point_count(), "coords": pf.pointIdsByCoord.size()})
	_graph_check(h)
	h.check("tiles changed on drone paths", toggles >= 20, toggles)
	h.check("no drone path runs through solid rock", bad_paths.is_empty(), bad_paths.slice(0, 20))
	h.check("no drone leaves the map", off_map.is_empty(), off_map.slice(0, 10))
	h.check("the run is still going", is_instance_valid(map) and not GameWorld.gameover)
