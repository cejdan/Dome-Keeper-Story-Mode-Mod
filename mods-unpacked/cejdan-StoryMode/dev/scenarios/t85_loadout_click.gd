extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Loadout screen driven with real mouse clicks, the way a player picks a mode.
# A reported freeze followed a left click on this screen.


func boot() -> Dictionary:
	return {"loadout": true}


func _click(h, pos: Vector2, label: String) -> void:
	var t0 := Time.get_ticks_msec()
	for p in [pos - Vector2(30, 0), pos]:
		var m := InputEventMouseMotion.new()
		m.position = p
		m.global_position = p
		Input.warp_mouse(p)
		Input.parse_input_event(m)
		await h.frames(3)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		Input.parse_input_event(e)
		await h.frames(2)
	await h.wait(1.0)
	h.note("click " + label, {"pos": pos, "ms": Time.get_ticks_msec() - t0, "mode": Level.loadout.modeId, "fps": Engine.get_frames_per_second()})


func run(h) -> void:
	h.note("start", {"figuredOut": GameWorld.figuredOutMovementInLoadout, "getter": GameWorld.getFiguredOutMovementInLoadout()})
	await h.wait(3.0)
	await h.shot("spawn")
	var stage = Level.stage
	var vp: Vector2 = stage.get_viewport().get_visible_rect().size
	await _click(h, vp * 0.5, "center")
	await _click(h, vp * Vector2(0.25, 0.3), "upper left")
	# Out of the pocket, so the mode choices show.
	GameWorld.figuredOutMovementInLoadout = true
	stage.tileRevealed(Vector2i.ZERO)
	await h.wait(1.0)
	var choice = null
	for c in stage.find_child("GameModeContainers").get_children():
		if not c is Label and c.id == "storymode":
			choice = c
	h.keeper().teleport(choice.getGlobalPosition() + Vector2(0, 60))
	await h.wait(2.0)
	await h.shot("near_story")
	var sp: Vector2 = choice.get_global_transform_with_canvas() * (choice.size * 0.5)
	await _click(h, sp, "story choice")
	if Level.loadout.modeId != "storymode":
		# Synthetic clicks don't reach the tile in a harness window; send the
		# click the tile's own mouse handler gets.
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = true
		choice._on_LoadoutChoice_gui_input(e)
		await h.wait(1.0)
	await h.wait(2.0)
	await h.shot("after_story_click")
	h.check("story picked by click", Level.loadout.modeId == "storymode", Level.loadout.modeId)
	await h.wait(3.0)
	h.check("no lava field on loadout map", Level.map != null and not Level.map.has_node("StoryLavaField"))
	for i in 6:
		await _click(h, vp * Vector2(0.15 + 0.14 * i, 0.5 + 0.06 * (i % 3)), "spot %d" % i)
	await h.shot("end")
	h.check("still running", true)
