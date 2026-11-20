extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #231: the user's black screen, the way the user got there (their dev log of
# 2026-11-17 08:05): the title's Splitscreen button, two devices join, Story
# Mode, the run is lost, the end screen's Another Run (pressed as a button)
# goes back to the loadout, and a second run starts. Every screen on the way
# is shot and checked for black. `-Extra "--single"`: the title's Singleplayer
# button instead; `-Extra "--vanilla"`: Relic Hunt, for comparison.

const TIMEOUT := 480


func boot() -> Dictionary:
	return {"title": true}


static func _arg(a: String) -> bool:
	return a in OS.get_cmdline_user_args()


func run(h) -> void:
	var single: bool = _arg("--single")
	var mode: String = "relichunt" if _arg("--vanilla") else "storymode"
	var want: int = 1 if single else 2
	await h.wait(1.0)
	await h.shot("title")
	var title = StageManager.currentStage
	if single:
		title._on_singleplayer_button_pressed()
	else:
		title._on_splitscreen_button_pressed()
	var in_loadout: bool = await h.until(func(): return StageManager.currentStage is MultiplayerLoadoutStage and StageManager.currentStage.get("initialized") == true, 30.0)
	h.check("loadout from the title", in_loadout, str(StageManager.currentStage))
	if not in_loadout:
		return
	GameWorld.figuredOutMovementInLoadout = true
	await h.wait(1.0)
	if not single:
		h.check("keyboard joined", await h.join_device(0))
		h.check("gamepad joined", await h.join_device(1))
	await h.shot("loadout1")
	if not await _start(h, mode, want, "run1"):
		return
	await h.wait(2.0)
	await h.shot("run1")
	Data.apply("team1.dome.health", 0)
	var panel: bool = await h.until(func(): return Level.stage.endingPanel != null and Level.stage.endingPanel.get("isIn") == true, 40.0)
	h.check("end screen", panel and GameWorld.lost)
	await h.wait(4.0)
	await h.shot("end_screen")
	var popup = Level.stage.endingPanel
	var st: int = Level.stage.get_instance_id()
	# Press Another Run as a player does: focus it and press A on the gamepad
	# (Enter on the keyboard in single player).
	if popup.anotherRunButton.visible:
		popup.anotherRunButton.grab_focus()
		await h.wait(0.3)
		if single:
			await h.press("ui_accept")
		else:
			await h.pad_press(1, "ui_accept")
	var left: bool = await h.until(func(): return StageManager.isSwitchingStage() or not is_instance_valid(Level.stage) or Level.stage.get_instance_id() != st, 3.0)
	h.note("Another Run pressed by input", left)
	if not left:
		popup._on_AnotherRunButton_pressed()
	var back: bool = await h.until(func(): return is_instance_valid(StageManager.currentStage) and StageManager.currentStage is MultiplayerLoadoutStage and StageManager.currentStage.get("initialized") == true, 60.0)
	h.check("back in the loadout", back, str(StageManager.currentStage))
	for i in 4:
		await h.wait(1.0)
		await h.shot("loadout2_%d" % i)
	_dark(h, "loadout after Another Run is not black")
	h.note("loadout 2", {"local": h.local_keepers().map(func(k): return [k.playerId, k.deviceId]), "lobby": h.lobby_rows(), "loadout": Level.loadout.keepers.map(func(lk): return [lk.playerId, lk.deviceId, lk.keeper != null]), "split": Keepers.isSplitScreen, "mode": Network.multiplayer_mode})
	h.check("every keeper back in the loadout", h.local_keepers().size() == want, h.local_keepers().size())
	if not await _start(h, mode, want, "run2"):
		return
	await h.wait(3.0)
	await h.shot("run2")
	_dark(h, "second run is not black")


func _start(h, mode: String, want: int, label: String) -> bool:
	var stage = StageManager.currentStage
	stage.gameModeSelected(mode)
	await h.wait(1.5)
	var st: int = stage.get_instance_id()
	stage.startRun()
	var started: bool = await h.until(func(): return is_instance_valid(Level.stage) and Level.stage.get_instance_id() != st and Level.stage is LevelStage and Level.stage.get("keeperInputStarted") == true and Level.map != null and Level.map.isMapReady(), 180.0)
	if not h.check(label + " started", started, str(Level.stage)):
		await h.shot(label + "_failed")
		_dark(h, label + " screen")
		return false
	h.mute_beats()
	h.disable_waves()
	h.check(label + ": every keeper", h.local_keepers().size() == want, h.local_keepers().map(func(k): return [k.playerId, k.deviceId]))
	return true


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
