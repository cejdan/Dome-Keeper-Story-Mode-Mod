extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 132 (playtest fix): pressing a New Gadget entry without the money
# must not open the gadget choice. The panel shows the shop's "can't afford"
# error instead, nothing is charged, and with the money it opens as before.

const GadgetShop = preload("res://mods-unpacked/cejdan-StoryMode/gamemode/gadget_shop.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


func _popup_open() -> bool:
	var p = Level.stage.currentGadgetPopupByPlayerId.get("player1", null)
	return p != null and is_instance_valid(p) and p.is_inside_tree()


func _shop(h):
	for n in h.get_tree().root.find_children("*", "", true, false):
		if n.has_method("buyUpgrade") and n.has_method("updateCostLabels") and n.find_child("TechTree") != null:
			return n
	return null


# Opens the shop and puts the focus on the first New Gadget entry.
func _focus_entry(h):
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	var shop = _shop(h)
	var tree = shop.find_child("TechTree") if shop else null
	var entry: String = GadgetShop.next_entry("team1")
	var panel = null
	if tree:
		for track in tree.get_node("Tracks").get_children():
			for p in track.techPanels.values():
				if p.techId == entry:
					panel = p
	if panel:
		InputSystem.grabFocus(panel)
	await h.wait(0.8)
	return panel


func run(h) -> void:
	h.disable_waves()
	await h.wait(1.0)
	var entry: String = GadgetShop.next_entry("team1")
	var price: int = GadgetShop.price("team1")
	h.set_inv("money", price - 1)
	var panel = await _focus_entry(h)
	h.check("the New Gadget I panel is focused", panel != null and _shop(h).find_child("TechTree").focussedTechPanel == panel, entry)
	await h.press("ui_select")
	await h.wait(0.6)
	await h.shot("broke_press")
	await h.wait(1.0)
	h.check("$%d short: the gadget choice stays shut" % 1, not _popup_open())
	h.check("nothing charged, nothing bought", h.inv("money") == price - 1 and not GameWorld.boughtUpgrades.has(entry), {"money": h.inv("money")})
	await h.shot("broke_after")
	await h.press("ui_cancel")
	await h.wait(1.0)

	# With the money, the same press opens it.
	h.set_inv("money", price)
	panel = await _focus_entry(h)
	await h.press("ui_select")
	await h.until(func(): return _popup_open(), 5.0)
	await h.wait(1.0)
	await h.shot("paid_press")
	h.check("with $%d the press opens the gadget choice" % price, _popup_open())
	h.check("opening still charges nothing", h.inv("money") == price, h.inv("money"))
	h.snap("end", [])
