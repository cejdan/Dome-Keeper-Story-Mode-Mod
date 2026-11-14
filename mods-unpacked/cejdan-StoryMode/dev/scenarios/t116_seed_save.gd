extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 116, part one: a seed-12345 run records its seed in the map data and
# saves to slot 18, with markers for t116_seed_reload: the palette in use and
# a lava field value (recalls = 4242) that only a restored lava save brings back.
# A shaft is dug from the surface into the lava ocean (as a player reaches it),
# and the keeper waits just above the ocean, which draws lava, not black.

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	var td = Level.map.tileData
	h.check("the map data carries the run's seed", td.has_meta(Story.SEED_META) and int(td.get_meta(Story.SEED_META)) == 12345, td.get_meta(Story.SEED_META, null))
	var field = Level.map.get_node("StoryLavaField")
	# A shaft from the surface down through the ocean's ceiling.
	var oc: Dictionary = td.get_meta("story_ocean")
	var entries: Array = td.get_entry_coords(true)
	var entry: Vector2i = Vector2i(entries[0])
	var x: int = entry.x
	var top: int = int(oc["top"])
	h.note("shaft", {"entry": entries, "x": x, "ocean": [oc["x0"], oc["x1"], top]})
	var shaft: Array = []
	for y in range(entry.y, top):
		shaft.append(Vector2i(x, y))
	# Revealed, then broken (tiles only exist once revealed), down to the last
	# ceiling row; breaking it lets the flood reveal reach the ocean below.
	await h.reveal(shaft)
	await h.clear_tiles(shaft)
	# Metal and the gate only break to the Suit Blaster: break those directly.
	for c: Vector2i in shaft:
		var t = Level.map.getTile(Vector2(c))
		if td.get_resourcev(c) != -1 and t != null:
			Level.map.destroyTile("team1", "", t)
	await h.frames(3)
	await h.reveal([Vector2i(x, top - 1)])
	var solid: Array = shaft.filter(func(c): return td.get_resourcev(c) != -1)
	h.check("the shaft is really dug (empty in the map data)", solid.is_empty(), solid.slice(0, 10))
	await h.teleport_tile(Vector2i(x, top - 4))
	h.snap_camera()
	await h.wait(2.0)
	var probe: Vector2i = Vector2i(x, top + 1)
	h.check("the ocean under the shaft is seen and holds lava", field._seen(probe) and field.mass.get(probe, 0.0) > 0.5, {"seen": field._seen(probe), "mass": field.mass.get(probe, 0.0)})
	Data.apply("dev.t116.probe", [probe.x, probe.y])
	await h.shot("ocean_before_save")
	field.recalls = 4242
	Data.apply("dev.t116.palette", Level.loadout.palette)
	h.note("before save", {"seed": Level.levelSeed, "palette": Level.loadout.palette, "lava cells": field.mass.size()})
	await SaveGame.saveGame("singleplayer", 18, true)
	await h.wait(1.0)
	h.note("saved slot 18")
