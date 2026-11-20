extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 26, vanilla side: a Relic Hunt run has no story beats. Digging deep
# and calling the triggers does nothing.

const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
static var _StoryBeats = StoryBeats  # calls go through this: lazy_preload makes const-preload calls slow


func boot() -> Dictionary:
	return {"mode": "relichunt", "seed": 12345}


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	h.check("no beats node in a vanilla run", _StoryBeats.instance() == null)
	await h.dig_room(Vector2i(-2, 20), Vector2i(2, 24))
	await h.teleport_tile(Vector2i(0, 24))
	await h.wait(2.0)
	h.check("trigger() does nothing", _StoryBeats.trigger("biome:B2") == 0 and not _StoryBeats.fire("first_gem"))
	await h.wait(1.0)
	h.check("no beat box ever opens", h.beat_box() == null and not _StoryBeats.is_open())
	await h.shot("vanilla_deep")
