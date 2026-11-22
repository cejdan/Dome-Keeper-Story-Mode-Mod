extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# Ticket 314 online, client half: once the host has dug the lanes and dragged
# its own drops, the client's Engineer picks up each drop the host spawns for
# it and drags it (pressed) or flings it, measuring what the client sees.
# Pair: t314_mp_drag_host.

const TIMEOUT := 600
const D = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t314_drop_drag.gd")
const TRIALS := 8   # t314_mp_drag_host: 2 floors x 2 kinds x 2 modes


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var by_floor = await shared(h, "lanes", 120.0)
	if not h.check("host shared the lanes", by_floor != null, by_floor):
		return
	for f: String in by_floor:
		D.set_lane_tiles(by_floor[f], int(D.FLOORS[f]))
	h.check("host dug them", await shared(h, "dug", 60.0) == true)
	var open: bool = await h.until(func():
		for f in by_floor:
			var l: Dictionary = by_floor[f]
			if not Level.map.is_tile_empty(Vector2i(int(l["x1"]), int(l["y"]))) or not Level.map.is_tile_empty(Vector2i(int(l["x1"]), int(l["y"]) - 2)):
				return false
		return true, 20.0)
	h.check("lanes open on the client", open)
	var k = h.keeper()
	h.check("the client's keeper is the Engineer", k.techId == "keeper1", k.techId)
	var res := {}
	for n in TRIALS:
		var got: bool = await h.until(func():
			var t = shared_now("trial")
			return t != null and int(t["n"]) == n, 180.0)
		if not h.check("trial %d shared" % n, got):
			return
		var t: Dictionary = shared_now("trial")
		var uid: int = int(t["uid"])
		await h.until(func(): return Level.drops.has_drop(uid), 10.0)
		var d = Level.drops.get_drop(uid) if Level.drops.has_drop(uid) else null
		if not h.check("trial %d: the drop reached the client" % n, d != null, t):
			continue
		var f: String = t["floor"]
		var key: String = "%s@%s" % [t["kind"], f]
		var label: String = "client_" + key
		var r: Dictionary
		if t["mode"] == "pressed":
			r = await D.pressed(h, k, by_floor[f], t["kind"], D.keyboard_mover(h), label, d)
		else:
			r = await D.fling(h, k, by_floor[f], t["kind"], D.keyboard_mover(h), label, d)
		if not res.has(key):
			res[key] = {}
		res[key].merge(r, true)
	# The client's drops are its own scenes following the host (vanilla iron is
	# Story iron here), so friction is the host's to check.
	D.judge(h, res, "client view ", false, false)


func shared_now(key: String):
	var have = Data.ofOr(DEV_SHARE, "")
	if not have is String or have == "":
		return null
	return JSON.parse_string(have).get(key)
