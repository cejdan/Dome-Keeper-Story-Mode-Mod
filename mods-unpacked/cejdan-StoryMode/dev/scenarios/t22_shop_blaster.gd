extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 22: the Suit Blaster is sold in the Story Mode shop for $500. Buying
# it equips it and the keeper can blast (through metal). Run it with
# -Extra "--gadget=<id>" to check other loadouts.

const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	h.note("loadout", {"primary gadget": Level.loadout.domes[0].primaryGadgetId if Level.loadout.domes.size() > 0 else "?"})
	var entry: Dictionary = GameWorld.upgrades.get("team1.storysuitblaster", {})
	h.check("the shop has the Suit Blaster entry", not entry.is_empty(), GameWorld.upgrades.keys().filter(func(k): return "story" in k))
	h.check("it costs $500 and nothing else", entry.get("cost", {}) == {"money": 500}, entry.get("cost", {}))
	h.check("the run starts without the Suit Blaster", not GameWorld.boughtUpgrades.has("player1.suitblaster"))

	h.set_inv("money", 520)
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	await h.shot("techtree")
	# Walk down the tracks to the Story Mode one (the last track).
	for i in 12:
		await h.press("ui_down")
		await h.wait(0.25)
	await h.shot("techtree_story_track")
	await h.press("ui_cancel")
	await h.wait(1.0)

	var refused: bool = false
	h.set_inv("money", 499)
	refused = not (await h.buy("storysuitblaster"))
	h.check("refused with $499", refused and not GameWorld.boughtUpgrades.has("player1.suitblaster"), h.inv("money"))
	h.set_inv("money", 520)
	var ok: bool = await h.buy("storysuitblaster")
	await h.wait(1.0)
	h.check("bought for $500", ok and h.inv("money") == 20, h.inv("money"))
	h.check("buying it equips the Suit Blaster", GameWorld.boughtUpgrades.has("player1.suitblaster"))
	h.check("its upgrades are in the shop at iron x 14", GameWorld.upgrades.get("team1.suitblastermaxcharge", GameWorld.upgrades.get("player1.suitblastermaxcharge", {})).get("cost", {}).get("money", -1) == 28, GameWorld.upgrades.keys().filter(func(k): return "suitblaster" in k))

	# Blast through a metal plate under the keeper.
	var td = Level.map.tileData
	var c: Vector2i = Vector2i(0, 8)
	td.set_resourcev(c, Metal.TILE_ID)
	await h.dig_room(Vector2i(-3, 5), Vector2i(3, 7))
	await h.reveal([c])
	await h.teleport_tile(Vector2i(0, 7))
	await h.wait(2.0)
	await h.shot("equipped")
	await h.press("keeper_gadget1")
	await h.burst("blast", 10, 3)
	await h.wait(1.5)
	h.check("the keeper blasts: the metal plate under it is gone", Level.map.getTile(Vector2(c)) == null and td.get_resourcev(c) == Data.TILE_EMPTY, td.get_resourcev(c))
	await h.shot("after_blast")
	h.snap("end", [])
