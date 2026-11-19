extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #297 online, client half: this player is keeper4, the host the Assessor. Its
# own shop shows keeper4's tree in money with its own Heat Shielding and Suit
# Blaster (none of the host's); it buys Heat Shielding I and the Suit Blaster
# with its keys, then blasts the gate cell the host dug out.
# Pair: t297_mp_host.

const TIMEOUT := 300
const LavaData = preload("res://mods-unpacked/cejdan-StoryMode/data/lava.gd")
const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")
const K = preload("res://mods-unpacked/cejdan-StoryMode/dev/scenarios/t297_keeper2.gd")


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var go = await shared(h, "go", 150.0)
	h.check("the host is ready", go is Dictionary)
	if not go is Dictionary:
		return
	var me = h.keeper()
	var gw = GameWorld
	h.check("this keeper is the client's keeper4", me.playerId == go["client"] and me.techId == "keeper4", [me.playerId, me.techId, go])
	await h.until(func(): return int(Data.ofOr("team1.inventory.money", 0)) > 0, 10.0)

	# ---- its own shop, its own buttons
	var shop = await K.open_shop(h, me)
	h.check("the client's shop opens", shop != null)
	if shop == null:
		return
	K.check_keeper_shop(h, me, shop, "client: ")
	for raw in ["storyheatshield1", "storysuitblaster"]:
		var id: String = me.playerId + "." + raw
		if not await K.focus(h, shop, id):
			h.check("panel " + id, false)
			break
		await h.press("ui_select")
		var ok: bool = await h.until(func(): return gw.boughtUpgrades.has(id), 8.0)
		h.check("bought " + raw + " in the shop", ok, gw.boughtUpgrades.filter(func(k): return k.begins_with(me.playerId + ".story")))
		await h.wait(0.6)
	await h.shot("client_shop")
	await h.press("ui_cancel")
	await h.wait(1.0)
	var blaster: bool = await h.until(func(): return gw.boughtUpgrades.has(me.playerId + ".suitblaster"), 10.0)
	h.check("this keeper is at tier I and has the Suit Blaster", LavaData.shield_tier(me) == 1 and blaster, [LavaData.shield_tier(me), blaster])

	# ---- the gate
	var g = go.get("gate")
	if g == null:
		return
	var gate := Vector2i(int(g[0]), int(g[1]))
	var td = Level.map.tileData
	await h.teleport_tile(gate + Vector2i(0, -1))
	await h.until(func(): return float(Data.ofOr(me.playerId + ".suitblaster.charge", 0.0)) >= 1.0, 20.0)
	await h.wait(1.5)
	await h.shot("client_on_gate")
	await h.press("keeper_gadget1")
	await h.burst("client_blast", 8, 3)
	var broke: bool = await h.until(func(): return td.get_resourcev(gate) != Metal.GATE_ID, 40.0)
	h.check("this keeper4's Suit Blaster breaks the gate tile here", broke, {"tile": td.get_resourcev(gate), "keeper": h.keeper_tile(), "gate": gate})
	await shared(h, "gate_broken", 30.0)
	await h.shot("client_gate_broken")
