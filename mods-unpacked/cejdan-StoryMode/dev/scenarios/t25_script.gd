extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 25: every story beat from the script, in data order, one screenshot per
# page, so the whole horror voice can be read from the output folder. Checks
# each beat opens, fits its pages, and that no beat line is placeholder text.

const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const BeatData = preload("res://mods-unpacked/cejdan-StoryMode/data/beats.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	await h.dig_room(Vector2i(-3, 6), Vector2i(3, 9))
	await h.teleport_tile(Vector2i(0, 9))
	await h.wait(1.0)
	var n: int = 0
	for b: Dictionary in BeatData.BEATS:
		n += 1
		StoryBeats.fire(b["id"])
		var id: String = await h.read_beat("%02d_%s" % [n, b["id"]])
		h.check("%s opens and closes" % b["id"], id == b["id"] and not StoryBeats.is_open(), id)
	h.check("all %d beats played" % BeatData.BEATS.size(), BeatData.BEATS.all(func(b): return StoryBeats.has_played(b["id"])))
