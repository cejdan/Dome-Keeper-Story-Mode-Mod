extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #229: host half. The dome falls: the lost run's end screen shows on the host
# and on the client. Pair: t229_mp_lose_client.

const TIMEOUT := 300


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if not await host_start(h):
		return
	await h.wait(4.0)
	share("go", true)
	await h.wait(1.0)
	Data.apply("team1.dome.health", 0)
	var panel: bool = await h.until(func(): return Level.stage.endingPanel != null, 40.0)
	h.check("lost run's end screen on the host", panel and GameWorld.lost and not GameWorld.won)
	await h.wait(2.5)
	await h.shot("host_lost")
	await h.wait(4.0)
	h.check("one end screen, no ending cards", Level.mode.end_screens == 1 and Level.mode.get_node("StoryEndings").cards_shown == 0, [Level.mode.end_screens, Level.mode.get_node("StoryEndings").cards_shown])
	await host_wait_clients_left(h, 90.0)
