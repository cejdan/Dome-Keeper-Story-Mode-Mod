extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 95, part two: run t95_awakening first. Loads its save (slot 14) in a
# fresh process: ten unobtainium mined, the horror awake, no beat replays.

const Awakening = preload("res://mods-unpacked/cejdan-StoryMode/beats/awakening.gd")
const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")


func boot() -> Dictionary:
	return {"load": 14, "beats": true}


func run(h) -> void:
	await h.until(func(): return not SaveGame.currentLoadingSavegame, 20.0)
	await h.wait(1.0)
	h.disable_waves()
	h.check("the awakening survives the reload", Awakening.mined() == 10 and Awakening.is_awake() and Awakening.level() == 1.0, [Awakening.mined(), Awakening.is_awake()])
	var replays: Array = []
	for id: String in ["unobtainium_1", "unobtainium_3", "unobtainium_5", "unobtainium_7", "unobtainium_10", "boss_chamber", "boss_wait"]:
		if StoryBeats.fire(id):
			replays.append(id)
	h.check("no awakening beat plays again", replays.is_empty(), replays)
