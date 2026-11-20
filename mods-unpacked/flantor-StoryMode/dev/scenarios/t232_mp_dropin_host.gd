extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #232 (drop-in), host half: a player leaves a run under way and joins it again
# in a new process, as vanilla allows (the keeper choice offers the keeper of a
# player who left). Sets up the run's state (money, a beat, the translator
# stage, heat shield, lava and gas in sealed rooms), then starts Velle's fight
# with the host's keeper in the chamber (its hearts kept topped up), tells the
# first client to leave, and shares its view every second once the player is
# back. Run with:
#   mp_playtest.ps1 t232_mp_dropin_host t232_mp_dropin_leaver -Rejoin t232_mp_dropin_client

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const Boss = preload("res://mods-unpacked/flantor-StoryMode/data/boss.gd")
const Awakening = preload("res://mods-unpacked/flantor-StoryMode/beats/awakening.gd")
const TIMEOUT := 360


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if not await host_start(h):
		return
	var rooms: Dictionary = await setup_run_state(h)
	if rooms.is_empty():
		return
	var lava = Level.map.get_node("StoryLavaField")
	h.get_tree().process_frame.connect(func(): lava.heat = 0.0)
	# Velle's fight, with the host's keeper in the chamber (dev/boss_dev.gd's gear).
	var boss = _Director.instance()
	var dev = load("res://mods-unpacked/flantor-StoryMode/dev/boss_dev.gd")
	dev.give_gear()
	var ch: Rect2i = Level.map.tileData.get_meta("story_boss_chamber")
	var cells: Array = []
	for y in range(ch.position.y - 3, ch.end.y + 2):
		for x in range(ch.position.x - 2, ch.end.x + 2):
			cells.append(Vector2i(x, y))
	await h.reveal(cells)
	Data.apply(Awakening.AWAKE, true)
	await h.wait(1.0)
	await h.teleport_tile(ch.position + Vector2i(ch.size.x / 2, ch.size.y - 2))
	var fight: bool = await h.until(func(): return _Director.current() == "fight", 30.0)
	h.check("Velle's fight is on", fight, _Director.current())
	h.get_tree().process_frame.connect(func():
		if int(Data.ofOr("team1.story.hearts", Boss.HEARTS)) < Boss.HEARTS and _Director.current() == "fight":
			Data.apply("team1.story.hearts", Boss.HEARTS))
	await h.wait(4.0)    # the lava and gas settle; the first client sees the fight
	var leaver: String = ""
	for k in Keepers.getAll():
		if k.peerId != h.multiplayer.get_unique_id():
			leaver = k.playerId
	share("ready", {"rooms": rooms, "leaver": leaver})
	h.note("first client asked to leave", leaver)
	var left: bool = await h.until(func(): return Network.clients.is_empty(), 60.0)
	h.check("the player left", left)
	var t0: float = h.now()
	var back: bool = await h.until(func(): return not Network.clients.is_empty() and Network.clients.all(func(c): return c.connection_state == Network.ConnectionState.LEVEL_STAGE_SYNC), 150.0)
	h.check("the player joined the run again", back, {"waited": h.now() - t0, "states": Network.clients.map(func(c): return c.connection_state)})
	if not back:
		return
	h.note("keepers after the rejoin", keeper_rows(h))
	for i in 40:
		var f := facts(rooms)
		f["rooms"] = rooms
		f["leaver"] = leaver
		f["velle"] = boss.velle != null and is_instance_valid(boss.velle)
		share("live", f)
		if i == 0:
			h.note("host facts", f)
			await h.shot("host_fight")
		await h.wait(1.0)
		if Network.clients.is_empty():
			break
	h.check("the fight held while the player was away and back", _Director.current() == "fight", _Director.current())
	await host_wait_clients_left(h, 60.0)
