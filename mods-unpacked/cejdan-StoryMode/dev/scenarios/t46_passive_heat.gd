extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 46: passive heat builds with depth. Run with -Extra "--mode=relichunt"
# to check vanilla has none.

const LavaData = preload("res://mods-unpacked/cejdan-StoryMode/data/lava.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


var field
var td


# A dug 3 x 3 room centred on a cell near column x0 in row y whose biome passes `ok`.
func _room_at_row(h, y: int, ok: Callable) -> Vector2i:
	for dx in range(0, 30):
		for x in [dx, -dx]:
			var c := Vector2i(x, y)
			var fits: bool = true
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var n: Vector2i = c + Vector2i(ox, oy)
					fits = fits and td.get_biomev(n) >= 0 and td.get_resourcev(n) != Data.TILE_BORDER and td.get_hardnessv(n) < Data.HARDNESS_INDESTRUCTIBLE and ok.call(td.get_biomev(n))
			if fits:
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						var n: Vector2i = c + Vector2i(ox, oy)
						if td.get_resourcev(n) != Data.TILE_EMPTY:
							td.set_resourcev(n, Data.TILE_DIRT_START)
				await h.dig_room(c + Vector2i(-1, -1), c + Vector2i(1, 1))
				return c
	return Vector2i(9999, 9999)


# Logs heat every game second (the lava field's own clock, which follows game
# time even when a sped-up run can't keep up) for up to `limit` game seconds;
# returns the game seconds to an overheat, or -1 if none came.
func _watch(h, c: Vector2i, limit: float, label: String, shot_at: float = -1.0) -> float:
	field.heat = 0.0
	var r0: int = field.recalls
	await h.teleport_tile(c)
	await h.frames(2)
	var t0: float = field._time
	var next: float = 1.0
	var samples: Array = []
	var shot_done: bool = false
	while field._time - t0 < limit:
		await h.frames(1)
		var t: float = field._time - t0
		if t >= next:
			samples.append(snappedf(field.heat, 0.1))
			next += 1.0
		if shot_at > 0.0 and not shot_done and t >= shot_at:
			var sp: float = Engine.time_scale
			h.speed(1.0)
			await h.shot(label + "_heat_bar")
			h.speed(sp)
			shot_done = true
		if field.recalls > r0:
			h.note(label, {"rate": field.passive_rate, "overheat after s": snappedf(t, 0.1), "heat each second": samples})
			return t
	h.note(label, {"rate": field.passive_rate, "no overheat in s": limit, "heat each second": samples})
	return -1.0


func run(h) -> void:
	h.disable_waves()
	if Level.loadout.modeId != "storymode":
		h.check("vanilla has no lava field, so no passive heat", Level.map.get_node_or_null("StoryLavaField") == null)
		return
	field = Level.map.get_node("StoryLavaField")
	td = Level.map.tileData
	field.magma.clear()
	field._heat_rows()
	var top: int = field._heat_top
	var bottom: int = field._heat_bottom
	h.note("passive heat rows", {"B4 top row": top, "bottom row": bottom, "rate at bottom": LavaData.PASSIVE_HEAT_RATE_AT_BOTTOM,
		"rate 10 rows down": field.passive_rate_at(Vector2i(0, top + 10)) if td.get_biomev(Vector2i(0, top + 10)) >= 3 else "n/a"})

	# Above B4: no passive heat.
	var shallow: Vector2i = await _room_at_row(h, 20, func(b): return b < LavaData.PASSIVE_HEAT_START_BIOME)
	var t_sh: float = await _watch(h, shallow, 10.0, "above B4")
	h.check("above the start row heat stays 0", t_sh < 0 and field.heat == 0.0, field.heat)

	# 10 rows into B4 (time sped up; heat runs on game time).
	var mid: Vector2i = await _room_at_row(h, top + 10, func(b): return b >= LavaData.PASSIVE_HEAT_START_BIOME)
	var want_mid: float = 100.0 / maxf(0.0001, field.passive_rate_at(mid))
	h.speed(8.0)
	var t_mid: float = await _watch(h, mid, want_mid * 1.3, "10 rows into B4", 40.0)
	h.speed(1.0)
	h.check("10 rows below the start it overheats as the linear rule says (%.0f s; rule %.0f s; the ticket's target was ~300 s)" % [t_mid, want_mid], t_mid > 0 and absf(t_mid - want_mid) <= want_mid * 0.1, {"seconds": t_mid, "rule": want_mid})

	# Just above the bottom.
	# The deepest row (from 3 above the bottom up) where a 3 x 3 room fits; the
	# map narrows at the bottom.
	var deep: Vector2i = Vector2i(9999, 9999)
	for up in range(3, 20):
		deep = await _room_at_row(h, bottom - up, func(b): return b >= LavaData.PASSIVE_HEAT_START_BIOME)
		if deep.x != 9999:
			break
	h.check("found a room near the bottom", deep.x != 9999, deep)
	if deep.x == 9999:
		return
	var want_deep: float = 100.0 / maxf(0.0001, field.passive_rate_at(deep))
	h.speed(4.0)
	var t_deep: float = await _watch(h, deep, want_deep * 1.3, "near the bottom")
	h.speed(1.0)
	h.check("near the bottom (row %d of %d) it overheats in about 45 s (%.0f s)" % [deep.y, bottom, t_deep], t_deep > 0 and absf(t_deep - 45.0) <= 45.0 * 0.2, {"seconds": t_deep, "rule": want_deep})

	# Back in the dome the suit cools to 0.
	field.heat = 60.0
	var dome = Level.getDome("team1")
	h.keeper().teleport(dome.global_position)
	h.snap_camera()
	await h.until(func(): return h.keeper().isInsideDome, 5.0)
	await h.until(func(): return field.heat <= 0.0, 10.0)
	h.check("in the dome the suit cools to 0", h.keeper().isInsideDome and field.heat == 0.0, {"inside": h.keeper().isInsideDome, "heat": field.heat})

	# Heat Shielding IV: no passive heat anywhere out of lava, but lava still heats.
	Data.apply("team1." + LavaData.HEAT_SHIELD_KEY, 4)
	h.speed(4.0)
	var t_iv: float = await _watch(h, deep, 30.0, "tier IV near the bottom")
	h.speed(1.0)
	h.check("at tier IV heat stays 0 deep down out of lava", t_iv < 0 and field.heat == 0.0, field.heat)
	for y in range(-1, 2):
		for x in range(-1, 2):
			field.mass[deep + Vector2i(x, y)] = 1.0 + 0.25 * (y + 1)
	field.wake_all()
	await h.teleport_tile(deep)
	await h.wait(2.0)
	h.check("at tier IV lava still heats", field.heat > 5.0, field.heat)
