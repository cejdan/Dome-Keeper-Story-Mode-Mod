extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 11: vanilla modes have no money.


func boot() -> Dictionary:
	return {"mode": "relichunt", "seed": 12345}


func run(h) -> void:
	h.disable_waves()
	var iron0: int = h.inv("iron")
	await h.deliver("iron", 3)
	await h.until(func(): return h.inv("iron") >= iron0 + 3, 8.0)
	h.check("iron counted as iron", h.inv("iron") == iron0 + 3, h.inv("iron"))
	h.check("no money key in vanilla", not Data.has("team1.inventory.money"))
	await h.buy("domeresourcecounters")
	await h.wait(1.0)
	await h.shot("vanilla_hud")
