extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 51: the gadget shop. No gadget chambers; slot entries at the ladder
# price; a slot shows 3 fixed offers; reroll for 1 water; paid on pick; the
# Probe, Prospection Meter and Resource Packer never offered.

const GadgetShop = preload("res://mods-unpacked/cejdan-StoryMode/gamemode/gadget_shop.gd")
const MapConfig = preload("res://mods-unpacked/cejdan-StoryMode/data/map_config.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


func _popup_open() -> bool:
	var p = Level.stage.currentGadgetPopupByPlayerId.get("player1", null)
	return p != null and is_instance_valid(p) and p.is_inside_tree()


func _ids(arr: Array) -> Array:
	var out: Array = arr.map(func(x): return GadgetShop._base(x))
	out.sort()
	return out


func run(h) -> void:
	h.disable_waves()
	# ---- no gadget chambers, 20 seeds
	var chambers: int = 0
	for s in 20:
		var td = h.generate_map(MapConfig.make_archetype(), 2000 + s)
		if td != null:
			chambers += td.get_resource_cells_by_id(Data.TILE_GADGET).size()
			td.queue_free()
		await h.frames(1)
	h.check("20 seeds: zero gadget chamber tiles", chambers == 0, chambers)
	h.check("this run's map: zero gadget chamber tiles", Level.map.tileData.get_resource_cells_by_id(Data.TILE_GADGET).size() == 0)

	# ---- offer pools
	var pools: Dictionary = {}
	var removed_seen: Array = []
	for e: String in GadgetShop.ENTRIES:
		var slot: String = GadgetShop.ENTRIES[e]
		pools[slot] = _ids(GadgetShop.candidates(slot, "team1", "player1"))
		for r: String in GadgetShop.REMOVED:
			if pools[slot].has(r):
				removed_seen.append([slot, r])
	h.note("offer pools", pools)
	h.check("no pool offers the Probe, Prospection Meter, Resource Packer or Suit Blaster", removed_seen.is_empty(), removed_seen)

	# ---- entries at $50
	GadgetShop.refresh_entries("team1", "player1")
	var prices: Dictionary = {}
	for e: String in GadgetShop.ENTRIES:
		prices[e] = GameWorld.upgrades.get("team1." + e, {}).get("cost", {}).get("money", -1)
	h.check("a fresh run lists every slot entry at $50", prices.values().all(func(p): return p == 50), prices)
	h.set_inv("money", 1000)
	h.set_inv("water", 1)
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	for i in 14:
		await h.press("ui_down")
		await h.wait(0.2)
	await h.shot("shop_story_track")
	await h.press("ui_cancel")
	await h.wait(1.0)

	# ---- mineshaft: lift, drill, station extension; pick one for $50
	Level.stage.openStoryGadgetSlot("mineshaft", "team1", "player1")
	await h.wait(2.0)
	await h.shot("mineshaft_offers")
	var offers: Array = GadgetShop.offers("mineshaft", "team1", "player1")
	h.check("the mineshaft offers lift, mineshaft drill and station extension", _ids(offers) == ["drill", "lift", "stationextension"], _ids(offers))
	h.check("opening a slot charges nothing", h.inv("money") == 1000, h.inv("money"))
	var pick: String = offers[0]
	Level.stage.onGadgetSelected(pick, CONST.GADGET, "player1", "team1")
	await h.wait(2.0)
	h.check("picking charges $50 and installs it", h.inv("money") == 950 and GameWorld.boughtUpgrades.has(pick), {"money": h.inv("money"), "pick": pick})
	h.check("the popup closed", not _popup_open())
	GadgetShop.refresh_entries("team1", "player1")
	h.check("the next slot shows $400", GameWorld.upgrades.get("team1.storygadgetcellar", {}).get("cost", {}).get("money", -1) == 400, GameWorld.upgrades.get("team1.storygadgetcellar", {}).get("cost", {}))
	await h.shot("after_pick")

	# ---- cellar: reopening keeps the offers; cancel closes; reroll costs 1 water
	Level.stage.openStoryGadgetSlot("cellar", "team1", "player1")
	await h.wait(2.0)
	var first: Array = GadgetShop.offers("cellar", "team1", "player1").duplicate()
	await h.shot("cellar_offers")
	await h.press("ui_cancel")
	await h.wait(1.5)
	h.check("Cancel closes the slot without buying", not _popup_open() and h.inv("money") == 950, h.inv("money"))
	Level.stage.openStoryGadgetSlot("cellar", "team1", "player1")
	await h.wait(2.0)
	var again: Array = GadgetShop.offers("cellar", "team1", "player1")
	h.check("reopening shows the same 3 offers", again == first and first.size() == 3, [first, again])
	h.check("the offers are saved with the run (in Data)", str(Data.serialize()).find("story.gadgetoffers.cellar") >= 0)
	Level.stage.rerollOffers("team1", "player1")
	await h.wait(1.0)
	var rerolled: Array = GadgetShop.offers("cellar", "team1", "player1")
	h.check("a reroll costs 1 water and changes the offers", h.inv("water") == 0 and rerolled != first, {"water": h.inv("water"), "before": first, "after": rerolled})
	await h.shot("cellar_rerolled")
	Level.stage.rerollOffers("team1", "player1")
	await h.wait(0.5)
	h.check("no water, no reroll", GadgetShop.offers("cellar", "team1", "player1") == rerolled)
	await h.press("ui_cancel")
	await h.wait(1.0)

	# ---- two-slot gadgets: with dome back free and active taken
	var shock: Array = GadgetShop.candidates("domebackside", "team1", "player1")
	h.note("dome back pool before", _ids(shock))
	h.set_inv("money", 100000)
	# Take the active slot by buying the shockwave (dome surface + active) through the shop.
	Level.stage.openStoryGadgetSlot("domesurface", "team1", "player1")
	await h.wait(1.5)
	var surf: Array = GadgetShop.candidates("domesurface", "team1", "player1").filter(func(x): return GadgetShop._base(x) == "shockwave")
	if surf.size() > 0:
		Data.apply("team1.story.gadgetoffers.domesurface", surf[0])
		Level.stage.onGadgetSelected(surf[0], CONST.GADGET, "player1", "team1")
		await h.wait(2.0)
	h.check("shockwave installed (takes dome surface and active)", surf.size() > 0 and GameWorld.boughtUpgrades.has(surf[0]))
	var back: Array = _ids(GadgetShop.candidates("domebackside", "team1", "player1"))
	h.check("with active taken, dome back never offers rocket launcher or shockwave", not back.has("rocketlauncher") and not back.has("shockwave"), back)
	GadgetShop.refresh_entries("team1", "player1")
	h.check("the active slot entry left the shop", not GameWorld.upgrades.has("team1.storygadgetactive"))
	h.check("third gadget is priced $2,500", GadgetShop.price("team1") == 2500, GadgetShop.price("team1"))
	h.snap("end", [])
