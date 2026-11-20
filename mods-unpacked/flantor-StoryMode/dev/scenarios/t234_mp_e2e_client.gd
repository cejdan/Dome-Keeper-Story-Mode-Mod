extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #234: an online co-op run end to end, client half: what the client's keeper
# does and what the client sees. Pair: t234_mp_e2e_host (with
# t234_mp_e2e_leaver as -Client2); the steps are listed there.

const TIMEOUT := 1050
const Host = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t234_mp_e2e_host.gd")
const GadgetShop = preload("res://mods-unpacked/flantor-StoryMode/gamemode/gadget_shop.gd")
const Metal = preload("res://mods-unpacked/flantor-StoryMode/data/metal.gd")
const Runes = preload("res://mods-unpacked/flantor-StoryMode/pleas/runes.gd")
const Endings = preload("res://mods-unpacked/flantor-StoryMode/data/endings.gd")

var _held: Dictionary = {}


func boot() -> Dictionary:
	return {"netjoin": true}


func _popup(me: String):
	var p = Level.stage.currentGadgetPopupByPlayerId.get(me, null)
	return p if p != null and is_instance_valid(p) and p.is_inside_tree() and is_instance_valid(p.inputProcessor) and not p.inputProcessor.desintegrating else null


func _shown(me: String) -> Array:
	var p = _popup(me)
	return Host._sorted(p.offersById.keys()) if p else []


func _shop(h):
	for n in h.get_tree().root.find_children("*", "", true, false):
		if n.has_method("buyUpgrade") and n.has_method("updateCostLabels") and n.find_child("TechTree") != null and n.is_inside_tree():
			return n
	return null


# Opens this keeper's shop and focuses the next New Gadget entry (t132_broke).
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


func _carried(type: String = "") -> int:
	return Keepers.first().carriedCarryables.filter(func(c): return is_instance_valid(c) and (type == "" or c.type == type)).size()


# To the room under the dome (the host brings its copies of the carried drops
# along), then up into the dome with the keeper's own flying.
func _fly_home(h, what: String) -> void:
	await h.teleport_tile(Host.UNDER)
	await shared(h, "fly_" + what, 40.0)
	await h.wait(0.5)
	h.note("%s: carried under the dome" % what, Keepers.first().carriedCarryables.map(func(c): return c.type if is_instance_valid(c) else null))
	# Up through the cellar (the Teleporter's) into the dome's main room.
	for i in 6:
		await h.hold("ui_up", 1.5)
		if Keepers.first().isInsideDome and Level.map.getTileCoord(Keepers.first().global_position).y <= -5:
			break
	await h.wait(1.0)
	h.check("%s: the client's keeper flew into the dome" % what, Keepers.first().isInsideDome, Level.map.getTileCoord(Keepers.first().global_position))


# Facts as one instance and as JSON from another: numbers compared as floats.
static func _same(a: Dictionary, b) -> bool:
	if not b is Dictionary or a.size() != b.size():
		return false
	for k in a:
		var x = a[k]
		var y = b.get(k)
		if (x is int or x is float) and (y is int or y is float):
			if absf(float(x) - float(y)) > 0.001:
				return false
		elif str(x) != str(y):
			return false
	return true


func _has_shared(key: String) -> bool:
	var have = Data.ofOr(DEV_SHARE, "")
	return have is String and have != "" and JSON.parse_string(have).has(key)


func _buy(h, id: String, me: String) -> void:
	# Paid in what its cost names (Sand Repair: sand; a repeatable one is not
	# kept in boughtUpgrades).
	var c0 = GameWorld.upgrades.get(id, {}).get("cost", {})
	var cost: Dictionary = c0 if c0 is Dictionary else {}
	var inv0: Dictionary = {}
	for t in cost:
		inv0[t] = int(Data.ofOr("team1.inventory." + t, 0))
	GameWorld.buyUpgrade(id, "team1", me)
	var paid := func() -> bool:
		for t in cost:
			if int(inv0[t]) - int(Data.ofOr("team1.inventory." + t, 0)) != int(cost[t]):
				return false
		return true
	var ok: bool = await h.until(func(): return paid.call() and (GameWorld.boughtUpgrades.has(id) or GameWorld.upgrades.get(id, {}).get("repeatable", false)), 10.0)
	h.check("client buys %s for %s" % [id, cost], ok and not cost.is_empty(), {"before": inv0, "bought": GameWorld.boughtUpgrades.has(id)})


func run(h) -> void:
	var me: String = Keepers.first().playerId
	h.check("this is a client, keeper player2", not h.multiplayer.is_server() and me == "player2", me)
	var dome = Level.getDome("team1")

	# ---- 2. The host's sale.
	var hm = await shared(h, "host_sold", 300.0)
	h.check("the host's sale: the same money here", hm != null and await h.until(func(): return Host.money() == int(hm), 10.0), [Host.money(), hm])
	await h.shot("client_host_sale")

	# ---- 3. This keeper carries iron and the bones home.
	var b = await shared(h, "bones", 60.0)
	var bones_at := Vector2i(int(b[0]), int(b[1]))
	await h.teleport_tile(bones_at + Vector2i(0, -1))
	await shared(h, "carry_home", 60.0)
	var carrying: bool = await h.until(func(): return _carried() >= 4, 15.0)
	h.check("the client's keeper carries the 3 iron and the bones", carrying, Keepers.first().carriedCarryables.map(func(c): return c.type if is_instance_valid(c) else null))
	await h.shot("client_carrying")
	await _fly_home(h, "sale")
	var cm = await shared(h, "client_sold", 40.0)
	h.check("the client's sale: the host's money here", cm != null and await h.until(func(): return Host.money() == int(cm), 10.0), [Host.money(), cm])
	await h.wait(0.5)
	await h.shot("client_sold_home")

	# ---- 4. The B2 translator.
	var c = await shared(h, "chamber", 60.0)
	var ch_at := Vector2i(int(c[0]), int(c[1]))
	await h.teleport_tile(ch_at + Vector2i(0, -1))
	await shared(h, "chamber_open", 40.0)
	await h.teleport_tile(ch_at + Vector2i(1, 1))
	await h.wait(1.0)
	var chamber = null
	for n in Level.map.find_children("*", "", true, false):
		if n.get_script() != null and str(n.get_script().resource_path).ends_with("TranslatorChamber.gd"):
			if chamber == null or n.global_position.distance_to(h.keeper().global_position) < chamber.global_position.distance_to(h.keeper().global_position):
				chamber = n
	var sync = null
	if chamber != null:
		for n in chamber.find_children("*", "", true, false):
			if n.has_method("on_chamber_hit"):
				sync = n
	h.note("the chamber's state here", chamber.currentState if chamber else null)
	h.check("the client finds the chamber's synchronizer", sync != null)
	if sync != null:
		sync.on_chamber_hit(h.keeper())   # the keeper's hit, as Chamber does
	var got: bool = await h.until(func(): return _carried("translator") == 1, 10.0)
	h.check("the client's keeper carries the translator", got, _carried())
	await h.shot("client_translator")
	await _fly_home(h, "translator")
	var stage = await shared(h, "translated", 60.0)
	h.check("the plea stage is the host's here", stage != null and await h.until(func(): return Runes.stage() == int(stage), 10.0), [Runes.stage(), stage])
	await h.wait(1.0)
	await h.shot("client_translated")

	# ---- 5. The shop.
	var hf = await shared(h, "shop_go", 60.0)
	await h.wait(1.0)
	h.check("the host's drill upgrade as the host saw it", _same(Host.shop_facts(), hf), [Host.shop_facts(), hf])
	for id in ["player2.drill1", "player2.storyheatshield1", "player2.storyheatshield2", "player2.storyheatshield3", "player2.storyheatshield4", "player2.storysuitblaster", "team1.domehealthmeter", "team1.domesecondweapon"]:
		await h.wait(1.0)
		await _buy(h, id, me)
	# Sand Repair, Second Weapon's predecessor, counts while it can be bought;
	# at full health vanilla refuses it (nothing to repair).
	h.check("Sand Repair is in the shop on the way to Second Weapon", GameWorld.upgrades.has("team1.domesandrepair"))
	var f = await shared(h, "shop_facts", 60.0)
	await h.wait(1.0)
	h.note("shop facts on the client", Host.shop_facts())
	h.check("shop facts are the host's here", _same(Host.shop_facts(), f), [Host.shop_facts(), f])

	# ---- 6. The gadget shop through the real shop panel.
	await shared(h, "panel_go", 60.0)
	var entries: Array = GadgetShop.entries("team1")
	var m0: int = Host.money()
	var panel = await _focus_entry(h)
	var shop = _shop(h)
	h.check("New Gadget II is focused in the client's shop", panel != null and shop != null and shop.find_child("TechTree").focussedTechPanel == panel and panel.techId == entries[1], panel.techId if panel else null)
	await h.shot("client_shop_panel")
	await h.press("ui_select")
	var opened: bool = await h.until(func(): return _popup(me) != null and not _shown(me).is_empty(), 10.0)
	h.check("pressing the panel opens the gadget choice", opened)
	await h.wait(1.5)
	await h.shot("client_panel_offers")
	var p = _popup(me)
	var focused: String = str(p.selectedGadget.get("id", "")) if p and p.selectedGadget is Dictionary else ""
	h.check("a card has the focus when the choice opens over the shop", focused != "", focused)
	await h.press("ui_select")
	var bought: bool = await h.until(func(): return GameWorld.boughtUpgrades.has(entries[1]) and GameWorld.boughtUpgrades.has(focused), 10.0)
	h.check("the pick buys New Gadget II and the focused gadget", bought and m0 - Host.money() == Host.cost(entries[1]), {"pick": focused, "paid": m0 - Host.money()})
	await h.wait(1.0)
	for i in 4:
		if _shop(h) == null and _popup(me) == null:
			break
		await h.press("ui_cancel")
		await h.wait(1.0)
	h.check("the shop closes", _shop(h) == null and _popup(me) == null)

	# Host and client at once.
	await shared(h, "both_go", 60.0)
	Level.stage.openStoryGadgetChoice("team1", me)
	opened = await h.until(func(): return _popup(me) != null and not _shown(me).is_empty(), 15.0)
	var offers = await shared(h, "both_offers", 60.0)
	h.check("the client's choice is open with the host's offers", opened and offers != null and _shown(me) == Host._sorted(offers), [_shown(me), offers])
	await h.shot("client_both_open")
	var hp = await shared(h, "host_picked", 30.0)
	await h.wait(1.0)
	var mine: Array = _shown(me).filter(func(o): return o != hp)
	var other: String = mine[0] if mine.size() > 0 else ""
	Level.stage.onGadgetSelected(other, CONST.GADGET, me, "team1")
	await h.wait(4.0)
	var accepted: bool = GameWorld.boughtUpgrades.has(other)
	var still_open: bool = _popup(me) != null
	h.note("the client's pick after the host's", {"pick": other, "accepted": accepted, "popup still open": still_open, "shown": _shown(me), "offers now": Data.ofOr("team1.story.gadgetoffers", "")})
	await h.shot("client_after_both")
	if still_open:
		await h.press("ui_cancel")
		await h.wait(2.0)
	h.check("the client's choice is closed (picked, or Cancel)", _popup(me) == null)
	var br = await shared(h, "both_result", 40.0)
	await h.wait(1.0)
	h.check("gadgets and money as the host has them", br != null and Host.gadgets_bought().size() == int(br["gadgets"]) and Host.money() == int(br["money"]), [Host.gadgets_bought().size(), Host.money(), br])

	# ---- 7. The gate, then the Metal Bit.
	var g = await shared(h, "gate", 60.0)
	if g != null:
		var gate := Vector2i(int(g[0]), int(g[1]))
		await h.teleport_tile(gate + Vector2i(0, -1))
		await h.until(func(): return float(Data.ofOr(me + ".suitblaster.charge", 0.0)) >= 1.0, 15.0)
		await h.wait(1.5)
		await h.shot("client_on_gate")
		await h.press("keeper_gadget1")
		await h.burst("client_blast", 8, 3)
		var td = Level.map.tileData
		var tb: float = h.now()
		var broke: bool = await h.until(func(): return td.get_resourcev(gate) != Metal.GATE_ID, 40.0)
		h.check("the client's Suit Blaster breaks the gate tile here", broke, {"tile": td.get_resourcev(gate), "after s": h.now() - tb, "keeper": h.keeper_tile(), "gate": gate})
		await shared(h, "gate_broken", 30.0)
		h.note("map nodes with a Synchronizer (client)", Host.synced_map_nodes())
		await h.shot("client_gate_broken")
	await shared(h, "metalbit_go", 60.0)
	await _buy(h, "team1." + Metal.DRILL_UPGRADE, me)
	h.keeper().teleport(dome.global_position + Vector2(0, -8))
	h.snap_camera()

	# ---- 8. The wave, from the secondary station.
	await shared(h, "wave_go", 60.0)
	await Host.close_pause(h, "client")
	var st1 = Host.station(dome, 1)
	var inside: bool = st1 != null and await Host.enter_station(h, st1, h.keeper())
	var guns: Array = st1.getControlledWeapons() if st1 != null else []
	h.check("the client's keeper takes the secondary station, with a laser", inside and guns.size() >= 1, {"inside": inside, "guns": guns.size()})
	await shared(h, "wave_on", 120.0)
	var seen: int = 0
	var t0: float = h.now()
	while h.now() - t0 < 140.0 and not _has_shared("wave_over"):
		seen = maxi(seen, Host.monsters(h).size())
		if guns.size() > 0:
			Host.fight_step(h, guns[0], _held)
		await h.frames(2)
		if h.now() - t0 > 3.0 and not _held.get("shot", false):
			_held["shot"] = true
			await h.shot("client_wave")
	Host.release(h, _held)
	h.check("the wave's monsters showed on the client", seen > 0, seen)
	var wo = await shared(h, "wave_over", 10.0)
	await h.wait(1.0)
	h.check("the wave is over here; the dome's health is the host's", wo != null and not Data.ofOr("team1.monsters.wavepresent", false) and absf(float(Data.ofOr("team1.dome.health", 0)) - float(wo["health"])) < 1.0, [Data.ofOr("team1.dome.health", 0), wo])
	if st1 != null and h.keeper().isInsideStation:
		st1.useHit(h.keeper())
	await h.wait(1.0)

	# ---- 9. Retire Rich.
	await shared(h, "rich", 60.0)
	await h.until(func(): return Host.money() >= 1000000, 10.0)
	var ok: bool = await h.buy("storyretirerich")
	h.check("the client buys Retire Rich", ok)
	var panel_up: bool = await Host.to_end_screen(h, 180.0)
	h.check("end screen on the client, the doom ending's", panel_up and GameWorld.won and Level.stage.endingPanel.titleLabel.text == Endings.DOOM_TITLE, [GameWorld.won, Level.stage.endingPanel.titleLabel.text if panel_up else null])
	await h.wait(2.0)
	await h.shot("client_end_screen")
	h.check("one end screen here", Level.mode.end_screens == 1, Level.mode.end_screens)
	await h.wait(2.0)
