extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# #223: the host half of an online Story Mode session on this machine. Hosts
# an ENet session, waits in the loadout for t223_mp_client to join, starts a
# Story Mode run, plays a little, and stays up until the client leaves.
# Run both with dev/mp_playtest.ps1 t223_mp_host t223_mp_client.

const TIMEOUT := 420


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	var stage = Level.stage
	GameWorld.figuredOutMovementInLoadout = true
	var joined: bool = await h.until(func(): return Lobby.members.size() >= 2, 120.0)
	h.check("client joined the lobby", joined, Lobby.members.size())
	if not joined:
		return
	var spawned: bool = await h.until(func():
		if Level.loadout.keepers.size() < 2:
			return false
		for lk in Level.loadout.keepers:
			if lk.keeper == null:
				return false
		return true, 30.0)
	h.check("both loadout keepers spawned", spawned, Level.loadout.keepers.size())
	stage.gameModeSelected("storymode")
	await h.wait(2.0)
	h.check("story mode selected", Level.loadout.modeId == "storymode", Level.loadout.modeId)
	await h.shot("loadout_storymode")
	h.note("loadout keepers", Level.loadout.keepers.map(func(lk): return {"player": lk.playerId, "peer": lk.peerId, "keeper": lk.keeperId}))
	stage.startRun()
	var started: bool = await h.until(func(): return Level.stage is LevelStage and Level.stage.get("keeperInputStarted") == true and Level.map != null and Level.map.isMapReady(), 180.0)
	h.check("run started", started)
	if not started:
		return
	h.mute_beats()
	h.disable_waves()
	await h.wait(2.0)
	_keepers(h, "level start")
	h.check("two keepers in the run", Keepers.getAll().size() == 2, Keepers.getAll().size())
	h.check("lava field", Level.map.has_node("StoryLavaField"))
	h.check("gas field", Level.map.has_node("StoryGasField"))
	h.snap("start", ["team1.inventory.money"])
	await h.shot("start")
	await h.hold("ui_right", 0.3)
	await h.hold("ui_down", 8.0)
	await h.shot("host_dug")
	_keepers(h, "host dug")
	# Give the client time to play its half.
	for i in 6:
		await h.wait(10.0)
		await h.shot("host_t%02d" % i)
		_keepers(h, "host t%d" % i)
		if Network.clients.is_empty():
			break
	var left: bool = await h.until(func(): return Network.clients.is_empty(), 120.0)
	h.note("client left", left)
	h.snap("end", ["team1.inventory.money"])


func _keepers(h, label: String) -> void:
	var rows: Array = []
	for k in Keepers.getAll():
		rows.append({"player": k.playerId, "peer": k.peerId, "device": k.deviceId, "tile": Level.map.getTileCoord(k.global_position)})
	h.note(label + ": keepers", rows)
