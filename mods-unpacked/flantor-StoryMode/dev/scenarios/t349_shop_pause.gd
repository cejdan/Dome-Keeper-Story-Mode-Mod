extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 349: the gadget choice opened from the shop (New Gadget I-IV) used to
# unpause the game when it closed, so the run went on behind the still-open
# shop. Now Cancel and a pick both leave the game paused until the shop closes.

const GadgetShop = preload("res://mods-unpacked/flantor-StoryMode/gamemode/gadget_shop.gd")
static var _GadgetShop = GadgetShop


func boot() -> Dictionary:
	return {"seed": 12345}


func _popup_open() -> bool:
	var p = Level.stage.currentGadgetPopupByPlayerId.get("player1", null)
	return p != null and is_instance_valid(p) and p.is_inside_tree()


func _open_choice(h) -> void:
	Level.stage.openStoryGadgetChoice("team1", "player1")
	await h.until(func(): return _popup_open(), 5.0)
	await h.wait(1.0)


func run(h) -> void:
	h.disable_waves()
	await h.wait(1.0)
	h.set_inv("money", 100000)
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	h.check("the shop pauses the game", GameWorld.paused)

	await _open_choice(h)
	h.check("the choice opens over the paused shop", _popup_open() and GameWorld.paused)
	await h.press("ui_cancel")
	await h.wait(1.5)
	h.check("Cancel closes the choice and the game stays paused", not _popup_open() and GameWorld.paused and not Level.stage.showingChoicePopup,
		{"popup": _popup_open(), "paused": GameWorld.paused, "showingChoicePopup": Level.stage.showingChoicePopup})
	await h.shot("after_cancel")

	await _open_choice(h)
	var offers: Array = _GadgetShop.offers("team1", "player1")
	h.check("the choice has offers", not offers.is_empty(), offers)
	if not offers.is_empty():
		Level.stage.onGadgetSelected(offers[0], CONST.GADGET, "player1", "team1")
	await h.wait(2.0)
	h.check("a pick closes the choice and the game stays paused", not _popup_open() and GameWorld.paused and GameWorld.boughtUpgrades.has(offers[0] if offers.size() else ""),
		{"popup": _popup_open(), "paused": GameWorld.paused})
	await h.shot("after_pick")

	await h.press("ui_cancel")
	await h.wait(1.5)
	h.check("closing the shop unpauses the game", not GameWorld.paused)
	await h.shot("shop_closed")
