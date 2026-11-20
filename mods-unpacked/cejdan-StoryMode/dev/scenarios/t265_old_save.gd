extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# #265 (1/2): a save as one from before #265 holds it: the team bought Heat
# Shielding I-III (team1.storyheatshield1-3, Data team1.suit.heatshield = 3)
# and the Suit Blaster (team1.storysuitblaster; the keeper has its blaster),
# and there are no per-keeper entries or limits (dev/old_heat_save.gd). Saved
# into the singleplayer folder, slot SLOT. Then t265_old_load loads it.

const SLOT := 26
const OldSave = preload("res://mods-unpacked/cejdan-StoryMode/dev/old_heat_save.gd")


func boot() -> Dictionary:
	return {"seed": 26500}


func run(h) -> void:
	h.disable_waves()
	await h.wait(1.0)
	var old: Dictionary = OldSave.make_old(3, true)
	h.note("made old", old)
	h.check("the run looks like a save from before #265", old["limits"].is_empty() and old["team entries"].size() == 5 and Data.ofOr("team1.suit.heatshield", 0) == 3
		and not GameWorld.upgrades.has("player1.storyheatshield1"), old)
	Data.apply("team1.inventory.money", 1234)
	SaveGame.saveGame("singleplayer", SLOT, true)
	await h.wait(1.0)
	h.check("saved", FileAccess.file_exists("user://singleplayer/savegame_%d.json" % SLOT))
