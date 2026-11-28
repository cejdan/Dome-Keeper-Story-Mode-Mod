extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #367: client half. Its keeper is in the dome. The host's last chain
# reaches it live: its own copy of the cutscene plays (its camera, its ship),
# frozen here too, in step with the host: at the host's "beat" it is at the
# dock or the beat already; the beat opens here from the host's team key and
# this player reads it; at the host's "return" both camera pans go back.
# After: the ship at the dome, done here (live), play resumes, the keeper
# moves by real input. Pair: t367_mp_host.

const Ship = preload("res://mods-unpacked/flantor-StoryMode/endgame/ship.gd")
static var _Ship = Ship  # calls go through this: lazy_preload makes const-preload calls slow
const LastChain = preload("res://mods-unpacked/flantor-StoryMode/endgame/last_chain.gd")
static var _LastChain = LastChain  # calls go through this: lazy_preload makes const-preload calls slow
const Cut = preload("res://mods-unpacked/flantor-StoryMode/data/last_chain.gd")
const TIMEOUT := 420


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var ready = await shared(h, "ready", 150.0)
	if not h.check("host ready", ready != null):
		return
	var ok: bool = await h.until(func(): return _Ship.find() != null and _LastChain.find() != null and h.keeper() != null, 30.0)
	if not h.check("client: the ship and the cutscene are built", ok):
		return
	var ship = _Ship.find()
	var cut = _LastChain.find()
	var steps: Array = []
	cut.step_changed.connect(func(s): steps.append(s))
	var k = h.keeper()
	k.teleport(Level.getDome("team1").global_position + Vector2(10, -12))
	h.snap_camera(k)
	var started: bool = await h.until(func(): return cut.step != "idle", 150.0)
	h.check("client: the host's last chain plays the cutscene here, live, frozen", started and cut.live and GameWorld.paused, [cut.step, GameWorld.paused])
	var p0: Vector2 = k.global_position
	h.down("ui_left")
	await h.until(func(): return cut.step == "burst", 15.0)
	await h.wait(0.2)
	await h.shot("client_burst")
	await h.until(func(): return cut.step == "carry", 5.0)
	await h.wait(0.6)
	await h.shot("client_carry")
	var id: String = await h.read_beat("client_beat", 25.0)
	h.up("ui_left")
	h.check("client: the beat opens here from the host's word, this player reads it", id == Cut.BEAT_ID, id)
	h.check("client: frozen here too (a key held, the keeper never moved)", k.global_position.distance_to(p0) < 0.5, k.global_position - p0)
	var done: bool = await h.until(func(): return cut.step == "done", 60.0)
	var told: Array = _LastChain.events.filter(func(e): return e["what"] == "host_step")
	h.check("client: in step with the host: at its 'beat' this copy was at the dock or the beat, then its 'return'", told.size() >= 2 and told[0]["step"] == "beat" and told[0]["at"] in ["release", "dock", "beat"] and told[1]["step"] == "return", told)
	h.check("client: every step, in order", steps == ["hold", "rise", "crack", "burst", "carry", "set", "mend", "release", "dock", "beat", "return", "done"], steps)
	h.check("client: back on its keeper, play resumes, the ship at the dome", done and not GameWorld.paused and ship.mode == "dome" and _LastChain.is_done(), [cut.step, GameWorld.paused, ship.mode])
	await h.wait(0.3)
	await h.shot("client_after")
	var p1: Vector2 = k.global_position
	await h.hold("ui_right", 1.0)
	h.check("client: its keeper moves by real input", k.global_position.distance_to(p1) > 4.0, k.global_position - p1)
	await shared(h, "done", 60.0)
