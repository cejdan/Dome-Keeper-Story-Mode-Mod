extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #364: client half. Its tentacles are built from the host's map facts in the
# same places, take the host's chains broken (Data) and run on the host's wave
# clock: at every moment the host shares (wall-clock time, both instances on
# one machine), the client's own tips are where the host's were. Its own
# set_chains_broken does nothing (the host owns it), and when the host breaks
# more chains, the client's swing follows. Pair: t364_mp_host.

const Ocean = preload("res://mods-unpacked/flantor-StoryMode/map/ocean_tentacles.gd")
static var _Ocean = Ocean  # calls go through this: lazy_preload makes const-preload calls slow
const TIMEOUT := 420

var _hist: Array = []   # [wall, tips]


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var ready = await shared(h, "ready", 120.0)
	if not h.check("host ready", ready != null):
		return
	var ok: bool = await h.until(func(): return _Ocean.find() != null, 20.0)
	if not h.check("client: the ocean tentacles are built", ok):
		return
	var tents = _Ocean.find()
	h.check("client: its tentacles are a copy (net_client)", tents.net_client)
	var places = await shared(h, "places")
	var same: bool = places != null and places.size() == tents.places.size()
	if same:
		for i in places.size():
			if int(places[i]["x"]) != int(tents.places[i]["x"]) or int(places[i]["base_row"]) != int(tents.places[i]["base_row"]) or int(places[i]["segments"]) != int(tents.places[i]["segments"]):
				same = false
	h.check("client: the same two tentacles as the host (from its map facts)", same, [places, tents.places])
	var six: bool = await h.until(func(): return _Ocean.chains_broken() == 6, 15.0)
	h.check("client: the host's chains broken arrive (6)", six, _Ocean.chains_broken())
	_Ocean.set_chains_broken(2)
	await h.wait(0.5)
	h.check("client: its own set_chains_broken is ignored", _Ocean.chains_broken() == 6, _Ocean.chains_broken())
	# Be by the right tip, so this instance poses (and sees) them too.
	var cells: Array = []
	for p: Dictionary in tents.places:
		for y in range(int(p["tip_row"]) - 3, int(p["base_row"]) + 1):
			for dx in range(-8, 9):
				cells.append(Vector2i(int(p["x"]) + dx, y))
	await h.reveal(cells)
	var k = h.keeper()
	k.teleport(tents.rigs[1].pad_top_now() + Vector2(50, -20))
	tents.refresh_near()
	h.snap_camera(k)
	var lava = Level.map.get_node_or_null("StoryLavaField")
	await h.wait(1.0)
	await h.shot("client_tentacles")
	# Compare: keep this instance's tips per physics frame; for each host
	# sample, this instance's tips at the host's moment.
	var errs: Array = []
	var seen: Dictionary = {}
	var share_after_nine: float = -1.0
	var host_share_nine: float = -1.0
	var t0: float = h.now()
	while h.now() - t0 < 40.0:
		await h.get_tree().physics_frame
		_hist.append([Time.get_unix_time_from_system(), _tips(tents)])
		if _hist.size() > 600:
			_hist.pop_front()
		if lava != null:
			lava.set_heat_of(k, 0.0)
		var c = Data.ofOr(DEV_SHARE, "")
		if not c is String or c == "":
			continue
		var d: Dictionary = JSON.parse_string(c)
		if d.has("clock") and not seen.has(int(d["clock"]["i"])):
			var s: Dictionary = d["clock"]
			seen[int(s["i"])] = true
			var mine = _at(float(s["wall"]))
			if mine != null:
				var e: float = 0.0
				for j in mine.size():
					e = maxf(e, Vector2(float(s["tips"][j][0]), float(s["tips"][j][1])).distance_to(mine[j]))
				errs.append([int(s["i"]), snappedf(e, 0.01)])
			if int(s["i"]) >= 90 and share_after_nine < 0.0:
				share_after_nine = tents.rigs[0].share
				host_share_nine = float(s["share"])
		if d.has("done"):
			break
	h.note("tip error (px) per host sample [i, err]", errs)
	var late: Array = errs.filter(func(e): return int(e[0]) >= 8)
	var worst: float = 0.0
	var total: float = 0.0
	for e in late:
		worst = maxf(worst, float(e[1]))
		total += float(e[1])
	h.note("client vs host tips after the first 2 s: %d samples, worst %.2f px, mean %.2f px" % [late.size(), worst, total / maxf(1.0, float(late.size()))])
	h.check("client: compared at 40+ host moments", late.size() >= 40, late.size())
	h.check("client: its tips are where the host's are (within 4 px at every moment)", worst < 4.0, worst)
	h.check("client: the host's 9 chains reach it", _Ocean.chains_broken() == 9, _Ocean.chains_broken())
	h.check("client: its swing follows the host's after the break (within 0.02)", share_after_nine > 0.0 and absf(share_after_nine - host_share_nine) < 0.02, [share_after_nine, host_share_nine])
	await h.shot("client_end")


func _tips(tents) -> Array:
	var out: Array = []
	for r in tents.rigs:
		out.append(r.tip())
	return out


# This instance's tips at wall time `w`, between the two frames round it.
func _at(w: float):
	for i in range(_hist.size() - 1, 0, -1):
		var a: Array = _hist[i - 1]
		var b: Array = _hist[i]
		if float(a[0]) <= w and float(b[0]) >= w:
			var u: float = (w - float(a[0])) / maxf(0.000001, float(b[0]) - float(a[0]))
			var out: Array = []
			for j in a[1].size():
				out.append((a[1][j] as Vector2).lerp(b[1][j], u))
			return out
	return null
