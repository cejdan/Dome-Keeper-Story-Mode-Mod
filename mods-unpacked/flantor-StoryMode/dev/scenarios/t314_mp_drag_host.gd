extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# Ticket 314 online, host half: the host's Engineer drags vanilla iron and gold
# over rock and metal (t314_drop_drag), then the client's Engineer does the
# same with drops the host spawns for it one at a time, the host measuring
# them (drops are host physics). Pair: t314_mp_drag_client.

const TIMEOUT := 600
const D = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t314_drop_drag.gd")
const FLOORS := ["rock", "metal"]
const KINDS := ["vanilla_iron", "gold"]
const MODES := ["pressed", "fling"]


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if not await host_start(h):
		return
	var lanes: Array = D.find_lanes(FLOORS.size())
	if not h.check("found a lane for every floor", lanes.size() == FLOORS.size(), lanes):
		return
	var by_floor := {}
	for i in FLOORS.size():
		by_floor[FLOORS[i]] = lanes[i]
		D.set_lane_tiles(lanes[i], D.FLOORS[FLOORS[i]])
	# The client gives its map the same tiles before the host digs.
	share("lanes", by_floor)
	await h.wait(3.0)
	for f in FLOORS:
		await D.dig_lane(h, by_floor[f])
	if Level.map.has_method("finish_flood"):
		Level.map.finish_flood()
	await h.wait(0.5)
	D.check_lanes(h, by_floor)
	share("dug", true)

	var k = h.keeper()
	var res := {}
	for f in FLOORS:
		for kind in KINDS:
			await D.both(h, k, by_floor[f], kind, f, D.keyboard_mover(h), res, "host ")
	D.judge(h, res, "host keeper ")
	k.teleport(Level.getDome("team1").global_position + Vector2(0, -8))
	await h.frames(5)

	# The client's keeper, one drop at a time.
	var cres := {}
	var n := 0
	for f in FLOORS:
		for kind in KINDS:
			for mode in MODES:
				var lane: Dictionary = by_floor[f]
				var d = D.spawn(kind, Level.map.getTilePos(Vector2(D.drop_tile(lane, mode))))
				await h.frames(3)
				share("trial", {"n": n, "uid": d.UID, "floor": f, "kind": kind, "mode": mode})
				n += 1
				var got: bool = await h.until(func(): return is_instance_valid(d) and d.isCarried(), 40.0)
				if not h.check("client picked up %s for %s on %s" % [kind, mode, f], got):
					continue
				var ck = d.carriedBy[0]
				var r: Dictionary = D.material_info(d)
				if mode == "pressed":
					r.merge(await D.sample(h, ck, d, D.HOLD, {}, "host_sees_client_pressed_%s_on_%s" % [kind, f]))
				else:
					r.merge(await D.slide_of(h, d))
				await h.until(func(): return not is_instance_valid(d) or not d.isCarried(), 10.0)
				await h.wait(0.3)
				if is_instance_valid(d):
					Level.drops.network_free_drop(d.UID)
				var key: String = kind + "@" + f
				if not cres.has(key):
					cres[key] = {}
				cres[key].merge(r, true)
				h.note("client %s %s" % [mode, key], r)
	share("trials_done", n)
	D.judge(h, cres, "client keeper (host physics) ", true, false)
	await host_wait_clients_left(h)
