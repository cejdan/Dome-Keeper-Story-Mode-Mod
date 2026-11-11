extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 6: a vanilla Relic Hunt run still starts with the mod loaded.


func boot() -> Dictionary:
	return {"mode": "relichunt", "seed": 12345}


func run(h) -> void:
	h.check("mode is relichunt", Level.loadout.modeId == "relichunt", Level.loadout.modeId)
	h.check("vanilla mode node", Level.mode is Relichunt)
	await h.hold("ui_right", 0.25)
	await h.hold("ui_down", 6.0)
	h.snap("after drilling down")
	await h.shot("vanilla_in_mine")
	h.check("keeper went down", h.keeper_tile().y >= 1, h.keeper_tile())
