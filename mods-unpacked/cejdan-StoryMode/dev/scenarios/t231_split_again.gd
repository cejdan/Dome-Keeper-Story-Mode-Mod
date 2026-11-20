extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# #231: a splitscreen Story Mode run is lost; the end screen's Another Run goes
# back to the loadout, and a second run starts from there with both keepers
# (the user saw a black screen restarting a run). `-Extra "--single"` does the
# same with one keeper.

const TIMEOUT := 420
const Split = preload("res://mods-unpacked/cejdan-StoryMode/dev/scenarios/t231_split_restart.gd")


func boot() -> Dictionary:
	return {"loadout": true, "splitscreen": not _single()}


static func _single() -> bool:
	return "--single" in OS.get_cmdline_user_args()


func run(h) -> void:
	var want: int = 1 if _single() else 2
	if _single():
		GameWorld.figuredOutMovementInLoadout = true
		Level.stage.gameModeSelected("storymode")
		await h.wait(1.5)
		Level.stage.startRun()
		if not h.check("run started", await h.until(func(): return Level.stage is LevelStage and Level.stage.get("keeperInputStarted") == true and Level.map != null and Level.map.isMapReady(), 180.0)):
			return
		h.mute_beats()
		h.disable_waves()
	elif not await Split.start_split(h):
		return
	await h.wait(2.0)
	await h.shot("run1")
	Data.apply("team1.dome.health", 0)
	var panel: bool = await h.until(func(): return Level.stage.endingPanel != null, 40.0)
	h.check("end screen", panel and GameWorld.lost)
	await h.wait(4.0)
	await h.shot("end_screen")
	var popup = Level.stage.endingPanel
	var buttons: Dictionary = {}
	for b in ["mainMenuButton", "anotherRunButton", "mineViewButton"]:
		buttons[b] = popup.get(b).visible if popup.get(b) != null else null
	h.note("end screen buttons", buttons)
	var st: int = Level.stage.get_instance_id()
	popup._on_AnotherRunButton_pressed()
	var loadout: bool = await h.until(func(): return is_instance_valid(Level.stage) and Level.stage.get_instance_id() != st and Level.stage is MultiplayerLoadoutStage and Level.stage.get("initialized") == true, 60.0)
	h.check("back in the loadout", loadout, str(Level.stage))
	await h.wait(3.0)
	h.note("loadout keepers", {"local": h.local_keepers().map(func(k): return [k.playerId, k.deviceId]), "loadout": Level.loadout.keepers.map(func(lk): return [lk.playerId, lk.deviceId]), "lobby": h.lobby_rows(), "split": Keepers.isSplitScreen, "mode": Network.multiplayer_mode})
	await h.shot("loadout_again")
	_dark(h, "loadout not black")
	h.check("every keeper back in the loadout", h.local_keepers().size() == want, h.local_keepers().size())
	Level.stage.gameModeSelected("storymode")
	await h.wait(1.5)
	var st2: int = Level.stage.get_instance_id()
	Level.stage.startRun()
	var started: bool = await h.until(func(): return is_instance_valid(Level.stage) and Level.stage.get_instance_id() != st2 and Level.stage is LevelStage and Level.stage.get("keeperInputStarted") == true and Level.map != null and Level.map.isMapReady(), 180.0)
	h.check("second run started", started, str(Level.stage))
	if not started:
		await h.shot("second_run_failed")
		return
	h.mute_beats()
	h.disable_waves()
	await h.wait(3.0)
	h.check("second run: every keeper", h.local_keepers().size() == want, h.local_keepers().map(func(k): return [k.playerId, k.deviceId]))
	if Level.viewports != null:
		h.note("views", Level.viewports.viewportContainersByKeeperId.keys())
	await h.shot("run2")
	await h.hold("ui_down", 2.0)
	await h.shot("run2_dig")
	_dark(h, "run 2 not black")


func _dark(h, label: String) -> void:
	var img: Image = h.get_viewport().get_texture().get_image()
	var dark := 0
	var n := 0
	for y in range(0, img.get_height(), 16):
		for x in range(0, img.get_width(), 16):
			n += 1
			if img.get_pixel(x, y).get_luminance() < 0.03:
				dark += 1
	h.check(label, dark < n * 0.9, {"dark": dark, "of": n})
