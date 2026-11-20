extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 123, part two: run t123_keeper_log first. Loading its save (slot 17,
# where the welcome is not marked played, as in a save from before #123) in a
# fresh process shows no welcome: it is for new runs only.

const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
static var _StoryBeats = StoryBeats  # calls go through this: lazy_preload makes const-preload calls slow


func boot() -> Dictionary:
	return {"load": 17, "beats": true, "welcome": true}


func run(h) -> void:
	await h.until(func(): return not SaveGame.currentLoadingSavegame, 20.0)
	h.disable_waves()
	await h.wait(4.0)
	h.check("a loaded run opens no welcome log", not _StoryBeats.is_open(), _StoryBeats.instance().open_id)
	h.check("and nothing is waiting in the queue", str(Data.ofOr("team1.story.beatsqueued", "")) == "", Data.ofOr("team1.story.beatsqueued", ""))
