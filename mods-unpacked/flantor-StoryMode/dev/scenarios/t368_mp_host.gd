extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #368: host half of the online check for the ship. The host breaks all ten
# chains (the last live): the ship leaves the ocean and stands at the dome on
# both. The host's keeper is out in the mine. The client's keeper walks to the
# hatch in the dome and holds the use key: the host takes its word (once),
# stops play for everyone and lifts off with the client's keeper aboard, then
# plays the doom ending; one keeper boarding ends the run for both (the end
# screen "The Planet Is Lost" on each). Pair: t368_mp_client.

const EndGame = preload("res://mods-unpacked/flantor-StoryMode/endgame/end_game.gd")
static var _EndGame = EndGame  # calls go through this: lazy_preload makes const-preload calls slow
const Anchors = preload("res://mods-unpacked/flantor-StoryMode/map/chain_anchors.gd")
static var _Anchors = Anchors  # calls go through this: lazy_preload makes const-preload calls slow
const Ship = preload("res://mods-unpacked/flantor-StoryMode/endgame/ship.gd")
static var _Ship = Ship  # calls go through this: lazy_preload makes const-preload calls slow
const Endings = preload("res://mods-unpacked/flantor-StoryMode/data/endings.gd")
const TIMEOUT := 420


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if not await host_start(h):
		return
	var ok: bool = await h.until(func(): return _Anchors.find() != null and _Ship.find() != null, 20.0)
	if not h.check("host: the anchors and the ship are built", ok):
		return
	h.mute_beats()
	var ship = _Ship.find()
	var anchors = _Anchors.find()
	h.disable_waves()
	h.check("host: the ship is in the ocean", ship.mode == "ocean", ship.mode)
	share("ready", true)
	# The client's keeper goes into the dome (a client can't share back).
	var k = h.keeper()
	var inside: bool = await h.until(func():
		for kk in Keepers.getAll():
			if kk != k and kk.getIsInsideDome() and kk.global_position.distance_to(Level.getDome("team1").global_position) < 60.0:
				return true
		return false, 90.0)
	h.check("host: the client's keeper is in the dome", inside)
	await h.wait(1.0)
	for a in anchors.anchors:
		if not a["broken"]:
			anchors.dev_break(a["id"], false)
			await h.wait(0.1)
	h.check("host: free", _EndGame.is_free(), _EndGame.state())
	var landed: bool = await h.until(func(): return ship.mode == "dome", 40.0)
	h.check("host: the ship stands at the dome (the last-chain cutscene, live)", landed and _Ship.events.any(func(e): return e["what"] == "landed" and e["live"]), _Ship.events)
	# The cutscene (#367) ends before play goes on.
	var LastChain = load("res://mods-unpacked/flantor-StoryMode/endgame/last_chain.gd")
	await h.until(func(): return LastChain.is_done() and not GameWorld.paused, 40.0)
	# The host's keeper out in the mine, far from the dome.
	k.teleport(Level.getDome("team1").global_position + Vector2(0, 24 * 12))
	h.snap_camera(k)
	share("landed", true)
	var lifting: bool = await h.until(func(): return ship.mode == "lifting" or ship.mode == "gone", 120.0)
	var client_pid: String = ""
	for kk in Keepers.getAll():
		if kk != k:
			client_pid = kk.playerId
	var lift: Array = _Ship.events.filter(func(e): return e["what"] == "lift_off")
	h.check("host: the client's keeper boarded: the lift-off, with it aboard", lifting and lift.size() == 1 and lift[0]["player"] == client_pid, [lift, client_pid])
	h.check("host: its own keeper never asked", not _Ship.events.any(func(e): return e["what"] == "board_asked"), _Ship.events)
	h.check("host: play stops for everyone (the host's keeper too, out in the mine)", Level.mode.is_ending(), Level.mode.is_ending())
	await h.wait(2.5)
	await h.shot("host_liftoff")
	var panel: bool = await h.until(func(): return Level.stage.endingPanel != null, 90.0)
	await h.wait(1.0)
	await h.shot("host_end_screen")
	h.check("host: the doom ending's end screen", panel and GameWorld.won and Level.stage.endingPanel.titleLabel.text == Endings.DOOM_TITLE, [GameWorld.won, Level.stage.endingPanel.titleLabel.text if panel else null])
	h.check("host: one end screen", Level.mode.end_screens == 1, Level.mode.end_screens)
	share("done", true)
	await host_wait_clients_left(h)
