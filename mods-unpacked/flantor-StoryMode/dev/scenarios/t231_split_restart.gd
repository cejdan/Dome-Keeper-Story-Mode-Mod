extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t231_restart.gd"

# #231: Restart Run in a splitscreen Story Mode run (two local keepers).

const TIMEOUT := 360


func boot() -> Dictionary:
	return {"loadout": true, "splitscreen": true, "welcome": welcome()}


func run(h) -> void:
	if not await start_split(h):
		return
	if welcome():
		h.check("welcome log in the first run", await h.read_beat("welcome_run1", 10.0) != "")
	await h.hold("ui_down", 2.0)
	await h.pad_stick(1, Vector2(0.4, 1), 2.0)
	await h.shot("before")
	await restart(h)
	h.check("two local keepers after the restart", h.local_keepers().size() == 2, h.local_keepers().map(func(k): return k.playerId))


# Two devices join in the splitscreen loadout and start a Story Mode run.
# `keepers`: each local keeper's keeper, in loadout order (#297); the Engineer
# for both by default, as every Story run had before #297.
static func start_split(h, keepers: Array = ["keeper1", "keeper1"]) -> bool:
	GameWorld.figuredOutMovementInLoadout = true
	if not h.check("keyboard joined", await h.join_device(0)):
		return false
	if not h.check("gamepad joined", await h.join_device(1)):
		return false
	await h.wait(1.0)
	Level.stage.gameModeSelected("storymode")
	await h.wait(1.5)
	var i: int = 0
	for lk in Level.loadout.keepers.duplicate():
		if i < keepers.size() and lk.keeperId != keepers[i]:
			Level.stage.changeKeeper(lk.playerId, keepers[i] + "-skin0")
		i += 1
	var picked: bool = await h.until(func():
		for j in mini(keepers.size(), Level.loadout.keepers.size()):
			var lk2 = Level.loadout.keepers[j]
			if lk2.keeperId != keepers[j] or lk2.keeper == null or lk2.keeper.techId != keepers[j]:
				return false
		return true, 20.0)
	if not h.check("keepers picked: %s" % str(keepers), picked, Level.loadout.keepers.map(func(lk): return [lk.playerId, lk.keeperId])):
		return false
	await h.wait(1.0)
	Level.stage.startRun()
	var started: bool = await h.until(func(): return Level.stage is LevelStage and Level.stage.get("keeperInputStarted") == true and Level.map != null and Level.map.isMapReady(), 180.0)
	if not h.check("splitscreen run started", started):
		return false
	h.mute_beats()
	h.disable_waves()
	await h.wait(2.0)
	return h.check("two local keepers", h.local_keepers().size() == 2, h.local_keepers().map(func(k): return [k.playerId, k.deviceId]))
