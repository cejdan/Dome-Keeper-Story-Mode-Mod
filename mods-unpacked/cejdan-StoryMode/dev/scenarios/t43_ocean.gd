extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 43: the lava ocean in a running Story Mode game. Run with
# -Extra "--mode=relichunt" to check vanilla has none.

const LavaData = preload("res://mods-unpacked/cejdan-StoryMode/data/lava.gd")
const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")


func boot() -> Dictionary:
	# The boss fight (#160) would seal the chamber; it has its own scenarios.
	return {"seed": 12345, "boss": false}


var field
var td
var o: Dictionary


func _avg_ms(h, sec: float) -> Array:
	field.phys_us = 0
	field.phys_frames = 0
	var sum: float = 0.0
	var n: int = 0
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await h.frames(1)
		sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		n += 1
	return [sum / maxf(1.0, n), field.phys_us / 1000.0 / maxf(1.0, field.phys_frames)]


# Opens the ceiling over column x: a room above it, then the ceiling tile.
func _open_ceiling(h, x: int) -> void:
	var cy: int = int(o["ceiling"])
	for yy in range(cy - 4, cy):
		for xx in range(x - 1, x + 2):
			var c := Vector2i(xx, yy)
			if td.get_biomev(c) < 0 or td.get_resourcev(c) == Data.TILE_BORDER:
				td.set_biomev(c, 7)
				td.set_hardnessv(c, 2)
			td.set_resourcev(c, Data.TILE_DIRT_START)
	await h.dig_room(Vector2i(x - 1, cy - 4), Vector2i(x + 1, cy - 1))
	await h.reveal([Vector2i(x, cy)])
	await h.clear_tiles([Vector2i(x, cy)])


# Dives straight down from the ceiling hole at column x until the boss chamber
# or an overheat. Returns [seconds, reached, heat on arrival].
func _dive(h, x: int, keep_cool: bool = false) -> Array:
	field.boss_chamber_reached = false
	field.heat = 0.0
	var r0: int = field.recalls
	await h.teleport_tile(Vector2i(x, int(o["ceiling"]) - 1))
	await h.wait(0.3)
	field.heat = 0.0
	var t0: float = field._time
	h.down("ui_down")
	var trail: Array = []
	var next_t: float = 0.0
	while field._time - t0 < 60.0:
		await h.frames(1)
		if field._time - t0 >= next_t:
			trail.append([snappedf(field._time - t0, 0.1), h.keeper_tile()])
			next_t += 2.0
		if keep_cool:
			field.heat = 0.0
		if field.boss_chamber_reached or field.recalls > r0:
			break
	h.up("ui_down")
	var ft = Level.map.getTile(Vector2(x, int(o["bottom"]) + 1))
	h.note("dive trail x=%d" % x, {"trail": trail, "end": h.keeper_tile(), "floor": int(o["bottom"]) + 1, "chamber": td.get_meta("story_boss_chamber"),
		"floor tile": {"exists": ft != null, "type": ft.type if ft else "", "health": ft.health if ft else -1, "max": ft.max_health if ft else -1, "hardness": ft.hardness if ft else -1, "layer": ft.layer if ft else -1},
		"drill": Data.ofOr("player1.keeper1.drillstrength", -1)})
	return [snappedf(field._time - t0, 0.1), field.boss_chamber_reached, snappedf(field.heat, 0.1), field.recalls > r0]


func run(h) -> void:
	h.disable_waves()
	if Level.loadout.modeId != "storymode":
		h.check("vanilla has no ocean", Level.map.tileData.get_meta("story_ocean", {}).is_empty() and Level.map.get_node_or_null("StoryLavaField") == null)
		return
	field = Level.map.get_node("StoryLavaField")
	td = Level.map.tileData
	o = td.get_meta("story_ocean", {})
	h.check("the run has a lava ocean", not o.is_empty() and field.ocean_cells > 1000, {"ocean": o, "cells": field.ocean_cells})
	# Magma pockets stay out of the ocean's ceiling and everything below it (the
	# rock there touches lava and would melt open at once).
	var by_ocean: Array = field.magma.keys().filter(func(c): return c.y >= int(o["ceiling"]))
	h.check("no magma pocket in the ocean ceiling, floor or chamber walls", by_ocean.is_empty(), by_ocean.slice(0, 10))

	# ---- sealed for 10 minutes
	var m0: float = field.ocean_mass()
	h.speed(8.0)
	var t0: float = field._time
	var lo: float = m0
	var hi: float = m0
	var nxt: float = 0.0
	while field._time - t0 < 600.0:
		await h.frames(5)
		if field._time - t0 >= nxt:
			var m: float = field.ocean_mass()
			lo = minf(lo, m)
			hi = maxf(hi, m)
			nxt += 120.0
	h.speed(1.0)
	h.note("sealed ocean", {"start": m0, "min": lo, "max": hi, "awake": field._awake.size()})
	h.check("the sealed ocean keeps its mass within 1% over 10 min", (m0 - lo) / m0 <= 0.01 and (hi - m0) / m0 <= 0.01, {"start": m0, "min": lo, "max": hi})

	# ---- physics time, ocean settled against no ocean (alternated)
	var saved: Dictionary = field.mass.duplicate()
	var w: Array = []
	var wo: Array = []
	for i in 2:
		w.append(await _avg_ms(h, 10.0))
		field.mass = {}
		field.shown = {}
		await h.frames(10)
		wo.append(await _avg_ms(h, 10.0))
		field.mass = saved.duplicate()
		field.shown = saved.duplicate()
		field.wake_all()
		await h.frames(30)
	var own_w: float = (w[0][1] + w[1][1]) / 2.0
	var own_wo: float = (wo[0][1] + wo[1][1]) / 2.0
	h.note("physics ms [whole scene, lava field's own]", {"ocean settled": w, "no ocean": wo})
	# On a ~0.03 ms base, 15% is a few microseconds; allow 0.02 ms of absolute slack.
	h.check("the lava field's own physics time with the ocean is within 15% (or 0.02 ms) of without", own_w <= maxf(own_wo * 1.15, own_wo + 0.02), [own_w, own_wo])

	# ---- break the ceiling at x = 0
	await _open_ceiling(h, 0)
	await h.teleport_tile(Vector2i(0, int(o["ceiling"]) - 2))
	await h.wait(5.0)
	var room_lava: float = 0.0
	for yy in range(int(o["ceiling"]) - 4, int(o["ceiling"]) + 1):
		for xx in range(-1, 2):
			room_lava += field.mass.get(Vector2i(xx, yy), 0.0)
	await h.shot("ceiling_broken")
	h.check("breaking the ceiling doesn't flood the tunnel", room_lava < 0.05, room_lava)
	h.check("the ocean's top row is still full", field.mass.get(Vector2i(0, int(o["top"])), 0.0) >= 0.9, field.mass.get(Vector2i(0, int(o["top"])), 0.0))

	# ---- mine unobtainium in the ocean and carry it home (Heat Shielding IV so the trip fits)
	Data.apply("team1." + LavaData.HEAT_SHIELD_KEY, 4)
	var unob: int = int(Minerals.TABLE["unobtainium"]["tile_id"])
	var best: Vector2i = Vector2i(9999, 0)
	for c: Vector2i in td.get_resource_cells_by_id(unob):
		if c.y >= int(o["top"]) and absi(c.x) + (c.y - int(o["top"])) < absi(best.x) + (best.y - int(o["top"])):
			best = c
	await h.reveal([best])
	h.note("unobtainium tile", best)
	var f0: int = int(Data.ofOr("inventory.floatingunobtainium", 0))
	await h.clear_tiles([best])
	await h.wait(1.0)
	var drop = null
	for d in Level.drops.get_children():
		if "type" in d and d.type == "unobtainium":
			drop = d
	h.check("mining it in the ocean drops a piece", drop != null and int(Data.ofOr("inventory.floatingunobtainium", 0)) > f0)
	if drop != null:
		h.keeper().teleport(drop.global_position)
		await h.frames(3)
		h.keeper().pickup(drop)
		await h.wait(0.5)
		var money0: int = int(h.inv("money"))
		# Up through the lava, out of the hole, then home.
		for yy in range(best.y, int(o["ceiling"]) - 3, -2):
			h.keeper().teleport(Level.map.getTilePos(Vector2(0, yy)))
			await h.frames(4)
		await h.shot("carrying_unobtainium")
		var dome = Level.getDome("team1")
		h.keeper().teleport(dome.getDropTarget("unobtainium").global_position + Vector2(0, -10))
		h.snap_camera()
		await h.until(func(): return int(h.inv("money")) > money0, 15.0)
		h.check("delivered: one unobtainium and $100,000", int(h.inv("unobtainium")) >= 1 and int(h.inv("money")) == money0 + 100000, {"unob": h.inv("unobtainium"), "money": [money0, h.inv("money")]})

	# ---- the balance check: dive from the ceiling to the boss chamber
	# Straight dives need columns over the chamber with no unobtainium in the way
	# (a player would steer round it; a base drill can't get through it).
	var ch: Rect2i = td.get_meta("story_boss_chamber")
	var clear: Array = []
	for dx in range(0, ch.size.x / 2 - 1):
		for x in [dx, -dx - 1]:
			var ok: bool = x != 0 and x != best.x
			for y in range(int(o["top"]), int(o["bottom"]) + 1):
				ok = ok and td.get_resourcev(Vector2i(x, y)) == Data.TILE_EMPTY
			if ok and not clear.has(x) and clear.all(func(cx): return absi(cx - x) >= 3):
				clear.append(x)
	h.note("clear dive columns", clear)
	h.check("three clear dive columns over the chamber", clear.size() >= 3, clear)
	for x in clear.slice(0, 3):
		await _open_ceiling(h, x)
	# How long the dive takes, heat aside.
	var dt: Array = await _dive(h, clear[0], true)
	h.note("dive time with heat held at 0 [game s, reached]", dt)
	await h.wait(1.0)
	Data.apply("team1." + LavaData.HEAT_SHIELD_KEY, 3)
	var d3: Array = await _dive(h, clear[1])
	h.note("dive at tier III [game s, reached, heat, overheated]", d3)
	await h.wait(1.0)
	Data.apply("team1." + LavaData.HEAT_SHIELD_KEY, 4)
	var d4: Array = await _dive(h, clear[2])
	h.note("dive at tier IV [game s, reached, heat, overheated]", d4)
	h.note("tier IV lava multiplier", LavaData.HEAT_SHIELD_LAVA_MULT[4])
	await h.wait(0.5)
	await h.shot("boss_chamber")
	h.check("tier IV: the dive reaches the boss chamber under 100% heat", d4[1] and not d4[3], d4)
	await h.wait(3.0)
	var ch_lava: float = 0.0
	for c in field.mass:
		if ch.has_point(c):
			ch_lava += field.mass[c]
	h.check("the boss chamber stays dry after the crust is broken", ch_lava == 0.0, ch_lava)
	h.check("tier III: the same dive overheats before the floor", not d3[1] and d3[3], d3)
