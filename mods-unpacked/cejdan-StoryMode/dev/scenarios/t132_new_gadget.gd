extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 132: the gadget shop is one chain, New Gadget I -> II -> III -> IV,
# each dearer. Buying one opens vanilla's gadget choice (vanilla's number of
# offers, any slot the dome can still fill), never a keeper-suit gadget; a
# reroll costs 1 water; the price is paid on pick, which unlocks the next
# entry; Cancel costs nothing. Also: upgrades of owned gadgets and the dome
# apply their property changes when bought (the user saw "nothing happens").

const GadgetShop = preload("res://mods-unpacked/cejdan-StoryMode/gamemode/gadget_shop.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


func _popup_open() -> bool:
	var p = Level.stage.currentGadgetPopupByPlayerId.get("player1", null)
	return p != null and is_instance_valid(p) and p.is_inside_tree()


func _ids(arr: Array) -> Array:
	var out: Array = arr.map(func(x): return GadgetShop._base(x))
	out.sort()
	return out


func _cost(id: String) -> int:
	var c = GameWorld.upgrades.get(id, {}).get("cost", {})
	return int(c.get("money", -1)) if c is Dictionary else -1


# Opens the chain's entry the way the shop panel does and waits for the popup.
func _open(h) -> void:
	Level.stage.openStoryGadgetChoice("team1", "player1")
	await h.until(func(): return _popup_open(), 5.0)
	await h.wait(1.0)


# Buys an upgrade and checks every property change it lists took effect.
func _check_upgrade(h, id: String) -> void:
	var u: Dictionary = GameWorld.upgrades.get(id, {})
	var changes: Array = u.get("propertychanges", [])
	var before: Dictionary = {}
	for pc in changes:
		before[pc.key] = Data.ofOr(pc.key, null)
	var ok: bool = await h.buy(id)
	var after: Dictionary = {}
	var changed: bool = changes.is_empty()
	for pc in changes:
		after[pc.key] = Data.ofOr(pc.key, null)
		changed = changed or str(after[pc.key]) != str(before[pc.key])
	h.check("%s: bought for $%d, its property changes applied" % [id, _cost(id)], ok and GameWorld.boughtUpgrades.has(id) and changed, {"ok": ok, "before": before, "after": after})


func run(h) -> void:
	h.disable_waves()
	await h.wait(1.0)
	var entries: Array = GadgetShop.entries("team1")
	var prices: Array = entries.map(func(e): return _cost(e))
	h.note("chain prices", prices)
	h.check("the shop lists New Gadget I-IV, each dearer than the last", prices.size() == 4 and prices.all(func(p): return p > 0) and prices[0] < prices[1] and prices[1] < prices[2] and prices[2] < prices[3], prices)
	h.check("no slot-specific entries are left", GameWorld.upgrades.keys().filter(func(k): return "storygadget" in k).is_empty(), GameWorld.upgrades.keys().filter(func(k): return "storygadget" in k))
	var pool: Array = _ids(GadgetShop.candidates("team1", "player1"))
	h.note("offer pool", pool)
	var suit: Array = pool.filter(func(x): return x in ["probe", "prospectionmeter", "resourcepacker", "suitblaster", "keeperonewayteleporter"])
	h.check("the pool has no keeper-suit gadget", suit.is_empty() and pool.size() > 3, {"suit": suit, "pool": pool})

	h.set_inv("money", 100000)
	h.set_inv("water", 1)
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	for i in 14:
		await h.press("ui_down")
		await h.wait(0.2)
	await h.shot("shop_story_track")
	await h.press("ui_cancel")
	await h.wait(1.0)

	# ---- New Gadget I: open, cancel (free), reopen (same offers), reroll (1 water), pick (pays I)
	await _open(h)
	var first: Array = GadgetShop.offers("team1", "player1").duplicate()
	await h.shot("new_gadget_1_offers")
	h.check("vanilla's number of offers (%d)" % GadgetShop.offer_count("team1"), first.size() == GadgetShop.offer_count("team1"), first)
	h.check("opening charges nothing", h.inv("money") == 100000, h.inv("money"))
	await h.press("ui_cancel")
	await h.wait(1.5)
	h.check("Cancel closes it without buying", not _popup_open() and h.inv("money") == 100000 and not GameWorld.boughtUpgrades.has(entries[0]))
	await _open(h)
	h.check("reopening shows the same offers", GadgetShop.offers("team1", "player1") == first, [first, GadgetShop.offers("team1", "player1")])
	Level.stage.rerollOffers("team1", "player1")
	await h.wait(1.0)
	var rerolled: Array = GadgetShop.offers("team1", "player1")
	h.check("a reroll costs 1 water and changes the offers", h.inv("water") == 0 and rerolled != first, {"water": h.inv("water"), "before": first, "after": rerolled})
	await h.shot("new_gadget_1_rerolled")
	Level.stage.rerollOffers("team1", "player1")
	await h.wait(0.5)
	h.check("no water, no reroll", GadgetShop.offers("team1", "player1") == rerolled)
	var picks: Array = []
	for tier in 4:
		if tier > 0:
			await _open(h)
		var offers: Array = GadgetShop.offers("team1", "player1")
		if offers.is_empty():
			h.check("New Gadget %d has offers" % (tier + 1), false)
			break
		var pick: String = offers[0]
		var m0: int = int(h.inv("money"))
		Level.stage.onGadgetSelected(pick, CONST.GADGET, "player1", "team1")
		await h.wait(2.0)
		picks.append(pick)
		h.check("New Gadget %d: picking %s pays $%d, installs it and marks the entry bought" % [tier + 1, GadgetShop._base(pick), prices[tier]],
			m0 - int(h.inv("money")) == prices[tier] and GameWorld.boughtUpgrades.has(pick) and GameWorld.boughtUpgrades.has(entries[tier]) and not _popup_open(),
			{"paid": m0 - int(h.inv("money")), "pick": pick})
	await h.shot("after_four_gadgets")
	h.check("all four entries bought", entries.all(func(e): return GameWorld.boughtUpgrades.has(e)))
	h.check("a fifth open does nothing", GadgetShop.next_entry("team1") == "")

	# ---- upgrades of the bought gadgets, the primary gadget and the dome apply.
	# Up to 3 per root, every root tried. Many cost water or cobalt as well as
	# money (vanilla's own extra costs), so stock up on all three.
	h.set_inv("money", 1000000)
	h.set_inv("water", 500)
	h.set_inv("sand", 500)
	var roots: Array = picks.map(func(p): return GadgetShop._base(p)) + [Level.loadout.domes[0].primaryGadgetId, "laser"]
	var tried: Array = []
	var per_root: Dictionary = {}
	for pass_i in 4:
		for id: String in GameWorld.upgrades.keys():
			var u: Dictionary = GameWorld.upgrades[id]
			if GameWorld.boughtUpgrades.has(id) or u.get("type", "") == "gadget" or u.get("propertychanges", []).is_empty():
				continue
			var base: String = GadgetShop._base(id)
			var root: String = ""
			for r: String in roots:
				if base.begins_with(r):
					root = r
			if root == "" or int(per_root.get(root, 0)) >= 3 or not GameWorld.isUpgradeAddable(id):
				continue
			per_root[root] = int(per_root.get(root, 0)) + 1
			tried.append(id)
			await _check_upgrade(h, id)
	h.note("upgrades per root", per_root)
	for r: String in roots:
		h.check("%s: at least one upgrade bought and applied" % r, int(per_root.get(r, 0)) > 0, per_root)
	h.note("upgrades tried", tried)
	h.snap("end", [])
