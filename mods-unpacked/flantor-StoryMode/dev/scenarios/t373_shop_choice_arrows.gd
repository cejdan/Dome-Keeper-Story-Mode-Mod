extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 373: with the gadget choice open over the shop (New Gadget I-IV), up
# and down moved the focus to the shop's panels behind it. Now the focus stays
# on the choice until it closes, and the shop takes the arrows again after.


func boot() -> Dictionary:
	return {"seed": 12345}


func _popup():
	var p = Level.stage.currentGadgetPopupByPlayerId.get("player1", null)
	return p if p != null and is_instance_valid(p) and p.is_inside_tree() else null


func _focus() -> Control:
	return h_vp.gui_get_focus_owner()


func _inside(c: Control, root) -> bool:
	return c != null and root != null and (c == root or root.is_ancestor_of(c))


var h_vp: Viewport


func run(h) -> void:
	h.disable_waves()
	await h.wait(1.0)
	h.set_inv("money", 100000)
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	var shop = InputSystem.getLastChild(h.keeper().deviceId)
	var tree: Control = shop.popup
	h_vp = tree.get_viewport()
	h.check("the shop has the focus", _inside(_focus(), tree), {"focus": str(_focus())})

	Level.stage.openStoryGadgetChoice("team1", "player1")
	await h.until(func(): return _popup() != null, 5.0)
	await h.wait(1.0)
	var popup = _popup()
	h.check("the choice has the focus", _inside(_focus(), popup), {"focus": str(_focus())})
	var left_choice := []
	for a in ["ui_down", "ui_down", "ui_up", "ui_up", "ui_up", "ui_left", "ui_right", "ui_right"]:
		await h.press(a)
		await h.wait(0.2)
		if not _inside(_focus(), popup):
			left_choice.append([a, str(_focus())])
	h.check("the arrows keep the focus on the choice", left_choice.is_empty(), left_choice)
	await h.shot("choice_after_arrows")

	await h.press("ui_cancel")
	await h.wait(1.5)
	h.check("Cancel gives the focus back to the shop", _popup() == null and _inside(_focus(), tree), {"focus": str(_focus())})
	var before: Control = _focus()
	for a in ["ui_down", "ui_up", "ui_right", "ui_left"]:
		await h.press(a)
		await h.wait(0.3)
		if _focus() != before:
			break
	h.check("the shop's arrows work again", _inside(_focus(), tree) and _focus() != before, {"before": str(before), "after": str(_focus())})
	await h.shot("shop_after_cancel")
