extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 6: a Story Mode run starts and plays without errors.


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.check("mode is storymode", Level.loadout.modeId == "storymode", Level.loadout.modeId)
	h.check("mode node loaded", Level.mode != null and Level.mode.has_method("getRunWeight"))
	h.snap("start")
	await h.shot("start")
	await h.hold("ui_right", 0.25)
	await h.hold("ui_down", 9.0)
	h.snap("after drilling down")
	await h.shot("in_mine")
	h.check("keeper went down", h.keeper_tile().y >= 1, h.keeper_tile())
