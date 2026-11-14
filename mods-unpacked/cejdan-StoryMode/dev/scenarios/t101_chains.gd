extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 101 (stretch): chains bind each unobtainium deposit to the boss
# chamber. Screenshots and a frame burst in the lava ocean show them swaying,
# the keeper passing through one, and a chain breaking when its deposit is
# mined. Frame time in the ocean with and without the chains. Saves to slot 15
# for t101_reload (broken chains stay broken).

const Awakening = preload("res://mods-unpacked/cejdan-StoryMode/beats/awakening.gd")

const UNOB_ID := 47


func boot() -> Dictionary:
	return {"seed": 12345}


func _frame_ms(h, frames: int) -> float:
	var t0: int = Time.get_ticks_usec()
	await h.frames(frames)
	return (Time.get_ticks_usec() - t0) / 1000.0 / frames


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	h.set_inv("money", 10000000)
	for n in range(1, 5):
		await h.buy("storyheatshield%d" % n)
	var chains = Level.map.get_node_or_null("StoryChains")
	h.check("the run has chains", chains != null and chains.chains.size() > 0, chains.chains.size() if chains else 0)
	var td = Level.map.tileData
	var field = Level.map.get_node_or_null("StoryLavaField")
	h.check("chains stay hidden until the ocean is seen", chains.shown() == 0, chains.shown())
	# Breach: reveal the ocean and the chamber, as breaking into it does.
	var ocean: Dictionary = td.get_meta("story_ocean")
	var room: Rect2i = td.get_meta("story_boss_chamber")
	var cells: Array = []
	for y in range(int(ocean["ceiling"]), room.end.y + 1):
		for x in range(int(ocean["x0"]), int(ocean["x1"]) + 1):
			cells.append(Vector2i(x, y))
	await h.reveal(cells)
	await h.wait(1.6)
	h.check("every chain shows once the ocean is seen", chains.shown() == chains._all.size(), [chains.shown(), chains._all.size()])
	# A deposit near the middle, and the keeper floating above it in the lava.
	var dep: Dictionary = {}
	var best: float = 1e9
	for ch in chains.chains:
		var d: float = absf(ch["a"].x)
		if d < best:
			best = d
			dep = ch
	var cell: Vector2i = dep["cells"][0]
	var trunk: Dictionary = chains.trunks[dep["knot"]]
	h.note("chain", {"deposit": dep["cells"], "a": dep["a"], "knot": dep["b"], "roof": trunk["b"], "knots": chains.trunks.size(), "siblings": trunk["members"].size()})
	var mid: Vector2 = (dep["a"] + dep["b"]) / 2.0
	await h.reveal(dep["cells"])
	h.keeper().teleport(dep["a"] + Vector2(0, -40))
	h.snap_camera()
	await h.wait(1.0)
	if field != null:
		field.heat = 0.0
	await h.shot("chains_in_ocean")
	await h.burst("sway", 16, 6)
	# Where they meet: the chamber's roof.
	h.keeper().teleport(trunk["b"] + Vector2(0, -90))
	h.snap_camera()
	await h.wait(1.0)
	if field != null:
		field.heat = 0.0
	await h.shot("chamber_roof")
	h.keeper().teleport(dep["a"] + Vector2(-260, -40))
	h.snap_camera()
	await h.wait(1.0)
	if field != null:
		field.heat = 0.0
	await h.shot("ocean_wide")
	# The keeper passes through a chain: no collision.
	var from: Vector2 = mid + Vector2(-60, 0)
	h.keeper().teleport(from)
	h.snap_camera()
	await h.wait(0.3)
	h.down("ui_right")
	await h.wait(1.6)
	h.up("ui_right")
	if field != null:
		field.heat = 0.0
	var crossed: bool = h.keeper().global_position.x > mid.x + 10.0
	await h.shot("keeper_through_chain")
	h.check("the keeper passes through a chain", crossed, [from.x, h.keeper().global_position.x, mid.x])
	# Frame time in the ocean, chains on and off.
	h.keeper().teleport(dep["a"] + Vector2(0, -40))
	h.snap_camera()
	await h.wait(1.0)
	var on: float = await _frame_ms(h, 120)
	chains.visible = false
	chains.set_process(false)
	var off: float = await _frame_ms(h, 120)
	chains.visible = true
	chains.set_process(true)
	var on2: float = await _frame_ms(h, 120)
	h.note("frame ms in the ocean", {"chains on": on, "off": off, "on again": on2, "drawn": chains.draw_count})
	h.check("frame time with chains is no worse than without (within 10%% or 0.5 ms)", minf(on, on2) <= off * 1.1 + 0.5, [on, off, on2])
	# Mine the deposit: its chain breaks.
	var n0: int = chains.intact()
	for c in dep["cells"]:
		if td.get_resourcev(c) == UNOB_ID:
			Level.map.destroyTile("team1", "", Level.map.getTile(Vector2(c)))
	if field != null:
		field.heat = 0.0
	await h.burst("snap", 14, 4)
	await h.wait(2.5)
	await h.shot("after_snap")
	h.check("mining the deposit breaks its chain", dep["broken"] and chains.intact() == n0 - 1, [n0, chains.intact()])
	h.check("its knot holds while it has other deposits", trunk["broken"] == (trunk["members"].size() == 1), trunk["members"].size())
	# Mine the knot's other deposits: its trunk snaps off the roof.
	for i in trunk["members"]:
		for c in chains.chains[i]["cells"]:
			if td.get_resourcev(c) == UNOB_ID:
				Level.map.destroyTile("team1", "", Level.map.getTile(Vector2(c)))
	h.keeper().teleport(trunk["a"] + Vector2(0, -60))
	h.snap_camera()
	if field != null:
		field.heat = 0.0
	await h.burst("trunk_snap", 12, 5)
	await h.wait(2.5)
	await h.shot("after_trunk_snap")
	h.check("a knot's trunk snaps when its last deposit goes", trunk["broken"], trunk["members"].size())
	await SaveGame.saveGame("singleplayer", 15, true)
	await h.wait(1.0)
	h.note("saved slot 15", {"intact": chains.intact(), "of": chains.chains.size(), "broken cell": cell})
