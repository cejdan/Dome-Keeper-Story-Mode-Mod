extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 116, part two: run t116_seed_save first. Loading slot 18 in a fresh
# process keeps the level seed (12345), so the palette is the same and the
# saved lava is restored (its marker, recalls = 4242, comes back), and the
# ocean the shaft reached is still seen, so it draws lava, not black.


func boot() -> Dictionary:
	return {"load": 18}


func run(h) -> void:
	await h.until(func(): return not SaveGame.currentLoadingSavegame, 20.0)
	await h.wait(1.0)
	h.disable_waves()
	h.check("the loaded run has its saved seed", Level.levelSeed == 12345, Level.levelSeed)
	var want: String = str(Data.ofOr("dev.t116.palette", "?"))
	h.check("the palette is the one the run was saved with (%s)" % want, Level.loadout.palette == want, Level.loadout.palette)
	var field = Level.map.get_node("StoryLavaField")
	h.check("the saved lava was restored, not placed fresh", field.recalls == 4242, {"recalls": field.recalls, "cells": field.mass.size()})
	var pr: Array = Data.ofOr("dev.t116.probe", [0, 0])
	var probe: Vector2i = Vector2i(int(pr[0]), int(pr[1]))
	var vis: Dictionary = {}
	var td = Level.map.tileData
	for y in [-3, -2, -1, 0, 1, 5, 20, 80, 150, 151, 152, 153, 160]:
		var c: Vector2i = Vector2i(probe.x, y)
		vis[str(y)] = [Level.map.visibleTileCoords.has(Vector2(c)), td.get_resourcev(c), td.get_hardnessv(c)]
	h.note("shaft visibility after load [visible, resource, hardness]", {"cells": vis, "visible total": Level.map.visibleTileCoords.size(), "entry": td.get_entry_coords(true)})
	h.snap_camera()
	await h.wait(1.0)
	h.check("the ocean under the shaft is seen and holds lava after the reload", field._seen(probe) and field.mass.get(probe, 0.0) > 0.5, {"seen": field._seen(probe), "mass": field.mass.get(probe, 0.0)})
	await h.shot("ocean_after_reload")
