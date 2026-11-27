extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #364: host half of the online check for the ocean's tentacles. Sets 6
# chains broken, reveals the ocean round the tentacles, stands its keeper by
# the left tip and shares, 4 times a second, the wall-clock time and where
# both tips are, so the client can compare its own tentacles at the same
# moment (both instances run on this machine: one clock). Halfway it breaks
# three more chains (9). Pair: t364_mp_client.

const Ocean = preload("res://mods-unpacked/flantor-StoryMode/map/ocean_tentacles.gd")
static var _Ocean = Ocean  # calls go through this: lazy_preload makes const-preload calls slow
const TIMEOUT := 420


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


static func tips(tents) -> Array:
	var out: Array = []
	for r in tents.rigs:
		var p: Vector2 = r.tip()
		out.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
	return out


func run(h) -> void:
	if not await host_start(h):
		return
	var ok: bool = await h.until(func(): return _Ocean.find() != null, 20.0)
	if not h.check("host: the ocean tentacles are built", ok):
		return
	var tents = _Ocean.find()
	h.check("host: its tentacles run the clock (not a copy)", not tents.net_client)
	load("res://mods-unpacked/flantor-StoryMode/dev/boss_dev.gd").give_gear()
	_Ocean.set_chains_broken(6)
	var cells: Array = []
	for p: Dictionary in tents.places:
		for y in range(int(p["tip_row"]) - 3, int(p["base_row"]) + 1):
			for dx in range(-8, 9):
				cells.append(Vector2i(int(p["x"]) + dx, y))
	await h.reveal(cells)
	var k = h.keeper()
	k.teleport(tents.rigs[0].pad_top_now() + Vector2(-50, -20))
	tents.refresh_near()
	h.snap_camera(k)
	share("places", tents.places)
	share("ready", true)
	await h.wait(1.0)
	await h.shot("host_tentacles")
	var lava = Level.map.get_node_or_null("StoryLavaField")
	for i in 100:
		if i == 50:
			_Ocean.set_chains_broken(9)
			share("nine", Time.get_unix_time_from_system())
		share("clock", {"wall": Time.get_unix_time_from_system(), "tips": tips(tents), "share": tents.rigs[0].share, "i": i})
		if lava != null:
			lava.set_heat_of(k, 0.0)
		await h.wait(0.25)
	share("done", true)
	h.note("host: chains broken at the end", _Ocean.chains_broken())
	h.check("host: a client's set_chains_broken did not change it (still 9)", _Ocean.chains_broken() == 9, _Ocean.chains_broken())
	await h.shot("host_end")
	await host_wait_clients_left(h)
