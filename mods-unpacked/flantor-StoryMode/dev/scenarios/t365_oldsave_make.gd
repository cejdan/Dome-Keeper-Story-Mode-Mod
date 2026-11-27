extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #365: makes a stand-in for a Story Mode save from before #364 (no tentacles,
# no anchors, unobtainium in the ocean, the old seal's Data) with this build,
# for `t365_oldsave -Extra "--slot=62"`. Real saves that old were made under
# the mod's previous id (cejdan-StoryMode, before #310) and don't load in
# any current build; this one keeps the current id. Saves slot 62.

const AnchorData = preload("res://mods-unpacked/flantor-StoryMode/data/anchors.gd")


func boot() -> Dictionary:
	return {"seed": 4242, "boss": false}


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	var td = Level.map.tileData
	var ocean: Dictionary = td.get_meta("story_ocean")
	# Back to the old ocean: the anchors' cells open, unobtainium clumps in the
	# open lava, no tentacle or anchor meta.
	var anchors: int = 0
	for a in td.get_meta("story_anchors", []):
		for dy in 2:
			for dx in 2:
				var c: Vector2i = a["cell"] + Vector2i(dx, dy)
				var inside: bool = c.y > int(ocean["ceiling"]) and (c.y < int(ocean["top"]) or ocean["rows"].has(c.y))
				td.set_resourcev(c, Data.TILE_EMPTY if inside else Data.TILE_DIRT_START)
				anchors += 1
	var unob: int = 0
	var y: int = int(ocean["top"]) + 6
	var row: Array = ocean["rows"][y]
	for x in range(int(row[0]) + 2, int(row[1]) - 2, 5):
		td.set_resourcev(Vector2i(x, y), 47)
		unob += 1
	td.remove_meta("story_tentacles")
	td.remove_meta("story_anchors")
	Data.apply("team1.story.unobmined", 3)
	Data.apply("team1.story.unobcells", "1,2;3,4;5,6;")
	await SaveGame.saveGame("singleplayer", 62, true)
	await h.wait(1.0)
	h.check("saved a stand-in old save (slot 62)", unob > 0 and anchors == 40, {"unobtainium tiles": unob, "anchor cells undone": anchors})
