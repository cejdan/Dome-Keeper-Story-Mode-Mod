extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #297 online, host half: mixed keepers in Story Mode co-op. The host plays the
# Assessor (keeper2), the client keeper4. Each player's Heat Shielding and Suit
# Blaster entries hang off that player's own keeper (player1.keeper2,
# player2.keeper4) and sit in that player's keeper track. The host's shop shows
# its tree in money with its entries (t297_keeper2's checks). The client buys
# Heat Shielding I and its Suit Blaster in its own shop and blasts a gate
# (t297_mp_client); the host sees the client's keeper at tier I with a Suit
# Blaster, its own at 0 without one, the team paid once for each, and the gate
# tile broken. Pair: t297_mp_client.

const TIMEOUT := 300
const LavaData = preload("res://mods-unpacked/flantor-StoryMode/data/lava.gd")
const Metal = preload("res://mods-unpacked/flantor-StoryMode/data/metal.gd")
const K = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t297_keeper2.gd")
const KEEPERS := ["keeper2", "keeper4"]
const MONEY := 5000


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


# As t234_mp_e2e_host's.
func _clear_of_hazards(c: Vector2i, r: int) -> bool:
	var lava = Level.map.get_node("StoryLavaField")
	var gas = Level.map.get_node("StoryGasField")
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var t := c + Vector2i(dx, dy)
			if lava.magma.has(t) or lava.mass.has(t) or gas.rock.has(t) or gas.mass.has(t):
				return false
	return true


func run(h) -> void:
	if not await host_start(h, 2, "storymode", "", KEEPERS):
		return
	var me = h.keeper()
	var ck = null
	for k in Keepers.getAll():
		if is_instance_valid(k) and k.playerId != me.playerId:
			ck = k
	h.check("a client keeper", ck != null)
	if ck == null:
		return
	h.check("the host plays keeper2, the client keeper4", me.techId == "keeper2" and ck.techId == "keeper4", [me.techId, ck.techId])
	var gw = GameWorld
	for k in [me, ck]:
		var preds: Array = []
		for raw in K.STORY_ENTRIES:
			preds.append(gw.upgrades.get(k.playerId + "." + raw, {}).get("predecessors", []))
		h.check("%s's Story entries hang off its own %s" % [k.playerId, k.techId], preds.all(func(p): return p == [k.playerId + "." + k.techId]), preds)
	Data.apply("team1.inventory.money", MONEY)
	await h.wait(0.5)

	# ---- the host's own shop
	var shop = await K.open_shop(h, me)
	h.check("the host's shop opens", shop != null)
	if shop != null:
		K.check_keeper_shop(h, me, shop, "host: ")
		await K.focus(h, shop, me.playerId + ".storyheatshield1")
		await h.shot("host_shop")
		await h.press("ui_cancel")
		await h.wait(1.0)

	# ---- a gate cell for the client to blast
	var td = Level.map.tileData
	var gate = null
	var gcells: Array = td.get_resource_cells_by_id(Metal.GATE_ID)
	gcells.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and absi(a.x) < absi(b.x)))
	for c0 in gcells:
		var c := Vector2i(c0)
		# No metal in the room dug above it: the host's dev clear of a metal tile
		# doesn't reach the client, whose keeper then stands on phantom metal.
		var room_metal := false
		for dy in range(-3, 0):
			for dx in range(-1, 2):
				if Metal.is_metal_id(td.get_resourcev(c + Vector2i(dx, dy))):
					room_metal = true
		if absi(c.x) > 2 and not room_metal and _clear_of_hazards(c, 4):
			gate = c
			break
	h.check("a gate cell clear of lava and gas", gate != null, gcells.size())
	if gate != null:
		await h.dig_room(gate + Vector2i(-1, -3), gate + Vector2i(1, -1))
		await h.reveal([gate])
	share("go", {"host": me.playerId, "client": ck.playerId, "gate": [gate.x, gate.y] if gate != null else null})

	# ---- the client buys in its own shop
	var cpid: String = ck.playerId
	var done: bool = await h.until(func(): return gw.boughtUpgrades.has(cpid + ".storyheatshield1") and gw.boughtUpgrades.has(cpid + ".suitblaster"), 90.0)
	await h.wait(1.0)
	var view := {
		"client tier": LavaData.shield_tier(ck), "host tier": LavaData.shield_tier(me),
		"bought": gw.boughtUpgrades.filter(func(k): return "storyheat" in k or "suitblaster" in k),
		"money": int(Data.ofOr("team1.inventory.money", -1)),
	}
	h.note("host view after the client's purchases", view)
	h.check("the client bought Heat Shielding I and the Suit Blaster", done, view)
	h.check("the client's keeper4 is at tier I, the host's keeper2 at 0", view["client tier"] == 1 and view["host tier"] == 0, view)
	h.check("the Suit Blaster went to the client's keeper only", gw.boughtUpgrades.has(cpid + ".suitblaster") and not gw.boughtUpgrades.has(me.playerId + ".suitblaster"), view["bought"])
	var paid: int = K.story_price("storyheatshield1") + K.story_price("storysuitblaster")
	h.check("the team paid $%d once" % paid, view["money"] == MONEY - paid, view["money"])

	# ---- the client's blast
	if gate != null:
		var broke: bool = await h.until(func(): return td.get_resourcev(gate) != Metal.GATE_ID, 60.0)
		h.check("the client's keeper4 blasts the gate tile (host map)", broke, td.get_resourcev(gate))
		share("gate_broken", broke)
		await h.teleport_tile(gate + Vector2i(0, -1), me)
		await h.wait(1.5)
		await h.shot("host_gate")
	await host_wait_clients_left(h, 120.0)
