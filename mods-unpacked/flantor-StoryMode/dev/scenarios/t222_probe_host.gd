extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #222 gap probe, host half: opens the welcome log (does the client see it?),
# then gives the team money for the client's shop and gadget-shop tries, and
# reports what the host saw. Pair: t222_probe_client.

const TIMEOUT := 420
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
const GadgetShop = preload("res://mods-unpacked/flantor-StoryMode/gamemode/gadget_shop.gd")


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true, "beats": true, "welcome": true}


func run(h) -> void:
	if not await host_start(h):
		return
	var opened: bool = await h.until(func(): return StoryBeats.is_open(), 15.0)
	h.check("welcome log open on the host", opened)
	share("beat_open", true)
	await h.wait(5.0)
	await h.shot("host_beat")
	h.note("host paused during beat", GameWorld.paused)
	if opened:
		await h.read_beat("welcome", 10.0, false)
	Data.apply("team1.inventory.money", 100000)
	Data.apply("team1.inventory.water", 5)
	var is_gadget := func(k): return GameWorld.upgrades.get(k, {}).get("type", "") == "gadget"
	var gadgets0: Array = GameWorld.boughtUpgrades.filter(is_gadget)
	share("go", true)
	# The client buys Heat Shielding I, then uses the gadget shop: open, Cancel,
	# reopen, one reroll, a pick (New Gadget I) and a second pick (New Gadget II).
	var entries: Array = GadgetShop.entries("team1")
	var cost := func(id: String) -> int: return int(GameWorld.upgrades.get(id, {}).get("cost", {}).get("money", -1))
	var spent: int = cost.call(Keepers.first().playerId + ".storyheatshield1") + cost.call(entries[0]) + cost.call(entries[1])
	var both: bool = await h.until(func(): return GameWorld.boughtUpgrades.has(entries[0]) and GameWorld.boughtUpgrades.has(entries[1]), 90.0)
	await h.wait(3.0)
	var gadgets: Array = GameWorld.boughtUpgrades.filter(func(k): return is_gadget.call(k) and not gadgets0.has(k))
	var money: int = int(Data.ofOr("team1.inventory.money", -1))
	var water: int = int(Data.ofOr("team1.inventory.water", -1))
	h.note("host view after client tries", {"money": money, "water": water, "entries bought": both, "new gadgets": gadgets, "heatshield1": GameWorld.boughtUpgrades.filter(func(k): return k.ends_with(".storyheatshield1"))})
	h.check("host: New Gadget I and II are bought, III is not", both and not GameWorld.boughtUpgrades.has(entries[2]))
	h.check("host: the client paid Heat Shielding I + New Gadget I + II, nothing else", 100000 - money == spent, {"spent": 100000 - money, "expected": spent})
	h.check("host: the reroll cost 1 water", water == 4, water)
	h.check("host: exactly two gadgets were added", gadgets.size() == 2, gadgets)
	h.check("host: the shop choice is closed and the offers are cleared", Level.stage.story_shop.is_empty() and str(Data.ofOr("team1.story.gadgetoffers", "")) == "" and str(Level.stage.currentOfferTypeByPlayerId.get("player2", "")) == "", {"shop": Level.stage.story_shop, "offers": Data.ofOr("team1.story.gadgetoffers", ""), "type": Level.stage.currentOfferTypeByPlayerId})
	await h.shot("host_after_client_shop")
	await host_wait_clients_left(h)
