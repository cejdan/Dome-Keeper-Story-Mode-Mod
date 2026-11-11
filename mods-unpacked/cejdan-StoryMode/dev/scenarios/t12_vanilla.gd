extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 12: vanilla modes keep iron prices and the vanilla shop screen.


func boot() -> Dictionary:
	return {"mode": "relichunt", "seed": 12345}


func run(h) -> void:
	h.disable_waves()
	var c: Dictionary = GameWorld.upgrades["player1.drill1"].get("cost", {}) if GameWorld.upgrades.has("player1.drill1") else GameWorld.upgrades["team1.drill1"].get("cost", {})
	h.check("vanilla drill1 costs 4 iron", c == {"iron": 4}, c)
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	await h.shot("vanilla_techtree")
	var iron0: int = h.inv("iron")
	var ok: bool = await h.buy("drill1")
	h.check("vanilla drill1 charged 4 iron", ok and h.inv("iron") == iron0 - 4, h.inv("iron"))
