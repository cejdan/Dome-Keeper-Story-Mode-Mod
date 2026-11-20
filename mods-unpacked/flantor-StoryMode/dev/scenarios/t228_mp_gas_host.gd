extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #228: host half. Digs a sealed room beside a gas pocket and breaches it (the
# rest of the pocket bursts), sharing its gas every second so the client can
# compare; holds the settled gas still for a cell-by-cell check; once the
# client's keeper has been gassed (the host takes half of $1000), lights the
# gas with lava and shares what burnt; then puts gas in the dome for the
# client to breathe and vent. Pair: t228_mp_gas_client.

const GasData = preload("res://mods-unpacked/flantor-StoryMode/data/gas.gd")
const TIMEOUT := 480


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if not await host_start(h):
		return
	var field = Level.map.get_node("StoryGasField")
	var lava = Level.map.get_node("StoryLavaField")
	var td = Level.map.tileData
	h.check("the host runs the gas", not field.net_client)
	# The host's keeper only watches: no toxin, no heat.
	field.freeze_toxin = true
	var cool := func(): lava.heat = 0.0
	Level.map.get_tree().process_frame.connect(cool)

	# A pocket with solid, plain rock to its right for a sealed room.
	var pick = null
	for r: Vector2i in field.rock:
		if r.y < 10 or (pick != null and r.y >= pick.y):
			continue
		var ok := true
		for y in range(r.y - 5, r.y + 2):
			for x in range(r.x + 1, r.x + 6):
				var c := Vector2i(x, y)
				if field.rock.has(c) or lava.magma.has(c) or td.get_resourcev(c) != Data.TILE_DIRT_START or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE:
					ok = false
		if ok:
			pick = r
	h.check("found a gas pocket", pick != null, pick)
	if pick == null:
		return
	var room_a: Vector2i = pick + Vector2i(1, -4)
	var room_b: Vector2i = pick + Vector2i(4, 0)
	# The whole pocket: the gas rock joined to the picked cell.
	var pocket: Array = [pick]
	var i := 0
	while i < pocket.size():
		for d in field.DIRS:
			if field.rock.has(pocket[i] + d) and not pocket.has(pocket[i] + d):
				pocket.append(pocket[i] + d)
		i += 1
	var rock0: int = field.rock.size()
	h.note("pocket", {"pick": pick, "cells": pocket.size(), "gas rock on the map": rock0, "gas cells at start": field.mass.size()})
	await h.dig_room(room_a, room_b)
	h.keeper().teleport(Level.map.getTilePos(room_a + Vector2i(1, 1)))
	h.snap_camera()
	await h.wait(1.0)
	share("room", [room_a.x, room_a.y, room_b.x, room_b.y])
	await h.wait(3.0)
	# (Set here, not at the start: in one run a client never saw values set the
	# moment it came into sync.)
	Data.apply("team1.inventory.money", 1000)
	Data.apply("team1.inventory.water", 5)
	share("before", _state(field, pick, false))
	await h.wait(4.0)
	await h.shot("host_room")
	await h.clear_tiles([pick])
	h.note("breached", pick)
	for n in 20:
		share("gas", _state(field, pick, false))
		await h.wait(1.0)
		if n == 2:
			h.snap_camera()
			await h.shot("host_rising")
			var broken := 0
			for c in pocket:
				if Level.map.is_tile_empty(c):
					broken += 1
			h.check("the whole pocket burst", broken == pocket.size() and field.rock.size() == rock0 - pocket.size(), [broken, pocket.size(), field.rock.size()])
			share("burst", {"rock": field.rock.size(), "cells": pocket.map(func(c): return [c.x, c.y])})
	# Held still, so both sides can be compared cell by cell.
	field.freeze_flow = true
	await h.wait(1.0)
	share("gas_final", _state(field, pick, true))
	h.note("host gas, settled", _state(field, pick, false))
	h.snap_camera()
	await h.shot("host_settled")

	# The client's keeper breathes it and is recalled: the penalty lands here.
	var paid: bool = await h.until(func(): return int(Data.ofOr("team1.inventory.money", 0)) == 500, 120.0)
	h.check("the client's gassing cost the team half its money", paid and lava.recalls == 1, [Data.ofOr("team1.inventory.money", -1), lava.recalls])
	h.check("the host's own bar never moved", field.toxin == 0.0 and field.gassed == 0, [field.toxin, field.gassed])
	await h.wait(8.0)

	# Fire: lava beside the gas.
	field.freeze_flow = false
	var spot = null
	for y in range(room_a.y, room_b.y + 1):
		for x in range(room_a.x, room_b.x):
			var g := Vector2i(x, y)
			if spot == null and field.mass.get(g, 0.0) >= 0.3 and field.mass.get(g + Vector2i.RIGHT, 0.0) >= 0.3:
				spot = g
	h.check("gas left in the room to light", spot != null, _state(field, pick, false))
	if spot == null:
		return
	var gas_before: float = _state(field, pick, false)["total"]
	share("igniting", {"total": gas_before})
	await h.wait(1.0)
	lava.mass[spot] = 1.0
	lava.shown[spot] = 1.0
	lava._wake(spot)
	var lit: bool = await h.until(func(): return field.ignitions > 0, 5.0)
	h.check("lava lit the gas", lit, field.stats())
	var peak := 0
	for n in 12:
		peak = maxi(peak, field.fire.size())
		await h.burst("host_fire_%02d" % n, 1, 4)
	var out: bool = await h.until(func(): return field.fire.is_empty(), 40.0)
	h.check("the fire burnt out", out, field.stats())
	field.freeze_flow = true
	await h.wait(1.0)
	share("fire_done", {"peak": peak, "burned": field.burned, "state": _state(field, pick, true)})
	h.note("after the fire", {"peak fire cells": peak, "burned": field.burned, "gas before": gas_before, "state": _state(field, pick, false)})
	await h.shot("host_burnt")
	await h.wait(4.0)

	# Gas in the dome, for the client to breathe and vent.
	field.dome.amount = 3.0 * GasData.DOME_POCKET_MASS
	share("dome", {"amount": field.dome.amount})
	await host_wait_clients_left(h)
	h.check("the client's Vent the Dome cleared the host's dome", field.dome.amount == 0.0 and field.dome.vents == 1, [field.dome.amount, field.dome.vents])
	h.note("at the end", {"money": Data.ofOr("team1.inventory.money", -1), "water": Data.ofOr("team1.inventory.water", -1), "recalls": lava.recalls})


# The whole field's gas in numbers, and (with `cells`) each cell near `at`.
static func _state(field, at: Vector2i, cells: bool) -> Dictionary:
	var total := 0.0
	var near: Array = []
	for c in field.mass:
		total += field.mass[c]
		if cells and absi(c.x - at.x) <= 12 and absi(c.y - at.y) <= 12:
			near.append([c.x, c.y, snappedf(field.mass[c], 0.0001)])
	var d := {"n": field.mass.size(), "total": total, "fire": field.fire.size(), "rock": field.rock.size()}
	if cells:
		d["near"] = near
	return d
