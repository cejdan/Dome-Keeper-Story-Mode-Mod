extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t365_anchors.gd"

# #365: a save from before End game 2.0 still loads. Slot 61 is a copy of a
# save made by the #364 code (t101_chains: unobtainium in the ocean, some of
# it mined, the old seal chains' record in Data, tentacles; copy it from slot
# 15 of a pre-#365 build if it is missing); `--slot=62` a stand-in for one
# from before #364 (no tentacles either), made by t365_oldsave_make. (Real
# saves that old were made under the mod's previous id, cejdan-StoryMode,
# and don't load in any current build.)
# Checks: it loads with no script error; no unobtainium tile is left; the
# ocean has its two tentacles and ten whole chain anchors (placed on load),
# with no saved lava in their cells; the old seal's Data is gone; the end
# game starts at 0 chains; an anchor breaks as usual; any old unobtainium
# drop came back as a diamond.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const Legacy = preload("res://mods-unpacked/flantor-StoryMode/gamemode/legacy_saves.gd")


func boot() -> Dictionary:
	return {"load": int(_Story.user_arg("slot", "61")), "boss": false}


func run(h) -> void:
	await h.until(func(): return not SaveGame.currentLoadingSavegame, 20.0)
	if not await setup(h):
		return
	var td = Level.map.tileData
	h.note("slot %s migration" % _Story.user_arg("slot", "61"), Legacy.last)
	h.check("no unobtainium tile is left", td.get_resource_cells_by_id(47).is_empty(), td.get_resource_cells_by_id(47).size())
	h.check("two tentacles", tents.rigs.size() == 2, tents.rigs.size())
	h.check("ten whole chain anchors", anchors.anchors.size() == 10 and anchors.anchors.all(func(a): return not a["broken"] and a["cells"].all(func(c): return td.get_resourcev(c) == AnchorData.TILE_ID)), anchors.anchors.size())
	var wet: Array = []
	for a in anchors.anchors:
		for c in a["cells"]:
			if lava != null and lava.mass.has(c):
				wet.append(c)
	h.check("no saved lava in the anchors' cells", wet.is_empty(), wet)
	h.check("the old seal's Data is gone", not Data.values.has("team1.story.unobmined") and not Data.values.has("team1.story.unobcells"))
	h.check("the end game starts at 0 chains", _EndGame.chains_broken() == 0 and not _EndGame.is_free(), _EndGame.state())
	var legacy: Array = []
	for d in Level.drops.get_children():
		if String(d.name).begins_with("LegacyUnobtainium"):
			legacy.append(d.type)
	h.note("old unobtainium drops loaded", legacy)
	h.check("old unobtainium drops came back as diamonds", legacy.all(func(t): return t == "diamond"), legacy)
	await reveal_ocean(h)
	for ti in 2:
		var mid: Vector2 = Vector2.ZERO
		for a in anchors.anchors.filter(func(x): return x["tentacle"] == ti):
			mid += a["centre"] / 5.0
		await look_at(h, mid)
		await h.shot("old_save_anchors_%d" % ti)
	var a: Dictionary = anchors.anchors[0]
	await hit_break(h, a)
	h.check("an anchor breaks as usual", a["broken"] and _EndGame.chains_broken() == 1 and chain_events.size() == 1, _EndGame.state())
