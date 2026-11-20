extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #222 gap probe, client half: does the client see the host's story beat; can
# it buy from the shop; does the gadget shop (New Gadget) work from a client
# (#236: open, Cancel, reroll, pick, and a second pick).
# Pair: t222_probe_host.

const TIMEOUT := 420
const GadgetShop = preload("res://mods-unpacked/flantor-StoryMode/gamemode/gadget_shop.gd")


func boot() -> Dictionary:
	return {"netjoin": true}


func _cost(id: String) -> int:
	var c = GameWorld.upgrades.get(id, {}).get("cost", {})
	return int(c.get("money", -1)) if c is Dictionary else -1


func _money() -> int:
	return int(Data.ofOr("team1.inventory.money", 0))


func _popup(me: String):
	var p = Level.stage.currentGadgetPopupByPlayerId.get(me, null)
	return p if p != null and is_instance_valid(p) and p.is_inside_tree() and not p.inputProcessor.desintegrating else null


func _popup_open(me: String) -> bool:
	return _popup(me) != null


func _sorted(a: Array) -> Array:
	var out: Array = a.duplicate()
	out.sort()
	return out


# The choices in the client's popup.
func _shown(me: String) -> Array:
	var p = _popup(me)
	return _sorted(p.offersById.keys()) if p else []


# The host's offers, as synced through Data (read only: a client can't draw).
func _offers() -> Array:
	return Array(str(Data.ofOr("team1.story.gadgetoffers", "")).split(",", false))


# Presses New Gadget the way the shop panel does; true once the popup is up
# with offers in it.
func _open(h, me: String) -> bool:
	Level.stage.openStoryGadgetChoice("team1", me)
	var ok: bool = await h.until(func(): return _popup_open(me) and not _shown(me).is_empty(), 8.0)
	await h.wait(1.5)
	return ok


func run(h) -> void:
	var me: String = Keepers.first().playerId
	await shared(h, "beat_open", 60.0)
	await h.wait(2.0)
	h.note("client during host beat", {"beat box": h.beat_box() != null, "paused": GameWorld.paused})
	h.check("client sees the host's story beat", h.beat_box() != null)
	await h.shot("client_during_beat")
	await shared(h, "go", 60.0)
	await h.wait(1.0)
	# The welcome log is still open here (the host closed only its own) and
	# would take the key presses meant for the gadget choice: close it.
	for i in 5:
		if h.beat_box() == null:
			break
		await h.press("ui_select")
		await h.wait(1.0)
	h.note("client closed its beat box", h.beat_box() == null)
	# A plain shop buy.
	var m0: int = int(Data.ofOr("team1.inventory.money", 0))
	GameWorld.buyUpgrade(me + ".storyheatshield1", "team1", me)   # its own entry (#265)
	await h.wait(2.0)
	var m1: int = int(Data.ofOr("team1.inventory.money", 0))
	h.check("client buys Heat Shielding I", GameWorld.boughtUpgrades.has(me + ".storyheatshield1") and m0 - m1 == _cost(me + ".storyheatshield1"), {"paid": m0 - m1, "price": _cost(me + ".storyheatshield1")})
	# The gadget shop (#236): the host opens the choice, draws the offers and
	# does the paying; this client shows the popup and sends its choices.
	var entries: Array = GadgetShop.entries("team1")
	var prices: Array = entries.map(func(e): return _cost(e))
	var m2: int = _money()
	var w0: int = int(Data.ofOr("team1.inventory.water", 0))
	h.check("gadget shop popup opens on the client", await _open(h, me))
	await h.shot("client_gadget_offers")
	var first: Array = _shown(me)
	h.note("client offers", {"shown": first, "data": _offers()})
	h.check("the popup shows the host's offers, and no shred choice", first.size() == GadgetShop.offer_count("team1") and first == _sorted(_offers()), {"shown": first, "data": _offers()})
	h.check("Cancel is available (the shop's input processor)", _popup(me) != null and _popup(me).inputProcessor.get_script().resource_path.ends_with("ShopChoiceInputProcessor.gd"))
	h.check("opening charges nothing", _money() == m2, m2 - _money())
	# Cancel: free, offers kept.
	await h.press("ui_cancel")
	await h.wait(2.0)
	h.check("Cancel closes it without buying", not _popup_open(me) and _money() == m2 and not GameWorld.boughtUpgrades.has(entries[0]), {"open": _popup_open(me), "paid": m2 - _money()})
	h.check("reopening works after Cancel", await _open(h, me))
	h.check("reopening shows the same offers", _shown(me) == first, [first, _shown(me)])
	# Reroll, the way the popup's button does it: 1 water.
	if _popup_open(me):
		_popup(me)._on_reroll_button_pressed()
	await h.wait(2.0)
	var rerolled: Array = _shown(me)
	var w1: int = int(Data.ofOr("team1.inventory.water", 0))
	h.check("a reroll costs 1 water and changes the offers", w0 - w1 == 1 and rerolled != first and rerolled == _sorted(_offers()) and _money() == m2, {"water": [w0, w1], "before": first, "after": rerolled, "data": _offers()})
	await h.shot("client_gadget_rerolled")
	# Pick with the select key: pays New Gadget I.
	var p = _popup(me)
	var pick1: String = str(p.selectedGadget.get("id", "")) if p and p.selectedGadget is Dictionary else ""
	h.check("a gadget is focussed in the popup", pick1 != "" and rerolled.has(pick1), pick1)
	await h.press("ui_select")
	await h.wait(3.0)
	var m3: int = _money()
	h.note("after client gadget pick", {"paid": m2 - m3, "price": prices[0], "entry bought": GameWorld.boughtUpgrades.has(entries[0]), "pick": pick1, "pick bought": GameWorld.boughtUpgrades.has(pick1)})
	h.check("client gadget pick pays the New Gadget I price and marks it bought", m2 - m3 == prices[0] and GameWorld.boughtUpgrades.has(entries[0]) and GameWorld.boughtUpgrades.has(pick1) and not _popup_open(me), {"paid": m2 - m3, "price": prices[0], "pick": pick1, "open": _popup_open(me)})
	await h.shot("client_after_gadget")
	# New Gadget II: fresh offers, the dearer price.
	h.check("New Gadget II opens", await _open(h, me))
	await h.shot("client_gadget_2_offers")
	var second: Array = _shown(me)
	h.check("New Gadget II has fresh offers without the gadget just bought", second.size() > 0 and not second.has(pick1), second)
	if second.is_empty():
		return
	Level.stage.onGadgetSelected(second[0], CONST.GADGET, me, "team1")
	await h.wait(3.0)
	var m4: int = _money()
	h.check("the second pick pays the New Gadget II price and marks it bought", m3 - m4 == prices[1] and prices[1] > prices[0] and GameWorld.boughtUpgrades.has(entries[1]) and GameWorld.boughtUpgrades.has(second[0]) and not _popup_open(me), {"paid": m3 - m4, "price": prices[1], "pick": second[0]})
	h.check("no shop choice is left open on the client", not Level.stage.story_shop.has(me), Level.stage.story_shop)
	await h.shot("client_after_gadget_2")
	h.snap("client end", [])
