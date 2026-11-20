extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #231: the second keeper's laser in splitscreen. With two keepers the dome has
# a secondary station, whose laser vanilla sells in the shop (Second Weapon,
# behind Sand Repair). Story Mode keeps that (the free laser of the first #231
# pass is gone): the team has no second laser until it buys one, the shop
# offers it, and the team buys it (money, sand and water set by the harness;
# the map must hold sand and water to mine). Keeper 2 (the gamepad) takes the
# secondary station with its own buttons and fires: its laser moves and fires
# while keeper 1's stays idle; then both fire at once.

const TIMEOUT := 360
const Split = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t231_split_restart.gd")


func boot() -> Dictionary:
	return {"loadout": true, "splitscreen": true}


func run(h) -> void:
	if not await Split.start_split(h):
		return
	var k2 = Keepers.getLocalKeeperByDeviceId(1)
	var dome = Level.getDome("team1")
	var gw = GameWorld
	var id := "team1.domesecondweapon"
	h.note("secondary station", {
		"data secondarystation": Data.ofOr("team1.dome.secondarystation", null),
		"data secondaryweapon": Data.ofOr("team1.dome.secondaryweapon", null),
		"stations": dome.stations.size(),
		"station 1 visible": dome.stations[1].visible if dome.stations.size() > 1 else null,
		"limits": {"hostile": gw.isUpgradeLimitAvailable("team1.hostile"), "multiplekeepers": gw.isUpgradeLimitAvailable("team1.multiplekeepers")},
		"upgrade": gw.upgrades.get(id, {}).get("cost", null),
		"available": gw.availableUpgrades.has(id) if "availableUpgrades" in gw else null,
	})
	h.check("the dome has a secondary station", dome.stations.size() > 1 and dome.stations[1].visible)
	h.note("lasers before the second weapon", [dome.stations[0].getControlledWeapons().size(), dome.stations[1].getControlledWeapons().size()])
	h.check("no free second laser: vanilla's Second Weapon is still to buy", not gw.boughtUpgrades.has(id) and dome.stations[1].getControlledWeapons().is_empty() and not Data.ofOr("team1.dome.secondaryweapon", false),
		{"bought": gw.boughtUpgrades.has(id), "station 2 lasers": dome.stations[1].getControlledWeapons().size()})
	# Sand (cobalt) and water to mine for it.
	var sand_tiles: int = Level.map.tileData.get_resource_cells_by_id(Data.TILE_SAND).size()
	var water_tiles: int = Level.map.tileData.get_resource_cells_by_id(Data.TILE_WATER).size()
	h.check("the map holds sand and water to mine", sand_tiles > 0 and water_tiles > 0, {"sand tiles": sand_tiles, "water tiles": water_tiles})
	# The way to the second weapon in the shop: its predecessor, then it.
	h.set_inv("money", 5000)
	h.set_inv("sand", 3)
	h.set_inv("water", 30)
	# Keeper 2's shop (in its own view) lists it.
	Level.stage.startUpgradesInput(k2)
	await h.wait(2.0)
	var panels: Array = h.get_tree().root.find_children("*", "", true, false).filter(func(n): return n.get("techId") != null and str(n.get("techId")) != "")
	var ids: Array = panels.map(func(n): return str(n.techId))
	h.note("keeper 2's shop", {"panels": ids.size(), "dome track": ids.filter(func(i): return i.begins_with("team1.dome"))})
	h.note("keeper 2's shop dome track", ids.filter(func(i): return i.begins_with("team1.dome")))
	await h.shot("k2_shop")
	await h.pad_press(1, "ui_cancel")
	await h.wait(1.0)
	await h.pad_press(1, "ui_cancel")
	await h.wait(1.0)
	# The shop's way to it: the Health Meter, then Sand Repair (a repeatable
	# predecessor: it counts while it can be bought), then Second Weapon.
	var chain: Dictionary = {}
	h.check("the Health Meter is in the shop", gw.isUpgradeAddable("team1.domehealthmeter") or gw.boughtUpgrades.has("team1.domehealthmeter"))
	if not gw.boughtUpgrades.has("team1.domehealthmeter"):
		gw.buyUpgrade("team1.domehealthmeter", "team1", k2.playerId)
		await h.wait(0.5)
	for u in ["team1.domehealthmeter", "team1.domesandrepair", id]:
		chain[u] = {"bought": gw.boughtUpgrades.has(u), "addable": gw.isUpgradeAddable(u), "cost": gw.upgrades.get(u, {}).get("cost", null)}
	h.note("the way to the second weapon", chain)
	h.check("Sand Repair and Second Weapon are in the shop", gw.isUpgradeAddable("team1.domesandrepair") and gw.isUpgradeAddable(id), chain)
	h.check("the team can afford Second Weapon", gw.canAfford(gw.upgrades.get(id, {}).get("cost", {}), "team1"), gw.upgrades.get(id, {}).get("cost", null))
	gw.buyUpgrade(id, "team1", k2.playerId)
	await h.wait(1.0)
	h.check("Second Weapon bought: the secondary station has its laser", gw.boughtUpgrades.has(id) and Data.ofOr("team1.dome.secondaryweapon", false), {"bought": gw.boughtUpgrades.has(id), "money": Data.of("team1.inventory.money"), "water": Data.of("team1.inventory.water")})
	await h.wait(1.0)
	var w1: Array = dome.stations[0].getControlledWeapons()
	var w2: Array = dome.stations[1].getControlledWeapons()
	h.check("the secondary station has a laser", w2.size() >= 1, [w1.size(), w2.size()])
	# Keeper 2 walks into the secondary station and uses it with its gamepad.
	k2.teleport(dome.stations[1].global_position)
	await h.wait(1.0)
	await h.pad_press(1, "keeper_use" if InputMap.has_action("keeper_use") else "ui_select")
	await h.wait(0.8)
	h.note("station", {"keeper in station 1": str(dome.stations[1].keeperInStation), "focus": str(k2.focussedUsable)})
	if dome.stations[1].keeperInStation != k2:
		var used: bool = k2.useHit()
		h.note("useHit", used)
		await h.wait(0.8)
	h.check("keeper 2 is in the secondary station", dome.stations[1].keeperInStation == k2, str(dome.stations[1].keeperInStation))
	await h.shot("k2_station_popup")
	await h.pad_press(1, "dome_battle")
	await h.wait(0.8)
	h.check("keeper 2's laser started", w2.size() >= 1 and w2[0].started, [w2[0].started if w2.size() > 0 else null])
	var probe0: float = w2[0].pathProbe.progress_ratio if w2.size() > 0 else 0.0
	await h.pad_stick(1, Vector2(1, 0), 1.0)
	h.pad(1, "dome1_fire", true)
	await h.wait(0.8)
	await h.shot("k2_firing")
	h.note("weapons", {"w2": w2.map(func(w): return {"started": w.started, "ratio": w.pathProbe.progress_ratio}), "w1": w1.map(func(w): return {"started": w.started})})
	h.check("keeper 2's laser moves", w2.size() > 0 and absf(w2[0].pathProbe.progress_ratio - probe0) > 0.01, [probe0, w2[0].pathProbe.progress_ratio if w2.size() > 0 else null])
	h.pad(1, "dome1_fire", false)
	h.check("keeper 1's laser is idle", w1.size() > 0 and not w1[0].started, w1.map(func(w): return w.started))

	# Both at once: keeper 1 takes the main station with the keyboard.
	var k1 = Keepers.getLocalKeeperByDeviceId(0)
	k1.teleport(dome.stations[0].global_position)
	await h.wait(1.0)
	await h.press("ui_select")
	await h.wait(0.8)
	if dome.stations[0].keeperInStation != k1:
		k1.useHit()
		await h.wait(0.8)
	h.check("keeper 1 is in the main station", dome.stations[0].keeperInStation == k1, str(dome.stations[0].keeperInStation))
	await h.press("dome_battle")
	await h.wait(0.8)
	h.check("keeper 1's laser started, keeper 2's still on", w1[0].started and w2[0].started, [w1[0].started, w2[0].started])
	h.check("the game runs (not paused by a station)", not GameWorld.paused, GameWorld.paused)
	var r1: float = w1[0].pathProbe.progress_ratio
	var r2: float = w2[0].pathProbe.progress_ratio
	h.down("ui_left")
	h.pad(1, "dome1_fire", true)
	var stick := InputEventJoypadMotion.new()
	stick.device = 0
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = -1.0
	Input.parse_input_event(stick)
	await h.wait(1.0)
	await h.shot("both_firing")
	h.up("ui_left")
	stick = stick.duplicate()
	stick.axis_value = 0.0
	Input.parse_input_event(stick)
	h.pad(1, "dome1_fire", false)
	h.note("both", {"w1": [r1, w1[0].pathProbe.progress_ratio], "w2": [r2, w2[0].pathProbe.progress_ratio]})
	h.check("both lasers move at once", absf(w1[0].pathProbe.progress_ratio - r1) > 0.01 and absf(w2[0].pathProbe.progress_ratio - r2) > 0.01, [r1, w1[0].pathProbe.progress_ratio, r2, w2[0].pathProbe.progress_ratio])
