extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #265 (2/2): loads t265_old_save's save (a run from before #265, slot 26) in a
# fresh process. The keeper gets the team's tier (III) as its own, the team's
# entries leave the shop, the keeper's own track offers tier IV next, and its
# own Suit Blaster entry counts as bought (it has the blaster). Lava heats it
# at tier III's rate. Saved and loaded again it stays the same (slot 27 is
# written for a look; the second load is t265_old_load with `--reload`).

const LavaData = preload("res://mods-unpacked/flantor-StoryMode/data/lava.gd")
static var _LavaData = LavaData  # calls go through this: lazy_preload makes const-preload calls slow
const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow


func boot() -> Dictionary:
	return {"load": 27 if _Story.has_user_arg("reload") else 26}


func run(h) -> void:
	await h.until(func(): return not SaveGame.currentLoadingSavegame, 20.0)
	h.check("a Story Mode run came back from the save", Level.loadout != null and Level.loadout.modeId == "storymode")
	h.disable_waves()
	await h.wait(1.0)
	var k = h.keeper()
	var pid: String = k.playerId
	var gw = GameWorld
	var view := {
		"limit": gw.isUpgradeLimitAvailable(pid + ".storykeeper"),
		"bought": gw.boughtUpgrades.filter(func(x): return "storyheat" in x or "suitblaster" in x),
		"team entries": gw.upgrades.keys().filter(func(x): return x.begins_with("team1.story") and ("heat" in x or "suit" in x)),
		"tier": _LavaData.shield_tier(k), "data": [Data.ofOr(pid + ".suit.heatshield", null), Data.ofOr("team1.suit.heatshield", null)],
		"money": Data.ofOr("team1.inventory.money", -1),
	}
	h.note("loaded", view)
	h.check("the money came back (the save is the one made)", int(view["money"]) == 1234, view["money"])
	h.check("the keeper has its own limit", view["limit"])
	h.check("the keeper has the team's tier III as its own", _LavaData.shield_tier(k) == 3 and range(1, 4).all(func(n): return gw.boughtUpgrades.has("%s.storyheatshield%d" % [pid, n])) and not gw.boughtUpgrades.has(pid + ".storyheatshield4"), view)
	h.check("the team's entries are gone from the shop", view["team entries"].is_empty() and not view["bought"].any(func(x): return x.begins_with("team1.")), view)
	h.check("tier IV is offered next in the keeper's own track", gw.upgrades.has(pid + ".storyheatshield4") and gw.isUpgradeAddable(pid + ".storyheatshield4"))
	h.check("the keeper still has its Suit Blaster, and its own entry counts as bought", gw.boughtUpgrades.has(pid + ".suitblaster") and gw.boughtUpgrades.has(pid + ".storysuitblaster"), view["bought"])
	# The shop: the keeper track with I-III bought.
	Level.stage.startUpgradesInput(k)
	await h.wait(1.5)
	for n in h.get_tree().root.find_children("*", "", true, false):
		if n.get("techId") == pid + ".storyheatshield4":
			InputSystem.grabFocus(n)
	await h.wait(0.8)
	await h.shot("shop_after_load")
	await h.press("ui_cancel")
	await h.wait(1.0)
	# Lava at tier III's rate.
	var lava = Level.map.get_node("StoryLavaField")
	lava.magma.clear()
	lava.freeze_flow = true
	var c := Vector2i(6, 14)
	await h.dig_room(c + Vector2i(-1, -1), c + Vector2i(1, 1))
	for y in range(-1, 2):
		for x in range(-1, 2):
			lava.mass[c + Vector2i(x, y)] = 1.0
	lava.wake_all()
	await h.teleport_tile(c)
	await h.until(func(): return lava.keeper_in_lava(k), 3.0)
	lava.set_heat_of(k, 0.0)
	var t0: float = h.now()
	await h.wait(1.0)
	var rate: float = lava.heat_of(k) / (h.now() - t0)
	var want: float = LavaData.HEAT_PER_SECOND * LavaData.HEAT_SHIELD_LAVA_MULT[3]
	h.check("lava heats it at tier III's rate (%.0f/s)" % want, absf(rate - want) <= want * 0.15, rate)
	lava.set_heat_of(k, 0.0)
	for cc in lava.mass.keys():
		lava.mass.erase(cc)
	if not _Story.has_user_arg("reload"):
		# Saved again (now a #265 save): it must load the same (`--reload`).
		await h.teleport_tile(Vector2i(0, 3))
		await h.wait(0.5)
		SaveGame.saveGame("singleplayer", 27, true)
		await h.wait(1.0)
		h.check("saved again as slot 27", FileAccess.file_exists("user://singleplayer/savegame_27.json"))
