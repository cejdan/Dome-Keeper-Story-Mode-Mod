extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #369 (tuning aid, not a regression): the map's rows from the ocean to the
# surface, the dome, and how fast the keeper (boss gear) climbs a dug shaft.
# `-Extra "--keeper=keeper2"` etc. for the other keepers;
# `-Extra "--mapsize=regular-small"` for the other sizes.

const TIMEOUT := 200


func boot() -> Dictionary:
	return {"seed": 12345, "boss": false}


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.until(func(): return h.keeper() != null and Level.map != null, 30.0)
	await h.wait(1.0)
	h.disable_waves()
	load("res://mods-unpacked/flantor-StoryMode/dev/boss_dev.gd").give_gear()
	var td = Level.map.tileData
	var ocean: Dictionary = td.get_meta("story_ocean")
	var d = Level.getDome("team1")
	var dome_cell: Vector2i = Level.map.getTileCoord(d.global_position)
	var used: Rect2i = td.get_used_rect()
	var top_open: Array = []
	for y in range(used.position.y, used.position.y + 6):
		var row: Array = []
		for x in range(-4, 5):
			row.append("%d:%d" % [td.get_resourcev(Vector2i(x, y)), td.get_biomev(Vector2i(x, y))])
		top_open.append([y, row])
	h.note("geometry", {"used": used, "ocean": {"ceiling": ocean["ceiling"], "top": ocean["top"], "bottom": ocean["bottom"], "x0": ocean["x0"], "x1": ocean["x1"]},
		"dome": d.global_position, "dome_cell": dome_cell, "tile00": Level.map.getTilePos(Vector2(0, 0)), "entries": td.get_entry_coords(true), "top_rows": top_open,
		"keeper": h.keeper().global_position, "keeper_cell": h.keeper_tile()})
	# A straight shaft of 40 rows somewhere mid-map, climbed with ui_up held.
	var x: int = 6
	var y0: int = 60
	await h.dig_room(Vector2i(x, y0), Vector2i(x + 1, y0 + 40))
	await h.teleport_tile(Vector2i(x, y0 + 40))
	await h.wait(1.0)
	var k = h.keeper()
	var start: Vector2 = k.global_position
	var t0: float = h.now()
	h.down("ui_up")
	await h.until(func(): return k.global_position.y < start.y - 30.0 * 24.0, 30.0)
	h.up("ui_up")
	var dt: float = h.now() - t0
	h.note("climb", {"keeper": k.playerId, "rows": 30, "seconds": dt, "px_per_s": 30.0 * 24.0 / dt})
	h.check("climbed", dt < 29.0, dt)
