extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #228: client half. Its gas is the host's: the same sealed caverns from the
# start, the same cloud as a breached pocket empties into a room, the same
# cells once it settles; the pocket's gas rock bursts here too. Its keeper
# fills its own toxin bar in the cloud and is recalled, and the team's $1000
# halves on the host. Fire the host lights burns here; gas the host puts in
# the dome hazes this dome, fills the bar, and this player's Vent the Dome
# clears it for everyone. Pair: t228_mp_gas_host.

const GasData = preload("res://mods-unpacked/flantor-StoryMode/data/gas.gd")
const TIMEOUT := 480


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var home: Vector2 = h.keeper().global_position
	var room = await shared(h, "room", 90.0)
	h.check("host dug a room", room != null, room)
	if room == null:
		return
	await h.until(func(): return Level.map.has_node("StoryGasField"), 20.0)
	var field = Level.map.get_node("StoryGasField")
	var lava = Level.map.get_node("StoryLavaField")
	h.check("client field draws the host's gas", field.net_client)
	var got: bool = await h.until(func(): return field.net_packets > 0, 20.0)
	h.check("the host's gas arrived", got, field.net_packets)
	# Watching only, until the toxin check.
	field.freeze_toxin = true
	var cool := func(): lava.heat = 0.0
	Level.map.get_tree().process_frame.connect(cool)
	var a := Vector2i(int(room[0]), int(room[1]))
	var b := Vector2i(int(room[2]), int(room[3]))
	var before = await shared(h, "before", 30.0)
	h.check("the host shared its gas before the breach", before != null)
	if before != null:
		h.check("the sealed caverns' gas matches before anything is breached", field.mass.size() == int(before["n"]) and absf(_total(field) - float(before["total"])) < 0.01 and field.rock.size() == int(before["rock"]),
			{"host": before, "client n": field.mass.size(), "client total": _total(field), "client rock": field.rock.size()})
	await h.teleport_tile(a + Vector2i(1, 1))

	# ---- rising
	var worst := 0.0
	var grew := false
	var base: float = _total(field)
	var packets0: int = field.net_packets
	var flux_seen := 0
	for i in 14:
		await h.wait(1.0)
		var hs = await shared(h, "gas")
		var mine: float = _total(field)
		if mine > base + 3.0:
			grew = true
		flux_seen = maxi(flux_seen, field.flux.size())
		var rel: float = absf(mine - float(hs["total"])) / maxf(1.0, float(hs["total"]))
		worst = maxf(worst, rel)
		h.note("rising %d" % i, {"host total": hs["total"], "client total": mine, "host n": hs["n"], "client n": field.mass.size(), "flux cells": field.flux.size()})
		if i == 6 or i == 8:
			h.snap_camera()
			await h.shot("client_rising")
	h.check("gas came out of the pocket on the client", grew, [base, _total(field)])
	h.check("gas total tracks the host while it rises (within 5%)", worst < 0.05, worst)
	h.check("the client gets the gas's movement for the look", flux_seen > 0 and field.net_packets > packets0 + 10, [flux_seen, field.net_packets - packets0])
	var burst = await shared(h, "burst", 30.0)
	var open := 0
	for e in burst["cells"]:
		if Level.map.is_tile_empty(Vector2i(int(e[0]), int(e[1]))):
			open += 1
	h.check("the pocket's gas rock burst on the client", open == burst["cells"].size() and field.rock.size() == int(burst["rock"]), {"open": open, "cells": burst["cells"].size(), "client rock": field.rock.size(), "host rock": burst["rock"]})

	# ---- settled
	var fin = await shared(h, "gas_final", 60.0)
	await h.wait(1.5)
	var cmp: Dictionary = _compare(field, fin)
	h.note("settled", cmp)
	h.check("settled gas matches the host cell by cell", cmp["cells off"] == 0 and cmp["client n"] == cmp["host n"], cmp)
	h.snap_camera()
	await h.shot("client_settled")

	# ---- toxin: this keeper's own bar, this keeper's recall, the host's penalty
	var thick = null
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			var c := Vector2i(x, y)
			if field.mass.get(c, 0.0) >= GasData.DENSE_MASS and (thick == null or field.mass[c] > field.mass[thick]):
				thick = c
	h.check("thick gas to stand in", thick != null, thick)
	if thick == null:
		return
	var money0 = Data.ofOr("team1.inventory.money", 0)
	await h.teleport_tile(thick)
	h.keeper().set("gravity_scale", 0.0)
	field.freeze_toxin = false
	await h.wait(1.5)
	h.note("toxin after 1.5 s in gas", {"toxin": field.toxin, "breathing": field.breathing})
	h.check("the client keeper's toxin bar fills in gas", field.toxin > 20.0, field.toxin)
	await h.shot("client_in_gas")
	var recalled: bool = await h.until(func(): return h.keeper_tile().y < 0, 60.0)
	h.keeper().set("gravity_scale", 1.0)
	h.check("the client keeper is recalled to the dome", recalled and field.gassed == 1, [h.keeper_tile(), field.gassed])
	await h.wait(2.0)
	var money1 = Data.ofOr("team1.inventory.money", 0)
	h.check("the host took half the money", int(money1) == int(money0) / 2, [money0, money1])
	h.check("clean dome air: the bar is empty again", field.toxin == 0.0, field.toxin)
	await h.shot("client_recalled")

	# ---- fire
	field.freeze_toxin = true
	await h.teleport_tile(a + Vector2i(1, 1))
	var ign = await shared(h, "igniting", 90.0)
	h.check("the host is lighting the gas", ign != null, ign)
	var lit: bool = await h.until(func(): return not field.fire.is_empty(), 20.0)
	h.check("the fire reaches the client", lit, field.fire.size())
	var peak := 0
	var in_fire := false
	for n in 12:
		peak = maxi(peak, field.fire.size())
		in_fire = in_fire or field.in_fire
		await h.burst("client_fire_%02d" % n, 1, 4)
	var done = await shared(h, "fire_done", 90.0)
	await h.wait(1.5)
	var after: Dictionary = _compare(field, done["state"])
	after["peak fire cells"] = [peak, done["peak"]]
	after["client keeper in fire"] = in_fire
	after["client fire left"] = field.fire.size()
	h.note("after the fire", after)
	h.check("the client saw the fire spread", peak >= 3, [peak, done["peak"]])
	h.check("after the fire the gas matches the host and nothing burns", after["cells off"] == 0 and after["client n"] == after["host n"] and field.fire.is_empty(), after)
	h.snap_camera()
	await h.shot("client_burnt")

	# ---- the dome's gas
	var dg = await shared(h, "dome", 60.0)
	h.keeper().global_position = home
	await h.frames(5)
	h.snap_camera()
	field.toxin = 0.0
	field.freeze_toxin = false
	await h.wait(5.0)
	h.note("in the gassed dome", {"amount": field.dome.amount, "host amount": dg["amount"], "toxin": field.toxin, "inside": h.keeper().isInsideDome, "haze": field.dome.shown})
	h.check("the dome's gas reaches the client", absf(field.dome.amount - float(dg["amount"])) < 0.01, [field.dome.amount, dg["amount"]])
	h.check("the client keeper breathes it in the dome", h.keeper().isInsideDome and field.toxin > 3.0, field.toxin)
	h.check("the haze shows in the client's dome", field.dome.shown > 0.3, field.dome.shown)
	await h.shot("client_dome_gas")
	var water0 = Data.ofOr("team1.inventory.water", 0)
	await h.buy("storyventdome")
	var cleared: bool = await h.until(func(): return field.dome.amount == 0.0, 10.0)
	await h.wait(3.0)
	h.check("the client's Vent the Dome clears the dome's gas", cleared and field.dome.shown < 0.05, [field.dome.amount, field.dome.shown])
	h.check("the vent took its water", int(Data.ofOr("team1.inventory.water", 0)) < int(water0), [water0, Data.ofOr("team1.inventory.water", 0)])
	h.check("clean dome air again", field.toxin == 0.0, field.toxin)
	await h.shot("client_dome_vented")


static func _total(field) -> float:
	var t := 0.0
	for c in field.mass:
		t += field.mass[c]
	return t


# This field against a host state with cells (`near`): how many of those cells
# differ, and the whole field's count and total.
static func _compare(field, hs: Dictionary) -> Dictionary:
	var diff := 0
	var biggest := 0.0
	for e in hs["near"]:
		var d: float = absf(field.mass.get(Vector2i(int(e[0]), int(e[1])), 0.0) - float(e[2]))
		biggest = maxf(biggest, d)
		if d > 0.001:
			diff += 1
	return {"cells compared": hs["near"].size(), "cells off": diff, "biggest": biggest, "host n": int(hs["n"]), "client n": field.mass.size(), "host total": hs["total"], "client total": _total(field)}
