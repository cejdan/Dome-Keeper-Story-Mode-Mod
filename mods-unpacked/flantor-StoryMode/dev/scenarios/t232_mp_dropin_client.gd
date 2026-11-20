extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #232 (drop-in), the player back: a new process joins the run under way (the
# keeper choice in client-only mode; dev/harness.gd takes the free keeper and
# starts). It must get the map facts, all the lava and gas (rooms that settled
# long before it came, so only a full snapshot carries them), the story state
# and Velle's fight with its hearts. Pair: t232_mp_dropin_host (as -Rejoin).

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const TIMEOUT := 240


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var lava = Level.map.get_node_or_null("StoryLavaField")
	var gas = Level.map.get_node_or_null("StoryGasField")
	var t0: float = h.now()
	var live = await shared(h, "live", 60.0)
	h.check("the host shares its view", live is Dictionary)
	if not live is Dictionary:
		return
	h.check("this keeper is the one that left", Keepers.first() != null and Keepers.first().playerId == live["leaver"], {"mine": Keepers.first().playerId if Keepers.first() else "", "left": live["leaver"]})
	var meta: bool = await h.until(func(): return facts({})["map meta"], 20.0)
	h.check("the map facts reached the late joiner", meta)
	await h.until(func(): return Level.map.has_node("StoryGasField"), 20.0)
	gas = Level.map.get_node("StoryGasField")
	await h.until(func(): return gas.net_packets > 0, 20.0)
	await h.until(func(): return _Director.current() == "fight", 10.0)
	await h.wait(2.5)    # the boss repeat (2 s) and the #242 resend
	live = await shared(h, "live")
	var rooms: Dictionary = live["rooms"]
	var mine := facts(rooms)
	mine["velle"] = _Director.instance() != null and _Director.instance().velle != null and is_instance_valid(_Director.instance().velle)
	h.note("client facts", mine)
	h.note("time from run start to checks", h.now() - t0)
	check_facts(h, mine, live, "drop-in")
	h.check("drop-in: Velle is drawn here", mine["velle"] == true, mine["velle"])
	await h.shot("client_fight")
	await look_at_rooms(h, rooms)
	await h.wait(1.0)
	await h.shot("client_rooms")
