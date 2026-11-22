extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t313_pets.gd"

# Ticket 313, follow-up, part two: run t313_pets first (with the same
# `--keeper=`). This loads its save (slot 38, made between two waves with the
# pets out, the lava chamber hardening and melting and three drones stranded)
# the way Continue does, then plays the churn again: a mining stretch, a wave
# to its end, and the same checks on the pets' graph and paths and the drones.
# Vanilla refuses an offline save with a DLC keeper the Steam account doesn't
# own (SaveGame.gd, ERR_UNAUTHORIZED); `dlckeepers` (dev/dev_boot.gd) lets the
# Beastmaster's save load here anyway.


func boot() -> Dictionary:
	return {"load": PET_SLOT, "keeper": "keeper4", "dlckeepers": true}


func run(h) -> void:
	rng.seed = 3134
	map = Level.map
	td = map.tileData
	h.check("a Story Mode run came back from the save", Level.loadout != null and Level.loadout.modeId == "storymode")
	map.path_cell_closed.connect(_on_closed)
	map.tile_destroyed.connect(_on_opened)
	await h.until(func(): return _drones(h).size() >= 4, 15.0)
	h.check("the drones came back", _drones(h).size() >= 4, _drones(h).map(func(d): return {"state": d.state, "cell": map.getTileCoord(d.global_position)}))
	if _keeper4():
		goblins = Level.getDome("team1").goblins
		nav = goblins._navigator
		sampler = PetSampler.new()
		sampler.nav = nav
		h.get_tree().root.add_child(sampler)
		await h.until(func(): return _goblins().size() >= 8, 15.0)
		h.check("the pets came back", _goblins().size() >= 8, _goblins().size())
	for d in _drones(h):
		_count_home_asks(d)
	await h.teleport_tile(Vector2i(13, 8))
	await h.wait(2.0)
	await h.shot("reloaded")
	h.note("drones after the reload", _drones(h).map(func(d): return {"uid": d.UID, "state": d.state, "cell": map.getTileCoord(d.global_position), "carrying": d.carriedResource}))
	_spawn_far(6)
	await _measure(h, 10.0, "after the reload")

	h.speed(2.0)
	await _pet_churn(h, 20.0, "reloaded")
	h.enable_waves()
	GameWorld.runStarted = true
	Data.apply("team1.monsters.wavecooldown", 2)
	var came: bool = await h.until(func(): return Data.of("team1.monsters.wavepresent"), 60.0)
	h.check("a wave came after the reload", came)
	await _pet_churn(h, 15.0, "reloaded wave")
	await h.shot("reloaded_wave")
	for mm in Level.monstersByTeamId.values():
		mm.instantlyKillWave()
	await h.until(func(): return not Data.of("team1.monsters.wavepresent"), 30.0)
	h.disable_waves()
	h.speed(1.0)
	await _pet_churn(h, 4.0, "settle", false)
	var field = map.get_node_or_null("StoryLavaField")
	if field != null:
		field.magma.clear()
		field.freeze_flow = true
	for i in 24:
		if nav != null:
			nav.get_graph_generation()
		await h.wait(0.25)
	_pet_audit("end", true)
	await h.shot("end")
	_graph_check(h)
	h.check("tiles changed on drone paths", toggles >= 10, toggles)
	h.check("no drone path runs through solid rock", bad_paths.is_empty(), bad_paths.slice(0, 20))
	h.check("no drone leaves the map", off_map.is_empty(), off_map.slice(0, 10))
	if nav != null:
		h.note("pet audits", {"audits": audits, "pet toggles": pet_toggles, "cells changed": changed_ms.size(), "openings not in the graph yet (churn)": pet_graph_lagging})
		h.check("tiles changed on pet paths", pet_toggles >= 5, pet_toggles)
		h.check("no pet path runs through settled rock", pet_bad_paths.is_empty(), pet_bad_paths.slice(0, 20))
		h.check("the pets' graph has no surface in settled rock", pet_graph_rock.is_empty(), pet_graph_rock.slice(0, 20))
		h.check("once the rock stops changing, the pets' graph has a floor in every opening", pet_graph_missing.is_empty(), pet_graph_missing.slice(0, 20))
	h.check("the run is still going", is_instance_valid(map) and not GameWorld.gameover)
