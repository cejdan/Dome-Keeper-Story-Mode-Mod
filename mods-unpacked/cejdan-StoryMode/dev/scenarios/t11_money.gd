extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 11: deliveries credit dollars and the HUD shows the balance.

const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	var s0: Dictionary = h.snap("start")
	h.check("starts with $0 and no iron", s0["team1.inventory.money"] == 0 and s0["team1.inventory.iron"] == 0, s0)
	await h.deliver("iron", 3)
	await h.until(func(): return h.inv("iron") >= 3, 8.0)
	var s1: Dictionary = h.snap("after 3 iron")
	h.check("3 iron pay 3 x $5", s1["team1.inventory.money"] == 3 * Minerals.value_of("iron"), s1["team1.inventory.money"])
	await h.deliver("water", 2)
	await h.until(func(): return h.inv("water") >= 2, 8.0)
	var s2: Dictionary = h.snap("after 2 water")
	h.check("water delivered", s2["team1.inventory.water"] == 2, s2["team1.inventory.water"])
	h.check("water pays nothing", s2["team1.inventory.money"] == s1["team1.inventory.money"], s2["team1.inventory.money"])
	await h.wait(0.5)
	await h.shot("hud_balance")
	h.set_inv("money", 1234567)
	await h.wait(1.2)
	await h.shot("hud_big_balance")
	await h.buy("domeresourcecounters")
	await h.wait(1.0)
	await h.shot("hud_with_resource_counters")
