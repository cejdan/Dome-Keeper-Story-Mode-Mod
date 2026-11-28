extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t347_meter.gd"

# #368: the ship in the lava ocean (huge map, seed 12345; `--mapsize=` for the
# other sizes). A third, much bigger tentacle comes up out of the deep and is
# coiled round a Halcyon pickup vessel over the chamber's middle, between the
# two climbable tentacles. Checks: one ship, held in the ocean before the last
# chain; hidden until the ocean round it has been seen; nothing of it
# collides; it fits the ocean (between the walls, under the ceiling); it sways
# slowly (measured over 12 s); the climbable tentacles and the anchors draw in
# front of it. Shots: the coil from a few spots, a burst of the sway. Then
# the frame meter (#347): the ship on screen vs the same spot with it hidden,
# twice each; far from the ocean it draws nothing.

const Ship = preload("res://mods-unpacked/flantor-StoryMode/endgame/ship.gd")
static var _Ship = Ship  # calls go through this: lazy_preload makes const-preload calls slow
const ShipData = preload("res://mods-unpacked/flantor-StoryMode/data/ship.gd")
const TIMEOUT := 300
const MAX_ADDED_MS := 0.3
const T := 24.0


func boot() -> Dictionary:
	return {"seed": 12345}


func _lean(h, k, at: Vector2) -> void:
	var cam = Level.viewports.getPlayerCam(k.playerId)
	cam.targetOffset = at - k.global_position
	h.snap_camera(k)


func run(h) -> void:
	h.disable_waves()
	await h.until(func(): return _Ship.find() != null and h.keeper() != null, 30.0)
	var ship = _Ship.find()
	if not h.check("the run has a ship", ship != null):
		return
	load("res://mods-unpacked/flantor-StoryMode/dev/boss_dev.gd").give_gear()
	var k = h.keeper()
	await h.wait(1.0)
	h.check("before the last chain it is held in the ocean", ship.mode == "ocean" and not _Ship.is_landed() and _Ship.phase() == "away", [ship.mode, _Ship.phase()])
	h.check("hidden until the ocean round it is seen", not ship.seen and not ship.ocean.visible, [ship.seen, ship.ocean.visible])
	var bodies: Array = ship.find_children("*", "CollisionObject2D", true, false)
	var areas_on: Array = bodies.filter(func(b): return b is PhysicsBody2D or (b is Area2D and b.monitorable))
	h.check("nothing of it collides (no bodies; the hatch's use area is off)", areas_on.is_empty(), bodies.map(func(b): return str(b.get_path())))
	meter_start(h)
	await h.wait(1.0)
	await measure(h, "surface (ship far)", 4.0)
	h.check("far from the ocean it is not drawn", not ship.ocean.visible, ship.ocean.visible)
	# The ocean in sight.
	var td = Level.map.tileData
	var om: Dictionary = td.get_meta("story_ocean")
	var cells: Array = []
	for y in range(int(om["ceiling"]), int(om["bottom"]) + 2):
		for x in range(int(om["x0"]) - 2, int(om["x1"]) + 3):
			cells.append(Vector2i(x, y))
	await h.reveal(cells)
	var home: Vector2 = ship.to_global(ship.ocean_home)
	var cell: Vector2i = Vector2i(Level.map.getTileCoord(home)) if Level.map.has_method("getTileCoord") else Vector2i(int(floor(home.x / T)), int(floor(home.y / T)))
	k.teleport(home + Vector2(-150, -70))
	_lean(h, k, home + Vector2(0, 30))
	await h.wait(1.5)
	h.check("seen and on a view: drawn", ship.seen and ship.ocean.visible, [ship.seen, ship.ocean.visible])
	# It fits the ocean: the hull between its walls, the coil's top under the ceiling.
	var top_y: float = Level.map.getTilePos(Vector2(0, int(om["ceiling"]))).y + T * 0.5
	var fin: Vector2 = ship._ocean_ship.to_global(Vector2(-117, -56))
	var tip: Vector2 = ship._ocean_ship.to_global(Vector2(80, -70))
	var row: int = int(om["top"])
	var rows: Dictionary = om["rows"]
	var span: Array = rows.get(row, [om["x0"], om["x1"]])
	var left: float = Level.map.getTilePos(Vector2(int(span[0]), row)).x - T * 0.5
	var right: float = Level.map.getTilePos(Vector2(int(span[1]), row)).x + T * 0.5
	var nose: Vector2 = ship._ocean_ship.to_global(Vector2(124, 0))
	var tail: Vector2 = ship._ocean_ship.to_global(Vector2(-147, 0))
	h.check("it fits the ocean: under the ceiling, between the walls", fin.y > top_y + 4.0 and tip.y > top_y + 4.0 and tail.x > left + 24.0 and nose.x < right - 24.0,
		{"ceiling_bottom": top_y, "fin": fin, "tip": tip, "walls": [left, right], "tail": tail.x, "nose": nose.x})
	# The climbable tentacles and the anchors in front of it.
	var tents = Level.map.get_node_or_null("StoryOceanTentacles")
	var anch = Level.map.get_node_or_null("StoryChainAnchors")
	var lava = Level.map.get_node_or_null("StoryLavaField")
	h.check("drawn over the lava, under the climbable tentacles and the anchors", ship.z_index == 7 and lava != null and ship.get_index() > lava.get_index()
		and (tents == null or tents.get_index() > ship.get_index()) and (anch == null or anch.get_index() > ship.get_index()),
		{"ship": [ship.z_index, ship.get_index()], "lava": [lava.z_index, lava.get_index()] if lava != null else null, "tents": tents.get_index() if tents != null else null, "anchors": anch.get_index() if anch != null else null})
	await h.shot("coil_held_ship")
	# The sway: 12 s of the ship's angle and height.
	var rots: Array = []
	var ys: Array = []
	for i in 48:
		await h.wait(0.25)
		var g: Transform2D = ship._ocean_ship.get_global_transform()
		rots.append(g.get_rotation())
		ys.append(g.origin.y)
	var rmin: float = rots.min()
	var rmax: float = rots.max()
	h.note("sway over 12 s", {"angle_deg": [rad_to_deg(rmin), rad_to_deg(rmax)], "y": [ys.min(), ys.max()]})
	h.check("it sways slowly (a few degrees, a few px, no jumps)", rmax - rmin > 0.01 and rmax - rmin < 0.12 and ys.max() - ys.min() > 1.5 and ys.max() - ys.min() < 30.0, [rmax - rmin, ys.max() - ys.min()])
	await h.burst("sway", 8, 15)
	# From the left tentacle's tip, as a climber sees it.
	if tents != null and tents.rigs.size() > 0:
		var a: Vector2 = tents.rigs[0].pad_top_now()
		k.teleport(a + Vector2(10, -20))
		_lean(h, k, (a + home) * 0.5 + Vector2(0, 20))
		await h.wait(1.0)
		await h.shot("from_left_tip")
	# Wide: the whole of it under the surface too.
	k.teleport(home + Vector2(0, -60))
	_lean(h, k, home + Vector2(0, 120))
	await h.wait(1.0)
	await h.shot("deep_root")
	_lean(h, k, home + Vector2(0, 0))
	await h.wait(1.0)
	# The frame cost: on screen vs hidden, twice each.
	for i in 2:
		ship.ocean.process_mode = Node.PROCESS_MODE_DISABLED
		ship.process_mode = Node.PROCESS_MODE_DISABLED
		ship.visible = false
		await h.wait(1.0)
		await measure(h, "ocean, ship hidden %d" % (i + 1), 5.0)
		ship.process_mode = Node.PROCESS_MODE_INHERIT
		ship.ocean.process_mode = Node.PROCESS_MODE_INHERIT
		ship.visible = true
		await h.wait(1.0)
		await measure(h, "ocean, ship on screen %d" % (i + 1), 5.0)
	# Which part costs: the node's work with the drawing hidden, the drawing
	# with the node stopped.
	ship.ocean.visible = false
	ship.ocean.process_mode = Node.PROCESS_MODE_DISABLED
	var us0: int = ship.proc_us
	await measure(h, "ocean, ship working, not drawn", 4.0)
	h.note("ship _process us per frame (not drawn)", (ship.proc_us - us0) / maxf(1.0, float(_meter.get("ocean, ship working, not drawn", {}).get("frame ms", []).size())))
	ship.ocean.process_mode = Node.PROCESS_MODE_INHERIT
	ship.process_mode = Node.PROCESS_MODE_DISABLED
	ship.ocean.visible = true
	await measure(h, "ocean, ship drawn, node stopped", 4.0)
	ship.process_mode = Node.PROCESS_MODE_INHERIT
	us0 = ship.proc_us
	await measure(h, "ocean, ship on screen 3", 4.0)
	h.note("ship _process us per frame (on screen)", (ship.proc_us - us0) / maxf(1.0, float(_meter.get("ocean, ship on screen 3", {}).get("frame ms", []).size())))
	await h.shot("coil_end")
	meter_stop()
	var rep: Dictionary = report(h)
	var on: float = (avg(rep, "ocean, ship on screen 1") + avg(rep, "ocean, ship on screen 2")) * 0.5
	var off: float = (avg(rep, "ocean, ship hidden 1") + avg(rep, "ocean, ship hidden 2")) * 0.5
	var r_on: float = (avg(rep, "ocean, ship on screen 1", "render cpu ms") + avg(rep, "ocean, ship on screen 2", "render cpu ms")) * 0.5
	var r_off: float = (avg(rep, "ocean, ship hidden 1", "render cpu ms") + avg(rep, "ocean, ship hidden 2", "render cpu ms")) * 0.5
	h.note("ship on screen: frame %.3f ms vs %.3f hidden (+%.3f); render cpu %.3f vs %.3f" % [on, off, on - off, r_on, r_off])
	h.check("on screen it adds under %.1f ms a frame (average)" % MAX_ADDED_MS, on > 0.0 and off > 0.0 and on - off < MAX_ADDED_MS, [on, off])
