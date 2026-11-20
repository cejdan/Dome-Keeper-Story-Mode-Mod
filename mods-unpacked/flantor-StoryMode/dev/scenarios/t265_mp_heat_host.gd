extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #265 online, host half: Heat Shielding and the Suit Blaster are per keeper.
# The client buys Heat Shielding I and II and its Suit Blaster in its own shop
# (t265_mp_heat_client); the host buys nothing. The host sees the client's
# keeper at tier II with a Suit Blaster, its own keeper at 0 without one, and
# the team paid once for each. Then each player stands its keeper in lava: the
# host's heats at lava's full rate here, the client's at tier II's there.
# Pair: t265_mp_heat_client.

const TIMEOUT := 300
const LavaData = preload("res://mods-unpacked/flantor-StoryMode/data/lava.gd")
const MONEY := 5000


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if not await host_start(h):
		return
	var me = h.keeper()
	var ck = null
	for k in Keepers.getAll():
		if is_instance_valid(k) and k.playerId != me.playerId:
			ck = k
	h.check("a client keeper", ck != null)
	if ck == null:
		return
	var gw = GameWorld
	h.check("each player has its own limit and entries", [me.playerId, ck.playerId].all(func(p): return gw.isUpgradeLimitAvailable(p + ".storykeeper") and gw.upgrades.has(p + ".storyheatshield1") and gw.upgrades.has(p + ".storysuitblaster")),
		gw.upgrades.keys().filter(func(k): return "storyheat" in k or "storysuit" in k))
	Data.apply("team1.inventory.money", MONEY)
	# Two sealed rooms with lava on the floor: one for each player's keeper.
	var rooms: Array = find_rooms(2)
	h.check("found two sealed rooms", rooms.size() == 2, rooms)
	if rooms.size() < 2:
		return
	var lava = Level.map.get_node("StoryLavaField")
	lava.freeze_flow = true
	for r in rooms:
		await h.dig_room(r[0], r[1])
		for x in range(r[0].x, r[1].x + 1):
			for y in [r[1].y - 1, r[1].y]:
				lava.mass[Vector2i(x, y)] = 1.0
				lava._wake(Vector2i(x, y))
	lava.wake_all()
	share("rooms", {"host": room_arr(rooms[0]), "client": room_arr(rooms[1])})
	share("go", {"host": me.playerId, "client": ck.playerId})

	# ---- the client buys in its own shop
	var cpid: String = ck.playerId
	var done: bool = await h.until(func(): return gw.boughtUpgrades.has(cpid + ".storyheatshield2") and gw.boughtUpgrades.has(cpid + ".suitblaster"), 90.0)
	await h.wait(1.0)
	var view := {
		"client tier": int(Data.ofOr(cpid + ".suit.heatshield", 0)), "host tier": int(Data.ofOr(me.playerId + ".suit.heatshield", 0)),
		"bought": gw.boughtUpgrades.filter(func(k): return "storyheat" in k or "suitblaster" in k), "money": int(Data.ofOr("team1.inventory.money", -1)),
	}
	h.note("host view after the client's purchases", view)
	h.check("the client bought Heat Shielding II and the Suit Blaster", done, view)
	h.check("the client's keeper is at tier II, the host's at 0", LavaData.shield_tier(ck) == 2 and LavaData.shield_tier(me) == 0, view)
	h.check("the host's keeper has no entry bought", not gw.boughtUpgrades.any(func(k): return k.begins_with(me.playerId + ".story")), view["bought"])
	h.check("the Suit Blaster went to the client's keeper only", gw.boughtUpgrades.has(cpid + ".suitblaster") and not gw.boughtUpgrades.has(me.playerId + ".suitblaster"), view["bought"])
	h.check("the team paid $200 + $1,000 + $200 once", view["money"] == MONEY - 1400, view["money"])
	# The host's own shop: its tier I, still to buy.
	Level.stage.startUpgradesInput(me)
	await h.wait(1.5)
	var panel = null
	var ids: Array = []
	for n in h.get_tree().root.find_children("*", "", true, false):
		if n.get("techId") != null and str(n.get("techId")) != "":
			ids.append(str(n.techId))
			if n.techId == me.playerId + ".storyheatshield1":
				panel = n
	if panel != null:
		InputSystem.grabFocus(panel)
		await h.wait(0.6)
	await h.shot("host_shop")
	h.check("the host's shop shows its own tier I, unbought", panel != null and gw.isUpgradeAddable(me.playerId + ".storyheatshield1"))
	h.check("the host's shop shows none of the client's entries", not ids.any(func(i): return i.begins_with(cpid + ".")), ids.filter(func(i): return i.begins_with("player")))
	await h.press("ui_cancel")
	await h.wait(1.0)

	# ---- the host's keeper in lava, at lava's full rate
	var rate: float = await lava_rate(h, me, room_of(room_arr(rooms[0])), lava)
	var want: float = LavaData.HEAT_PER_SECOND * LavaData.HEAT_SHIELD_LAVA_MULT[0]
	h.check("the host's keeper (tier 0) heats at %.0f/s in lava" % want, absf(rate - want) <= want * 0.15, rate)
	await h.shot("host_in_lava")
	share("host rate", rate)
	await host_wait_clients_left(h, 120.0)


# Stands keeper `k` in the lava on room `r`'s floor and returns its heat per second.
static func lava_rate(h, k, r: Array, lava) -> float:
	var c := Vector2i((r[0].x + r[1].x) / 2, r[1].y)
	await h.teleport_tile(c, k)
	k.set("gravity_scale", 0.0)
	await h.until(func(): return lava.keeper_in_lava(k), 5.0)
	await h.wait(0.3)
	lava.set_heat_of(k, 0.0)
	var t0: float = h.now()
	await h.wait(0.8)
	var rate: float = lava.heat_of(k) / (h.now() - t0)
	h.note("lava rate of " + k.playerId, {"rate": snappedf(rate, 0.1), "in lava": lava.keeper_in_lava(k), "tier": LavaData.shield_tier(k)})
	lava.set_heat_of(k, 0.0)
	k.set("gravity_scale", 1.0)
	return rate
