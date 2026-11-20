extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 213, in the shop itself: the Vent the Dome panel. Pressed while the
# dome is clean it is refused and costs nothing; pressed with gas in the dome
# it is bought, takes its water and clears the gas; it stays on the shop to be
# bought again.

const GasData = preload("res://mods-unpacked/cejdan-StoryMode/data/gas.gd")
const VENT := "team1.storyventdome"


func boot() -> Dictionary:
	return {"seed": 12345}


func _shop(h):
	for n in h.get_tree().root.find_children("*", "", true, false):
		if n.has_method("buyUpgrade") and n.has_method("updateCostLabels") and n.find_child("TechTree") != null:
			return n
	return null


func _focus_vent(h):
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	var shop = _shop(h)
	var tree = shop.find_child("TechTree") if shop else null
	var panel = null
	if tree:
		for track in tree.get_node("Tracks").get_children():
			for p in track.techPanels.values():
				if p.techId == VENT:
					panel = p
	if panel:
		InputSystem.grabFocus(panel)
	await h.wait(0.8)
	return panel


func run(h) -> void:
	h.disable_waves()
	await h.until(func(): return Level.map.get_node_or_null("StoryGasField") != null, 10.0)
	var field = Level.map.get_node("StoryGasField")
	await h.wait(1.0)
	h.set_inv("water", 5)

	# ---- clean dome: refused
	var panel = await _focus_vent(h)
	h.check("the shop shows Vent the Dome", panel != null)
	await h.shot("vent_panel")
	await h.press("ui_select")
	await h.wait(0.8)
	await h.shot("vent_refused")
	h.check("with a clean dome it is refused: no water taken", int(h.inv("water")) == 5 and field.dome.vents == 0, [h.inv("water"), field.dome.vents])
	await h.press("ui_cancel")
	await h.wait(1.0)

	# ---- gas in the dome: bought
	field.dome.amount = 3 * GasData.DOME_POCKET_MASS
	await h.wait(1.0)
	panel = await _focus_vent(h)
	await h.press("ui_select")
	await h.wait(0.8)
	await h.shot("vent_bought")
	h.check("with gas in the dome it is bought: 2 water, the gas gone", int(h.inv("water")) == 3 and field.dome.amount == 0.0 and field.dome.vents == 1, [h.inv("water"), field.dome.amount])
	h.check("it stays on the shop to buy again", GameWorld.upgrades.has(VENT) and panel != null and is_instance_valid(panel))
	await h.press("ui_cancel")
	await h.wait(2.5)
	await h.shot("dome_after_vent")
