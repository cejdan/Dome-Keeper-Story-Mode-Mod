extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #231 spike: a splitscreen Story Mode run from the loadout. The keyboard and
# one gamepad join, Story Mode is picked and the run starts; both keepers move.

const TIMEOUT := 300


func boot() -> Dictionary:
	return {"loadout": true, "splitscreen": true}


func run(h) -> void:
	var stage = Level.stage
	GameWorld.figuredOutMovementInLoadout = true
	h.note("mode", {"multiplayer_mode": Network.multiplayer_mode, "split": GameWorld.isSplitScreen()})
	h.check("keyboard joined", await h.join_device(0), h.local_keepers().map(func(k): return [k.playerId, k.deviceId]))
	h.check("gamepad joined", await h.join_device(1), h.local_keepers().map(func(k): return [k.playerId, k.deviceId]))
	await h.wait(1.0)
	await h.shot("loadout_two")
	stage.gameModeSelected("storymode")
	await h.wait(2.0)
	h.check("story mode selected", Level.loadout.modeId == "storymode", Level.loadout.modeId)
	h.note("loadout keepers", Level.loadout.keepers.map(func(lk): return {"player": lk.playerId, "device": lk.deviceId, "keeper": lk.keeperId}))
	await h.shot("loadout_storymode")
	stage.startRun()
	var started: bool = await h.until(func(): return Level.stage is LevelStage and Level.stage.get("keeperInputStarted") == true and Level.map != null and Level.map.isMapReady(), 180.0)
	h.check("run started", started)
	if not started:
		return
	h.mute_beats()
	h.disable_waves()
	await h.wait(2.0)
	var ks: Array = h.local_keepers()
	h.check("two local keepers", ks.size() == 2, ks.map(func(k): return [k.playerId, k.deviceId]))
	h.note("viewports", Level.viewports.viewportContainersByKeeperId.keys())
	h.note("split", Keepers.isSplitScreen)
	await h.shot("start")
	await h.hold("ui_right", 0.4)
	await h.pad_stick(1, Vector2(-1, 0), 0.6)
	await h.hold("ui_down", 3.0)
	await h.pad_stick(1, Vector2(0, 1), 4.0)
	await h.wait(0.5)
	for k in ks:
		h.note("keeper " + k.playerId, {"tile": Level.map.getTileCoord(k.global_position), "dome": k.isInsideDome})
	await h.shot("both_dug")
