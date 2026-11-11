extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 12: the tech tree shows and charges dollar costs.


func boot() -> Dictionary:
	return {"seed": 12345}


func _cost(id: String) -> Dictionary:
	for prefix: String in ["", "team1.", "player1."]:
		if GameWorld.upgrades.has(prefix + id):
			return GameWorld.upgrades[prefix + id].get("cost", {})
	return {"missing": id}


func _bought(id: String) -> bool:
	for prefix: String in ["", "team1.", "player1."]:
		if GameWorld.boughtUpgrades.has(prefix + id):
			return true
	return false


func run(h) -> void:
	h.disable_waves()
	var expected: Dictionary = {"drill1": 4, "drill2": 15, "drill3": 200, "drill4": 1400, "jetpackspeed1": 4, "laserstrength1": 6, "domehealthmeter": 2}
	for id: String in expected:
		var c: Dictionary = _cost(id)
		h.check("%s costs $%d and no iron" % [id, expected[id]], c.get("money", -1) == expected[id] and not c.has("iron"), c)
	h.check("shield strength keeps its water", _cost("shieldstrength1") == {"money": 7, "water": 2}, _cost("shieldstrength1"))
	h.check("water-only cost untouched", _cost("domeresourcecounters") == {"water": 1}, _cost("domeresourcecounters"))

	h.set_inv("money", 100)
	h.set_inv("water", 3)
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	await h.shot("techtree_dollar_prices")
	# Walk the focus around so the cost panel shows a few different upgrades.
	await h.press("ui_right")
	await h.wait(0.4)
	await h.shot("techtree_focus_right")
	await h.press("ui_down")
	await h.wait(0.4)
	await h.shot("techtree_focus_down")

	var ok: bool = await h.buy("drill1")
	h.check("drill1 bought", ok and _bought("drill1"))
	h.check("drill1 charged $4", h.inv("money") == 96, h.inv("money"))
	var refused: bool = not (await h.buy("laserstrength4"))
	h.check("laserstrength4 ($6,300) refused with $96", refused and not _bought("laserstrength4") and h.inv("money") == 96, h.inv("money"))
	ok = await h.buy("shieldstrength1")
	h.check("shieldstrength1 charged $7 and 2 water", ok and h.inv("money") == 89 and h.inv("water") == 1, [h.inv("money"), h.inv("water")])
	await h.wait(0.6)
	await h.shot("techtree_after_buying")
	h.snap("end")
