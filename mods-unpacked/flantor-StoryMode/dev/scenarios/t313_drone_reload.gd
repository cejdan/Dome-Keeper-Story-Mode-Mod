extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t313_drone_crash.gd"

# Ticket 313, part two: run t313_drone_crash first. This loads its save (slot
# 37, made between two waves with the drones out) the way Continue does,
# then plays a wave to its end, a mining stretch and another wave, tiles on
# the drones' paths still changing and cobalt going 1 -> 0 near a wave's end.


func boot() -> Dictionary:
	return {"load": SLOT}


func run(h) -> void:
	rng.seed = 3132
	map = Level.map
	td = map.tileData
	h.check("a Story Mode run came back from the save", Level.loadout != null and Level.loadout.modeId == "storymode")
	await h.until(func(): return _drones(h).size() >= 3, 15.0)
	h.check("the drones came back", _drones(h).size() >= 3, _drones(h).map(func(d): return d.state))
	await h.teleport_tile(Vector2i(-2, 8))
	h.enable_waves()
	GameWorld.runStarted = true
	h.speed(2.0)
	await h.shot("reloaded")
	_spawn_far(6)
	await _churn(h, 5.0, "reloaded")
	Data.apply("team1.monsters.wavecooldown", 2)
	var first: bool = await h.until(func(): return Data.of("team1.monsters.wavepresent"), 60.0)
	h.check("a wave came after the reload", first)
	await _churn(h, 15.0, "reloaded wave")
	h.set_inv(CONST.SAND, 1)
	await _churn(h, 2.0, "reload cobalt")
	h.set_inv(CONST.SAND, 0)
	for mm in Level.monstersByTeamId.values():
		mm.instantlyKillWave()
	await h.until(func(): return not Data.of("team1.monsters.wavepresent"), 30.0)
	_spawn_far(6)
	await _churn(h, 25.0, "after the wave")
	Data.apply("team1.monsters.wavecooldown", 2)
	var came: bool = await h.until(func(): return Data.of("team1.monsters.wavepresent"), 60.0)
	h.check("another wave came", came)
	await _churn(h, 15.0, "next wave")
	await h.shot("next_wave")
	for mm in Level.monstersByTeamId.values():
		mm.instantlyKillWave()
	await h.until(func(): return not Data.of("team1.monsters.wavepresent"), 30.0)
	h.disable_waves()
	h.speed(1.0)
	await h.shot("end")
	_graph_check(h)
	h.check("tiles changed on drone paths", toggles >= 10, toggles)
	h.check("no drone path runs through solid rock", bad_paths.is_empty(), bad_paths.slice(0, 20))
	h.check("no drone leaves the map", off_map.is_empty(), off_map.slice(0, 10))
	h.check("the run is still going", is_instance_valid(map) and not GameWorld.gameover)
