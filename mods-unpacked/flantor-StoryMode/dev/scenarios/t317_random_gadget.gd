extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 317: "Roll a random gadget for the dome" did nothing. Clicked twice
# with the mouse, a New Gadget entry was bought the vanilla way (price paid,
# next entry unlocked) without opening the gadget choice, so no gadget came.
# Here the entry is clicked twice in the open shop: the gadget choice must
# open, charge nothing until a pick, and the pick must install the gadget.
# The keyboard path (select on the focused entry) is checked on the next one.

const GadgetShop = preload("res://mods-unpacked/flantor-StoryMode/gamemode/gadget_shop.gd")
static var _GadgetShop = GadgetShop  # calls go through this: lazy_preload makes const-preload calls slow


func boot() -> Dictionary:
	return {"seed": 12345}


func _popup_open() -> bool:
	var p = Level.stage.currentGadgetPopupByPlayerId.get("player1", null)
	return p != null and is_instance_valid(p) and p.is_inside_tree()


func _panel(id: String, n: Node = null):
	if n == null:
		n = Level.stage.get_tree().root
	if n.get("techId") == id and n is Control:
		return n
	for c in n.get_children():
		var p = _panel(id, c)
		if p != null:
			return p
	return null


func _cost(id: String) -> int:
	var c = GameWorld.upgrades.get(id, {}).get("cost", {})
	return int(c.get("money", -1)) if c is Dictionary else -1


# A left click on the panel: a real one at its screen position; if that does
# not reach it (synthetic clicks may miss in a harness window), the click the
# panel's own mouse handler gets.
func _click(h, panel: Control) -> void:
	var before: int = panel.focusCounter
	var pos: Vector2 = panel.get_viewport().get_screen_transform() * panel.get_global_transform_with_canvas() * (panel.size * 0.5)
	Input.warp_mouse(pos)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		Input.parse_input_event(e)
		await h.frames(2)
	if panel.focusCounter == before and not _popup_open() and is_instance_valid(panel):
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = true
		panel._gui_input(e)
		h.note("click sent to the panel's handler")
	await h.wait(0.4)


func run(h) -> void:
	h.disable_waves()
	await h.wait(1.0)
	h.set_inv("money", 100000)
	var entries: Array = _GadgetShop.entries("team1")
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)

	# ---- New Gadget I by mouse: two clicks
	var p1 = _panel(entries[0])
	h.check("the shop shows New Gadget I", p1 != null)
	if p1 == null:
		return
	InputSystem.grabFocus(p1)
	await h.wait(0.5)
	await h.shot("shop_new_gadget_1")
	await _click(h, p1)
	await _click(h, p1)
	await h.until(func(): return _popup_open(), 3.0)
	await h.wait(0.8)
	await h.shot("clicked_twice")
	h.check("two clicks open the gadget choice and charge nothing yet",
		_popup_open() and h.inv("money") == 100000 and not GameWorld.boughtUpgrades.has(entries[0]),
		{"popup": _popup_open(), "money": h.inv("money"), "entry bought": GameWorld.boughtUpgrades.has(entries[0])})
	var offers: Array = _GadgetShop.offers("team1", "player1")
	if not _popup_open() or offers.is_empty():
		return
	var pick: String = offers[0]
	Level.stage.onGadgetSelected(pick, CONST.GADGET, "player1", "team1")
	await h.wait(2.0)
	await h.shot("picked")
	h.check("the pick installs %s for $%d" % [pick, _cost(entries[0])],
		GameWorld.boughtUpgrades.has(pick) and GameWorld.boughtUpgrades.has(entries[0]) and 100000 - int(h.inv("money")) == _cost(entries[0]) and not _popup_open(),
		{"pick": pick, "paid": 100000 - int(h.inv("money"))})

	# ---- New Gadget II by keyboard: select on the focused entry
	var p2 = _panel(entries[1])
	if p2 == null:
		h.check("the shop shows New Gadget II", false)
		return
	InputSystem.grabFocus(p2)
	await h.wait(0.5)
	await h.press("ui_select")
	await h.until(func(): return _popup_open(), 3.0)
	await h.wait(0.8)
	await h.shot("keyboard_select")
	h.check("select on New Gadget II opens the gadget choice", _popup_open() and not GameWorld.boughtUpgrades.has(entries[1]),
		{"popup": _popup_open(), "entry bought": GameWorld.boughtUpgrades.has(entries[1])})
	await h.press("ui_cancel")
	await h.wait(1.0)
