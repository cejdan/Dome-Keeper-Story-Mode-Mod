extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #231: restarting a Story Mode run from the pause menu's Restart Run (the
# user saw a black screen in splitscreen). Single player here;
# t231_split_restart does the same with two local keepers.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")

# `-Extra "--welcome"`: the keeper's welcome log opens as in a real run (it
# opens again on the restarted run), and is read each time.
static func welcome() -> bool:
	return "--welcome" in OS.get_cmdline_user_args()


func boot() -> Dictionary:
	return {"welcome": welcome()}


func run(h) -> void:
	h.disable_waves()
	await h.wait(2.0)
	if welcome():
		h.check("welcome log in the first run", await h.read_beat("welcome_run1", 10.0) != "")
	await h.hold("ui_down", 2.0)
	await h.shot("before")
	await restart(h)


func restart(h) -> void:
	var before: int = Level.stage.get_instance_id()
	var seed0: int = Level.levelSeed
	h.note("keepers before", h.local_keepers().map(func(k): return [k.playerId, k.deviceId]))
	await h.press("escape")
	await h.wait(1.0)
	var menus: Array = h.get_tree().root.find_children("*", "", true, false).filter(func(n): return n.get_script() != null and n.get_script().resource_path == "res://content/pause/PauseMenu.gd")
	h.check("pause menu open", not menus.is_empty(), menus.size())
	if menus.is_empty():
		return
	await h.shot("pause_menu")
	menus[0]._on_button_restart_run_pressed()
	await h.wait(0.5)
	menus[0]._on_button_restart_run_pressed()
	var started: bool = await h.until(func(): return is_instance_valid(Level.stage) and Level.stage.get_instance_id() != before and Level.stage is LevelStage and Level.stage.get("keeperInputStarted") == true and Level.map != null and Level.map.isMapReady(), 90.0)
	h.check("new run started", started, {"stage": str(Level.stage), "seed": Level.levelSeed})
	h.mute_beats()
	h.disable_waves()
	if welcome():
		await h.wait(0.5)
		await h.shot("welcome_after_restart")
		h.check("welcome log after the restart", await h.read_beat("welcome_run2", 10.0) != "")
	await h.wait(3.0)
	h.check("new map", Level.levelSeed != seed0, [seed0, Level.levelSeed])
	h.check("story mode", Story.is_story())
	var nk: int = Keepers.getAllOfTeam("team1").size()
	h.check("no second laser until the team buys it (vanilla's Second Weapon)", not GameWorld.boughtUpgrades.has("team1.domesecondweapon") and Level.getDome("team1").stations[1].getControlledWeapons().size() == 0,
		{"keepers": nk, "station 2 lasers": Level.getDome("team1").stations[1].getControlledWeapons().size()})
	var ks: Array = h.local_keepers()
	h.note("keepers after", ks.map(func(k): return [k.playerId, k.deviceId, Level.map.getTileCoord(k.global_position)]))
	if Level.viewports != null:
		h.note("viewports after", {"ids": Level.viewports.viewportContainersByKeeperId.keys(), "split": Keepers.isSplitScreen})
		for pid in Level.viewports.viewportContainersByKeeperId:
			var vc = Level.viewports.viewportContainersByKeeperId[pid]
			h.note("view " + pid, {"visible": vc.is_visible_in_tree(), "size": vc.size, "curtain": vc._curtain.visible, "cam": str(vc.camera), "target": str(vc.camera.target) if vc.camera != null else ""})
	await h.shot("after_restart")
	await h.hold("ui_down", 2.0)
	await h.shot("after_restart_dig")
	# A screen that is all one colour is the black screen.
	var img: Image = h.get_viewport().get_texture().get_image()
	var dark := 0
	var n := 0
	for y in range(0, img.get_height(), 16):
		for x in range(0, img.get_width(), 16):
			n += 1
			if img.get_pixel(x, y).get_luminance() < 0.03:
				dark += 1
	h.check("screen not black", dark < n * 0.9, {"dark": dark, "of": n})

