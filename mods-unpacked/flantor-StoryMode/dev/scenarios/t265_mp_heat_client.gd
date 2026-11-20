extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #265 online, client half: opens its own shop, where its keeper track holds
# its own Heat Shielding and Suit Blaster entries (none of the host's), buys
# Heat Shielding I and II and the Suit Blaster with its keys, and sees its
# keeper at tier II, the host's at 0. Then its keeper stands in lava and heats
# at tier II's rate. Pair: t265_mp_heat_host.

const TIMEOUT := 300
const LavaData = preload("res://mods-unpacked/flantor-StoryMode/data/lava.gd")
static var _LavaData = LavaData  # calls go through this: lazy_preload makes const-preload calls slow
const Host = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t265_mp_heat_host.gd")
static var _Host = Host  # calls go through this: lazy_preload makes const-preload calls slow


func boot() -> Dictionary:
	return {"netjoin": true}


func _panels(h) -> Array:
	return h.get_tree().root.find_children("*", "", true, false).filter(func(n): return n.get("techId") != null and str(n.get("techId")) != "" and n.is_visible_in_tree())


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var go = await shared(h, "go", 120.0)
	h.check("the host is ready", go is Dictionary)
	if not go is Dictionary:
		return
	var me = h.keeper()
	var hpid: String = go["host"]
	h.check("this keeper is the client's", me.playerId == go["client"], [me.playerId, go])
	var gw = GameWorld
	h.check("this player's own entries reached the client", gw.upgrades.has(me.playerId + ".storyheatshield1") and gw.upgrades.has(me.playerId + ".storysuitblaster") and gw.isUpgradeLimitAvailable(me.playerId + ".storykeeper"))
	await h.until(func(): return int(Data.ofOr("team1.inventory.money", 0)) > 0, 10.0)

	# ---- the client's own shop, its own buttons
	Level.stage.startUpgradesInput(me)
	await h.wait(1.5)
	var ids: Array = _panels(h).map(func(p): return str(p.techId))
	h.note("client's shop", ids.filter(func(i): return i.begins_with("player")))
	h.check("the shop shows this keeper's Heat Shielding, none of the host keeper's", ids.has(me.playerId + ".storyheatshield1") and not ids.any(func(i): return i.begins_with(hpid + ".")), ids.filter(func(i): return i.begins_with("player")))
	for raw in ["storyheatshield1", "storyheatshield2", "storysuitblaster"]:
		var id: String = me.playerId + "." + raw
		var panel = null
		for p in _panels(h):
			if p.techId == id:
				panel = p
		if panel == null:
			h.check("panel " + id, false)
			break
		InputSystem.grabFocus(panel)
		await h.wait(0.6)
		await h.press("ui_select")
		var ok: bool = await h.until(func(): return gw.boughtUpgrades.has(id), 8.0)
		h.check("bought " + raw + " in the shop", ok, gw.boughtUpgrades.filter(func(k): return k.begins_with(me.playerId + ".story")))
		await h.wait(0.6)
	await h.shot("client_shop")
	await h.press("ui_cancel")
	await h.wait(1.0)
	var blaster: bool = await h.until(func(): return gw.boughtUpgrades.has(me.playerId + ".suitblaster"), 10.0)
	await h.wait(1.0)
	var view := {"mine": _LavaData.shield_tier(me), "host's": _LavaData.shield_tier(hpid), "blasters": gw.boughtUpgrades.filter(func(k): return k.ends_with(".suitblaster"))}
	h.note("client view", view)
	h.check("this keeper is at tier II, the host's at 0", _LavaData.shield_tier(me) == 2 and _LavaData.shield_tier(hpid) == 0, view)
	h.check("this keeper got the Suit Blaster, the host's didn't", blaster and not gw.boughtUpgrades.has(hpid + ".suitblaster"), view)

	# ---- this keeper in lava, at tier II's rate
	var rooms = await shared(h, "rooms", 30.0)
	if not rooms is Dictionary:
		h.check("the host shared the rooms", false)
		return
	var lava = Level.map.get_node("StoryLavaField")
	var r: Array = room_of(rooms["client"])
	await h.until(func(): return lava.mass.get(Vector2i(r[0].x, r[1].y), 0.0) > 0.5, 10.0)
	var rate: float = await _Host.lava_rate(h, me, r, lava)
	var want: float = LavaData.HEAT_PER_SECOND * LavaData.HEAT_SHIELD_LAVA_MULT[2]
	h.check("this keeper (tier II) heats at %.0f/s in lava" % want, absf(rate - want) <= want * 0.15, rate)
	await h.shot("client_in_lava")
	var host_rate = await shared(h, "host rate", 30.0)
	h.note("rates", {"client": rate, "host": host_rate})
	h.check("the host's keeper heated faster (tier 0)", host_rate != null and float(host_rate) > rate * 2.0, [host_rate, rate])
