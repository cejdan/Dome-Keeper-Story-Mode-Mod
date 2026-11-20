extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #265: Heat Shielding is per keeper, in splitscreen. Each keeper has its own
# entries in its own keeper track (vanilla's keeper tree: player2.drill1, so
# player2.storyheatshield1). Keeper 2 (the gamepad) opens its shop and buys
# tiers I and II with its own buttons; keeper 1 stays at 0, and keeper 1's
# shop shows its own tier I still to buy. Then both stand in lava, each heating
# at its own rate, and both go where the depth heat starts (B4): keeper 1
# heats there (and says so), keeper 2's suit keeps it cool.

const TIMEOUT := 420
const Split = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t231_split_restart.gd")
const LavaData = preload("res://mods-unpacked/flantor-StoryMode/data/lava.gd")

var k1
var k2
var lava
var gas


func boot() -> Dictionary:
	return {"loadout": true, "splitscreen": true}


# The open shop popup of player `pid`.
func _shop(h, pid: String):
	for n in h.get_tree().root.find_children("*", "", true, false):
		if is_instance_valid(n) and n.has_method("buyUpgrade") and n.has_method("updateCostLabels") and n.get("playerId") == pid and n.get("isIn") == true and n.find_child("TechTree") != null:
			return n
	return null


func _panels(shop) -> Array:
	var out: Array = []
	if shop == null:
		return out
	for track in shop.find_child("TechTree").get_node("Tracks").get_children():
		for p in track.techPanels.values():
			out.append(p)
	return out


func _panel(shop, id: String):
	for p in _panels(shop):
		if p.techId == id:
			return p
	return null


func _open_shop(h, k):
	Level.stage.startUpgradesInput(k)
	await h.until(func():
		var s = _shop(h, k.playerId)
		return s != null and s.animationDone, 5.0)
	await h.wait(0.5)
	return _shop(h, k.playerId)


func run(h) -> void:
	if not await Split.start_split(h):
		return
	k1 = Keepers.getLocalKeeperByDeviceId(0)
	k2 = Keepers.getLocalKeeperByDeviceId(1)
	h.check("keeper 2 is the gamepad's", k2 != null and k2.playerId == "player2" and k1.playerId == "player1", [k1.playerId, k2.playerId])
	lava = Level.map.get_node("StoryLavaField")
	gas = Level.map.get_node("StoryGasField")
	lava.magma.clear()
	gas.rock.clear()
	lava.freeze_flow = true
	gas.freeze_flow = true

	# ---- each keeper has its own entries, the way vanilla's keeper tree does
	var gw = GameWorld
	var own: Dictionary = {}
	for pid in ["player1", "player2"]:
		own[pid] = {"limit": gw.isUpgradeLimitAvailable(pid + ".storykeeper"), "mining": gw.isUpgradeLimitAvailable(pid + ".mining"),
			"entries": range(1, 5).map(func(n): return gw.upgrades.has("%s.storyheatshield%d" % [pid, n])), "blaster": gw.upgrades.has(pid + ".storysuitblaster"),
			"drill1": gw.upgrades.has(pid + ".drill1")}
	h.note("per player", own)
	h.check("each player has its own Heat Shielding I-IV and Suit Blaster entries", own.values().all(func(o): return o["limit"] and o["entries"] == [true, true, true, true] and o["blaster"]), own)
	h.check("the team has none", not gw.upgrades.has("team1.storyheatshield1") and not gw.upgrades.has("team1.storysuitblaster"))
	h.check("both start at tier 0", LavaData.shield_tier(k1) == 0 and LavaData.shield_tier(k2) == 0, [LavaData.shield_tier(k1), LavaData.shield_tier(k2)])

	# ---- keeper 2 buys tiers I and II in its own shop, with its gamepad
	h.set_inv("money", 5000)
	var shop2 = await _open_shop(h, k2)
	h.check("keeper 2's shop opened", shop2 != null)
	if shop2 == null:
		return
	var ids2: Array = _panels(shop2).map(func(p): return str(p.techId))
	var hs1 = _panel(shop2, "player2.storyheatshield1")
	h.note("keeper 2's shop", {"panels": ids2.size(), "player1 entries": ids2.filter(func(i): return i.begins_with("player1.")), "heat": ids2.filter(func(i): return "storyheat" in i)})
	h.check("keeper 2's shop shows its own Heat Shielding, none of keeper 1's", hs1 != null and not ids2.any(func(i): return i.begins_with("player1.")), ids2.filter(func(i): return i.begins_with("player")))
	h.check("Heat Shielding sits in keeper 2's keeper track", hs1 != null and hs1.track.rootTechId == "player2." + k2.techId, hs1.track.rootTechId if hs1 else null)
	for n in [1, 2]:
		var p = _panel(shop2, "player2.storyheatshield%d" % n)
		if p == null:
			h.check("tier %d panel in keeper 2's shop" % n, false)
			break
		InputSystem.grabFocus(p)
		await h.wait(0.6)
		if n == 1:
			await h.shot("k2_shop_heat_I")
		await h.pad_press(1, "ui_select")
		await h.wait(1.0)
	await h.shot("k2_shop_after_II")
	var bought: Dictionary = {}
	for pid in ["player1", "player2"]:
		bought[pid] = range(1, 5).filter(func(n): return gw.boughtUpgrades.has("%s.storyheatshield%d" % [pid, n]))
	h.note("bought", {"tiers": bought, "money": h.inv("money"), "data": [Data.ofOr("player1.suit.heatshield", null), Data.ofOr("player2.suit.heatshield", null), Data.ofOr("team1.suit.heatshield", null)]})
	h.check("keeper 2 bought I and II in its shop ($1,200)", bought["player2"] == [1, 2] and int(h.inv("money")) == 5000 - 1200, [bought["player2"], h.inv("money")])
	h.check("keeper 2's suit is at tier II, keeper 1's at 0", LavaData.shield_tier(k2) == 2 and LavaData.shield_tier(k1) == 0 and bought["player1"].is_empty(), [LavaData.shield_tier(k1), LavaData.shield_tier(k2)])
	var hs3 = _panel(shop2, "player2.storyheatshield3")
	h.check("keeper 2's shop offers tier III next", hs3 != null and gw.isUpgradeAddable("player2.storyheatshield3"))
	await h.pad_press(1, "ui_cancel")
	await h.wait(1.0)

	# ---- keeper 1's shop: its own tier I, still to buy
	var shop1 = await _open_shop(h, k1)
	var p1 = _panel(shop1, "player1.storyheatshield1")
	var ids1: Array = _panels(shop1).map(func(p): return str(p.techId))
	if p1 != null:
		InputSystem.grabFocus(p1)
		await h.wait(0.6)
	await h.shot("k1_shop_tier_0")
	h.check("keeper 1's shop shows its own tier I, unbought and buyable", p1 != null and not gw.boughtUpgrades.has("player1.storyheatshield1") and gw.isUpgradeAddable("player1.storyheatshield1"))
	h.check("keeper 1's shop shows none of keeper 2's", not ids1.any(func(i): return i.begins_with("player2.")), ids1.filter(func(i): return i.begins_with("player")))
	await h.press("ui_cancel")
	await h.wait(1.0)

	# ---- lava: each keeper heats at its own rate
	var r1 := _find_biome_row(1, 8)
	var r2 := _find_biome_row(1, r1.y + 6)
	for r: Vector2i in [r1, r2]:
		await h.dig_room(r + Vector2i(-2, -1), r + Vector2i(2, 1))
	_clear_drops()
	for r: Vector2i in [r1, r2]:
		for x in range(-2, 3):
			for y in [0, 1]:
				var c: Vector2i = r + Vector2i(x, y)
				lava.mass[c] = 1.0
				lava.shown[c] = 1.0
	await h.teleport_tile(r1, k1)
	await h.teleport_tile(r2, k2)
	for k in [k1, k2]:
		k.set("gravity_scale", 0.0)
		lava.set_heat_of(k, 0.0)
	lava.wake_all()
	await h.until(func(): return lava.keeper_in_lava(k1) and lava.keeper_in_lava(k2), 3.0)
	var t0: float = h.now()
	lava.set_heat_of(k1, 0.0)
	lava.set_heat_of(k2, 0.0)
	await h.wait(0.8)
	var dt: float = h.now() - t0
	var rate1: float = lava.heat_of(k1) / dt
	var rate2: float = lava.heat_of(k2) / dt
	var want1: float = LavaData.HEAT_PER_SECOND * LavaData.HEAT_SHIELD_LAVA_MULT[0]
	var want2: float = LavaData.HEAT_PER_SECOND * LavaData.HEAT_SHIELD_LAVA_MULT[2]
	h.note("lava heat per second", {"keeper 1": snappedf(rate1, 0.1), "keeper 2": snappedf(rate2, 0.1), "want": [want1, want2], "in lava": [lava.keeper_in_lava(k1), lava.keeper_in_lava(k2)]})
	h.snap_camera(k2)
	await h.shot("both_in_lava")
	h.check("keeper 1 (tier 0) heats at lava's full rate (%.0f/s)" % want1, absf(rate1 - want1) <= want1 * 0.15, rate1)
	h.check("keeper 2 (tier II) heats at its tier's rate (%.0f/s)" % want2, absf(rate2 - want2) <= want2 * 0.15, rate2)
	for k in [k1, k2]:
		lava.set_heat_of(k, 0.0)
	for c in lava.mass.keys():
		lava.mass.erase(c)
		lava.shown.erase(c)
	lava.wake_all()

	# ---- passive heat by suit tier, and the heat talk that goes with it
	var b: int = LavaData.PASSIVE_HEAT_START_BIOME
	h.check("keeper 1's suit feels biome %d, keeper 2's doesn't" % (b + 1), LavaData.passive_rate(b, k1) > 0.0 and LavaData.passive_rate(b, k2) == 0.0, [LavaData.passive_rate(b, k1), LavaData.passive_rate(b, k2)])
	var hot := _find_biome_row(b, 4)
	h.check("a room in biome %d" % (b + 1), Level.map.tileData.get_biomev(hot) == b, [hot, Level.map.tileData.get_biomev(hot)])
	await h.dig_room(hot + Vector2i(-4, -1), hot + Vector2i(4, 1))
	_clear_drops()
	await h.teleport_tile(hot + Vector2i(-2, 0), k1)
	await h.teleport_tile(hot + Vector2i(2, 0), k2)
	for k in [k1, k2]:
		k.set("gravity_scale", 0.0)
	for i in 3:
		if await h.read_beat("depth_beat%d" % i, 2.0, false) == "":
			break
	await h.wait(1.5)
	h.note("passive", {"keeper 1": lava.passive_rate_of(k1), "keeper 2": lava.passive_rate_of(k2), "heats": lava.heats})
	h.check("depth heat: keeper 1 heats, keeper 2 stays cool", lava.passive_rate_of(k1) > 0.0 and lava.passive_rate_of(k2) == 0.0, [lava.passive_rate_of(k1), lava.passive_rate_of(k2)])
	var talk = load("res://mods-unpacked/flantor-StoryMode/hud/heat_talk.gd").instance()
	var said: bool = await h.until(func(): return talk.shown.any(func(e): return e.get("player") == "player1"), 8.0)
	await h.shot("depth_heat")
	h.check("keeper 1 says its heat line", said, talk.shown)
	h.check("keeper 2 says none", not talk.shown.any(func(e): return e.get("player") == "player2"), talk.shown)
	h.note("final", {"heats": lava.heats, "talk": talk.shown})


func _clear_drops() -> void:
	for d in Level.drops.get_children():
		if "type" in d and "absorbed" in d:
			d.queue_free()


# The middle of a solid block of rock (9 x 5 tiles, a tile of wall around) in
# biome `biome`, at or below row `from_y` (t231_split_keeper2).
func _find_biome_row(biome: int, from_y: int) -> Vector2i:
	var td = Level.map.tileData
	for y in range(from_y, 400):
		for x in [-8, 8, -12, 12, -4, 4, -16, 16]:
			var ok := true
			for dy in range(-3, 4):
				for dx in range(-5, 6):
					var c := Vector2i(x + dx, y + dy)
					if td.get_biomev(c) != biome or Level.map.is_tile_empty(c) or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE or lava.magma.has(c) or lava.mass.has(c) or gas.rock.has(c) or gas.mass.has(c):
						ok = false
						break
				if not ok:
					break
			if ok:
				return Vector2i(x, y)
	return Vector2i(-6, from_y)
