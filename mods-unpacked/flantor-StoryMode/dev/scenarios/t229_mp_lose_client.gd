extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #229: client half. The dome falls on the host: the lost run's end screen
# shows here too. Pair: t229_mp_lose_host.

const TIMEOUT := 300


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	h.check("host is ready", await shared(h, "go", 60.0) != null)
	var panel: bool = await h.until(func(): return Level.stage.endingPanel != null, 40.0)
	h.check("lost run's end screen on the client", panel and GameWorld.lost and not GameWorld.won, [GameWorld.lost, GameWorld.won])
	h.check("the client's mode knows the run is over", Level.mode.is_ending())
	await h.wait(2.5)
	await h.shot("client_lost")
	await h.wait(4.0)
	h.check("one end screen, no ending cards", Level.mode.end_screens == 1 and Level.mode.get_node("StoryEndings").cards_shown == 0, [Level.mode.end_screens, Level.mode.get_node("StoryEndings").cards_shown])
