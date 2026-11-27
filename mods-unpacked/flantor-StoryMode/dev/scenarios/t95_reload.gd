extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 95, part two: run t95_awakening first. Loads its save (slot 14) in a
# fresh process: ten chains broken (#365; ten unobtainium before), the horror
# awake, no beat replays.

const Awakening = preload("res://mods-unpacked/flantor-StoryMode/beats/awakening.gd")
static var _Awakening = Awakening  # calls go through this: lazy_preload makes const-preload calls slow
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
static var _StoryBeats = StoryBeats  # calls go through this: lazy_preload makes const-preload calls slow


func boot() -> Dictionary:
	return {"load": 14, "beats": true, "boss": false}


func run(h) -> void:
	await h.until(func(): return not SaveGame.currentLoadingSavegame, 20.0)
	await h.wait(1.0)
	h.disable_waves()
	h.check("the awakening survives the reload", _Awakening.chains() == 10 and _Awakening.is_awake() and _Awakening.level() == 1.0, [_Awakening.chains(), _Awakening.is_awake()])
	var replays: Array = []
	for id: String in ["boss_chamber"]:
		if _StoryBeats.fire(id):
			replays.append(id)
	h.check("no awakening beat plays again", replays.is_empty(), replays)
