extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 42: open lava pools below the top of B5, bigger the deeper they are.
# Run with -Extra "--mode=relichunt" to check a vanilla run has none.

const MapConfig = preload("res://mods-unpacked/cejdan-StoryMode/data/map_config.gd")
const LavaData = preload("res://mods-unpacked/cejdan-StoryMode/data/lava.gd")
const T21 = preload("res://mods-unpacked/cejdan-StoryMode/dev/scenarios/t21_gate.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


func _pool_mass(field) -> float:
	var t: float = 0.0
	for p in field.pools:
		for c in p:
			t += field.mass.get(c, 0.0)
	return t


var own_ms: float = 0.0


func _avg_physics_ms(h, sec: float) -> float:
	var field = Level.map.get_node("StoryLavaField")
	field.phys_us = 0
	field.phys_frames = 0
	var sum: float = 0.0
	var n: int = 0
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await h.frames(1)
		sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		n += 1
	own_ms = field.phys_us / 1000.0 / maxf(1.0, field.phys_frames)
	return sum / maxf(1.0, n)


func run(h) -> void:
	h.disable_waves()
	if Level.loadout.modeId != "storymode":
		h.check("a vanilla run has no lava field", Level.map.get_node_or_null("StoryLavaField") == null)
		h.check("and no pools", Level.map.tileData.get_meta("story_pools", []).is_empty())
		return

	# ---- three seeds, generated headless
	var sig: Array = []
	for s in [1000, 1001, 1002, 1000]:
		var td = h.generate_map(MapConfig.make_archetype(), s)
		var pools: Array = td.get_meta("story_pools", [])
		var y_top: int = 1 << 20
		for c: Vector2i in td.get_used_biome_cells():
			if td.get_biomev(c) >= LavaData.POOL_START_BIOME:
				y_top = mini(y_top, c.y)
		var cells: int = 0
		var shallow: int = 0
		var bad_biome: int = 0
		var near_edge: int = 0
		var by_depth: Array = []
		var overlay: Dictionary = {}
		for p: Array in pools:
			var ys: float = 0.0
			for c: Vector2i in p:
				cells += 1
				ys += c.y
				overlay[c] = Color("#ff6a00")
				if td.get_biomev(c) < LavaData.POOL_START_BIOME:
					bad_biome += 1
				for ox in range(-1, 2):
					for oy in range(-1, 2):
						if td.get_biomev(c + Vector2i(ox, oy)) < 0 or td.get_resourcev(c + Vector2i(ox, oy)) == Data.TILE_BORDER:
							near_edge += 1
			by_depth.append([int(ys / p.size()), p.size()])
		by_depth.sort()
		var third: int = maxi(1, by_depth.size() / 3)
		var top_avg: float = 0.0
		var bot_avg: float = 0.0
		for i in third:
			top_avg += by_depth[i][1]
			bot_avg += by_depth[by_depth.size() - 1 - i][1]
		top_avg /= third
		bot_avg /= third
		var row: Dictionary = {"pools": pools.size(), "cells": cells, "B5 top row": y_top,
			"shallowest pool row": by_depth[0][0] if by_depth.size() else -1, "avg size, top third": top_avg, "avg size, bottom third": bot_avg}
		h.note("seed %d" % s, row)
		sig.append([pools.size(), cells])
		if sig.size() <= 3:
			h.check("seed %d: pools exist, all in B5 or deeper" % s, pools.size() > 3 and bad_biome == 0, row)
			h.check("seed %d: none touch the map edge" % s, near_edge == 0, near_edge)
			h.check("seed %d: deeper pools are bigger" % s, bot_avg > top_avg * 1.3, [top_avg, bot_avg])
			var col: Dictionary = T21.new()._colors()
			h.map_png("pools_seed%d" % s, col, 5, td, overlay)
		td.queue_free()
		await h.frames(1)
	h.check("the same seed gives the same pools", sig[0] == sig[3], [sig[0], sig[3]])

	# ---- the running game
	var field = Level.map.get_node_or_null("StoryLavaField")
	h.check("the run has a lava field", field != null)
	var st: Dictionary = field.stats()
	h.note("run pools", st)
	var low: int = 0
	for p in field.pools:
		for c in p:
			if field.mass.get(c, 0.0) < 1.0:
				low += 1
	h.check("the run's pools are filled brim-full (every cell at least 1.0)", st["pools"] > 3 and low == 0, st)
	# No pockets in the way of this test.
	field.magma.clear()

	# Sealed pools for 10 minutes of lava time.
	var m0: float = _pool_mass(field)
	h.speed(8.0)
	var t0: float = field._time
	var lo: float = m0
	var hi: float = m0
	var next_log: float = 0.0
	while field._time - t0 < 600.0:
		await h.frames(5)
		if field._time - t0 >= next_log:
			var m: float = _pool_mass(field)
			lo = minf(lo, m)
			hi = maxf(hi, m)
			h.note("sealed pools at %ds" % int(field._time - t0), {"mass": snappedf(m, 0.001), "awake cells": field._awake.size()})
			next_log += 60.0
	h.speed(1.0)
	h.check("sealed pools keep their mass within 1% over 10 min", (m0 - lo) / m0 <= 0.01 and (hi - m0) / m0 <= 0.01, {"start": m0, "min": lo, "max": hi})

	# Physics time with all pools settled against the same scene with them
	# emptied, alternated (with, without, with, without; 15 s each) so neither
	# side gets the warm-up.
	var saved: Dictionary = field.mass.duplicate()
	var w: Array = []
	var wo: Array = []
	var w_own: Array = []
	var wo_own: Array = []
	await h.wait(3.0)
	for round_i in 2:
		w.append(await _avg_physics_ms(h, 15.0))
		w_own.append(own_ms)
		field.mass.clear()
		field.shown.clear()
		await h.frames(10)
		wo.append(await _avg_physics_ms(h, 15.0))
		wo_own.append(own_ms)
		field.mass = saved.duplicate()
		field.shown = saved.duplicate()
		field.wake_all()
		await h.frames(30)
	var with_ms: float = (w[0] + w[1]) / 2.0
	var without_ms: float = (wo[0] + wo[1]) / 2.0
	var with_own: float = (w_own[0] + w_own[1]) / 2.0
	var without_own: float = (wo_own[0] + wo_own[1]) / 2.0
	h.note("physics frame ms (2 x 15 s each, alternated)", {"pools settled": w, "no pools": wo,
		"lava field's own, pools settled": snappedf(with_own, 0.0001), "lava field's own, no pools": snappedf(without_own, 0.0001)})
	# The same with the field hidden, and frame times, to see where the rest goes.
	field.visible = false
	var hid_w: float = await _avg_physics_ms(h, 10.0)
	var fps_w: float = Engine.get_frames_per_second()
	field.mass.clear()
	field.shown.clear()
	await h.frames(10)
	var hid_wo: float = await _avg_physics_ms(h, 10.0)
	var fps_wo: float = Engine.get_frames_per_second()
	field.mass = saved.duplicate()
	field.shown = saved.duplicate()
	field.wake_all()
	field.visible = true
	h.note("physics frame ms, field hidden", {"pools settled": hid_w, "no pools": hid_wo, "fps pools": fps_w, "fps no pools": fps_wo})
	h.check("the lava field's own physics time with settled pools is within 10% of no pools", with_own <= without_own * 1.10 + 0.005, [with_own, without_own])
	# Not a pass/fail: the whole scene's physics time also rises with pools
	# present, outside the lava field's own code (see the notes above).
	h.note("whole-scene physics frame ms", {"pools settled": with_ms, "no pools": without_ms})

	# Dig into the biggest pool's wall from the side.
	var big: Array = []
	for p in field.pools:
		if p.size() > big.size():
			big = p
	var set: Dictionary = {}
	for c in big:
		set[c] = true
	var wall: Vector2i = Vector2i(9999, 0)
	for c in big:
		if not set.has(c + Vector2i.LEFT) and not set.has(c + Vector2i.DOWN) and c.y > wall.y:
			wall = c
	var tunnel: Array = []
	for i in range(1, 10):
		tunnel.append(wall + Vector2i(-i, 0))
	var area: Array = []
	for y in range(wall.y - 6, wall.y + 4):
		for x in range(wall.x - 19, wall.x + 8):
			area.append(Vector2i(x, y))
	await h.reveal(area)
	# A drain room at the tunnel's end, big enough to take most of the pool.
	await h.dig_room(wall + Vector2i(-18, -3), wall + Vector2i(-10, 0))
	await h.teleport_tile(wall + Vector2i(-11, 0))
	await h.wait(1.0)
	await h.shot("pool_before_dig")
	var before: float = 0.0
	for c in big:
		before += field.mass.get(c, 0.0)
	await h.clear_tiles(tunnel)
	await h.wait(0.5)
	h.note("tunnel after digging", {"wall": wall, "resources": tunnel.map(func(c): return Level.map.tileData.get_resourcev(c)), "open": tunnel.map(func(c): return field._is_open(c))})
	await h.teleport_tile(wall + Vector2i(-11, -2))
	await h.wait(1.0)
	await h.shot("pool_dug_1s")
	await h.wait(9.0)
	await h.shot("pool_dug_10s")
	var after: float = 0.0
	for c in big:
		after += field.mass.get(c, 0.0)
	h.note("dug pool", {"cells": big.size(), "before": before, "after 10 s": after})
	h.check("lava pours out and the pool level drops", after < before - 1.0, [before, after])
	h.speed(8.0)
	var cooling_seen: int = 0
	var t1: float = field._time
	while field._time - t1 < 240.0:
		await h.frames(5)
		for c in field.cooling_cells():
			if set.has(c):
				cooling_seen += 1
				break
	h.speed(1.0)
	h.check("as the pool drains, its thinned open-topped parts cool", cooling_seen > 0, cooling_seen)
	await h.wait(1.0)
	await h.shot("pool_drained")
