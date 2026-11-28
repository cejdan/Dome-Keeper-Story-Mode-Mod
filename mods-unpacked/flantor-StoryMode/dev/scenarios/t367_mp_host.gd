extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #367: host half of the online cutscene. The host breaks all ten chains (the
# last live) with its keeper in the ocean by the ship; the client's keeper is
# in the dome. The host's cutscene plays: frozen, every step in order, the
# ship set down at the dome; the host opens the beat for the team (the beats'
# own team pause) and tells the client ("beat", then "return" once both have
# closed it); then back to the keepers and play resumes, done once, live.
# Pair: t367_mp_client.

const EndGame = preload("res://mods-unpacked/flantor-StoryMode/endgame/end_game.gd")
static var _EndGame = EndGame  # calls go through this: lazy_preload makes const-preload calls slow
const Anchors = preload("res://mods-unpacked/flantor-StoryMode/map/chain_anchors.gd")
static var _Anchors = Anchors  # calls go through this: lazy_preload makes const-preload calls slow
const Ship = preload("res://mods-unpacked/flantor-StoryMode/endgame/ship.gd")
static var _Ship = Ship  # calls go through this: lazy_preload makes const-preload calls slow
const LastChain = preload("res://mods-unpacked/flantor-StoryMode/endgame/last_chain.gd")
static var _LastChain = LastChain  # calls go through this: lazy_preload makes const-preload calls slow
const Cut = preload("res://mods-unpacked/flantor-StoryMode/data/last_chain.gd")
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
static var _StoryBeats = StoryBeats  # calls go through this: lazy_preload makes const-preload calls slow
const TIMEOUT := 420


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if not await host_start(h):
		return
	var ok: bool = await h.until(func(): return _Anchors.find() != null and _Ship.find() != null and _LastChain.find() != null, 20.0)
	if not h.check("host: the anchors, the ship and the cutscene are built", ok):
		return
	h.mute_beats()
	var played: Array = Array(str(Data.ofOr(_StoryBeats.PLAYED, "")).split(",", false))
	played.erase(Cut.BEAT_ID)
	Data.apply(_StoryBeats.PLAYED, ",".join(PackedStringArray(played)))
	var ship = _Ship.find()
	var anchors = _Anchors.find()
	var cut = _LastChain.find()
	var steps: Array = []
	cut.step_changed.connect(func(s): steps.append(s))
	h.disable_waves()
	var k = h.keeper()
	var td = Level.map.tileData
	var ocean: Dictionary = td.get_meta("story_ocean")
	var cells: Array = []
	for y in range(int(ocean["ceiling"]), int(ocean["top"]) + 2):
		for x in range(int(ocean["x0"]) - 2, int(ocean["x1"]) + 3):
			cells.append(Vector2i(x, y))
	await h.reveal(cells)
	k.teleport(ship.to_global(ship.ocean_home) + Vector2(-170, -70))
	h.snap_camera(k)
	share("ready", true)
	# The client's keeper goes into the dome (a client can't share back).
	await h.wait(10.0)
	await h.wait(2.0)
	for a in anchors.anchors:
		if not a["broken"]:
			anchors.dev_break(a["id"], false)
			await h.wait(0.05)
	var started: bool = await h.until(func(): return cut.step != "idle", 3.0)
	h.check("host: free, the cutscene plays here, play frozen", _EndGame.is_free() and started and GameWorld.paused, [cut.step, GameWorld.paused])
	await h.until(func(): return cut.step == "burst", 15.0)
	await h.wait(0.2)
	await h.shot("host_burst")
	await h.until(func(): return cut.step == "dock", 12.0)
	await h.shot("host_docked")
	var id: String = await h.read_beat("host_beat", 15.0)
	h.check("host: the beat opens for the team", id == Cut.BEAT_ID, id)
	var done: bool = await h.until(func(): return cut.step == "done", 90.0)
	h.check("host: after the client closed it too, back to the keeper; play resumes", done and not GameWorld.paused, [cut.step, GameWorld.paused])
	h.check("host: every step in order", steps == ["hold", "rise", "crack", "burst", "carry", "set", "mend", "release", "dock", "beat", "return", "done"], steps)
	h.check("host: the ship at the dome, set down live", ship.mode == "dome" and _Ship.events.any(func(e): return e["what"] == "landed" and e["live"]), ship.mode)
	h.check("host: done in Data", float(Data.ofOr(_LastChain.DONE_KEY, -1.0)) > 0.0, Data.ofOr(_LastChain.DONE_KEY, null))
	await h.wait(0.5)
	await h.shot("host_after")
	share("done", true)
	await host_wait_clients_left(h)
