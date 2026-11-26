extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 361: Velle's chamber in living stone. Checks the map (walls, floor
# and roof undrillable, the roof's four entry tiles left as drillable crust),
# that the stone node is built and stays hidden until the chamber is seen,
# that drilling and explosions don't break the stone while an entry tile does
# break, and that charges never spawn inside a stalactite. Shots of the chamber
# before and during the fight, and a burst of the tentacles moving.

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const LavaData = preload("res://mods-unpacked/flantor-StoryMode/data/lava.gd")
static var _LavaData = LavaData  # calls go through this: lazy_preload makes const-preload calls slow
const TIMEOUT := 300


func boot() -> Dictionary:
	return {"seed": 12345}


func _tile_ok(td, c: Vector2i, want_border: bool) -> bool:
	var border: bool = td.get_resourcev(c) == Data.TILE_BORDER and td.get_hardnessv(c) == Data.HARDNESS_INDESTRUCTIBLE
	return border == want_border


var _far := Vector2i.ZERO


# Is the far entry (the right one, never drilled here) still shut?
func _far_shut(h, when: String) -> void:
	var shut: bool = not Level.map.is_tile_empty(_far)
	h.note("far entry %s: %s" % [when, "shut" if shut else "OPEN"])


func run(h) -> void:
	h.disable_waves()
	Data.apply("team1.story.awake", false)   # Velle sleeps through the map checks
	var td = Level.map.tileData
	var ch: Rect2i = td.get_meta("story_boss_chamber")
	var wall: int = _LavaData.BOSS_CHAMBER_WALL
	h.note("chamber", {"rect": [ch.position.x, ch.position.y, ch.size.x, ch.size.y]})
	_far = Vector2i(ch.position.x + _LavaData.BOSS_CHAMBER_ENTRY[2], ch.position.y - 1)
	_far_shut(h, "at start")

	# ---- the map
	var bad: Array = []
	for y in range(ch.position.y, ch.end.y + wall):
		for x in range(ch.position.x - wall, ch.end.x + wall):
			var c := Vector2i(x, y)
			if not ch.has_point(c) and not _tile_ok(td, c, true):
				bad.append(c)
	h.check("the chamber's walls and floor are undrillable", bad.is_empty(), bad.slice(0, 6))
	var roof_bad: Array = []
	for x in range(ch.position.x - wall, ch.end.x + wall):
		var c := Vector2i(x, ch.position.y - 1)
		var entry: bool = (x - ch.position.x) in _LavaData.BOSS_CHAMBER_ENTRY
		if not _tile_ok(td, c, not entry):
			roof_bad.append(c)
	h.check("the roof is undrillable except its four entry tiles", roof_bad.is_empty(), roof_bad)
	var inside_empty: bool = true
	for y in range(ch.position.y, ch.end.y):
		for x in range(ch.position.x, ch.end.x):
			if td.get_resourcev(Vector2i(x, y)) != Data.TILE_EMPTY:
				inside_empty = false
	h.check("the chamber's inside is still open", inside_empty)

	# ---- the stone node
	var stone = Level.map.get_node_or_null("StoryChamberStone")
	if not h.check("the chamber stone is built", stone != null):
		return
	h.check("it has 14 bodies (2 steps, 2 stumps, 10 stalactites)", stone.bodies.size() == 14, stone.bodies.size())
	h.check("it is hidden before the chamber is seen", not stone.visible)

	var area: Array = []
	for y in range(ch.position.y - 4, ch.end.y + wall + 1):
		for x in range(ch.position.x - wall - 1, ch.end.x + wall + 1):
			area.append(Vector2i(x, y))
	await h.reveal(area)
	await h.teleport_tile(ch.position + Vector2i(2, ch.size.y - 1))
	await h.wait(1.5)
	h.check("it shows once the chamber is seen", stone.visible)
	_far_shut(h, "after the reveal")
	h.note("fight state after the reveal", {"director": _Director.current()})
	await h.shot("chamber_quiet")

	# ---- the keeper stands on the floor, drills down: the floor holds
	var k = h.keeper()
	var below: Vector2i = h.keeper_tile() + Vector2i(0, 1)
	h.note("standing", {"keeper tile": h.keeper_tile(), "below": below})
	await h.hold("ui_down", 3.0)
	h.check("drilling down doesn't break the living-stone floor", not Level.map.is_tile_empty(below), below)

	# ---- explosions on the wall, the floor and a stalactite's roof tile
	var hits: Array = [ch.position + Vector2i(-1, 4), Vector2i(ch.position.x + 8, ch.end.y), Vector2i(ch.position.x + 11, ch.position.y - 1)]
	for c: Vector2i in hits:
		Level.map.damageTileCircleArea(Level.map.getTilePos(Vector2(c)), 2.0, 9999.0, "team1")   # radius in tiles
	await h.wait(1.0)
	var broken: Array = hits.filter(func(c): return Level.map.is_tile_empty(c))
	h.check("big explosions don't break the wall, floor or roof", broken.is_empty(), broken)
	var soft := Vector2i(ch.position.x + _LavaData.BOSS_CHAMBER_ENTRY[1], ch.position.y - 1)
	Level.map.damageTileCircleArea(Level.map.getTilePos(Vector2(soft)), 0.5, 9999.0, "team1")
	await h.wait(0.5)
	h.check("the same explosion on an entry tile breaks it", Level.map.is_tile_empty(soft), soft)
	_far_shut(h, "after the explosions")

	# ---- an entry tile drills from below
	var entry := Vector2i(ch.position.x + _LavaData.BOSS_CHAMBER_ENTRY[0], ch.position.y - 1)
	var shut := Vector2i(ch.position.x + 9, ch.position.y - 1)
	await h.teleport_tile(shut + Vector2i(0, 1))
	await h.hold("ui_up", 3.0)
	h.check("drilling up into the roof away from the entry does nothing", not Level.map.is_tile_empty(shut), shut)
	await h.teleport_tile(entry + Vector2i(0, 1))
	await h.hold("ui_up", 4.0)
	h.check("an entry tile drills open", Level.map.is_tile_empty(entry), entry)
	_far_shut(h, "after drilling the near entry")
	await h.shot("entry_open")
	await h.teleport_tile(ch.position + Vector2i(2, ch.size.y - 1))
	await h.wait(1.0)

	# ---- the fight: charges never start inside a stalactite
	Data.apply("team1.story.awake", true)
	var started: bool = await h.until(func(): return _Director.current() == "fight", 8.0)
	if not h.check("the fight starts", started, _Director.current()):
		return
	var velle = _Director.instance().velle
	velle.attack_enabled = false
	await h.until(func(): return velle.state == "fight", 8.0)
	await h.wait(1.5)
	var in_stone: int = 0
	var xs: Array = []
	for i in 400:
		var x: float = velle._bomb_x()
		xs.append(x)
		if velle._in_stone(x) or absf(x - velle.base.x) <= 78.0:
			in_stone += 1
	h.check("400 charge spots: none in a stalactite or over Velle", in_stone == 0, in_stone)
	var spread: float = xs.max() - xs.min()
	h.check("charge spots still spread across the chamber", spread > 300.0, spread)
	await h.wait(6.0)
	var lying: Array = []
	for b in velle.bombs:
		if is_instance_valid(b):
			lying.append(stone.to_local(b.global_position))
	h.note("charges after a while (stone-local)", {"at": lying})
	h.check("the other entry stays shut through all of it", not Level.map.is_tile_empty(_far), _far)
	await h.shot("fight")
	await h.burst("tentacles", 12, 3)

	# ---- frame cost: the same view with the stone shown and hidden
	velle.spawn_bombs = false
	var cost: Dictionary = {}
	for shown in [false, true, false, true, false, true]:
		stone.visible = shown
		await h.frames(30)
		var proc: float = 0.0
		var calls: float = 0.0
		for i in 120:
			await h.frames(1)
			proc += Performance.get_monitor(Performance.TIME_PROCESS)
			calls += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var key: String = "shown" if shown else "hidden"
		cost[key + "_process_ms"] = cost.get(key + "_process_ms", 0.0) + proc / 120.0 * 1000.0 / 3.0
		cost[key + "_draw_calls"] = cost.get(key + "_draw_calls", 0.0) + calls / 120.0 / 3.0
	stone.visible = true
	h.note("frame cost", cost)
	# Whole-frame times swing by milliseconds with Velle's fight in the view, so
	# time the node's own per-frame work directly.
	var t0: int = Time.get_ticks_usec()
	for i in 2000:
		stone._process(1.0 / 60.0)
	var per_frame_us: float = float(Time.get_ticks_usec() - t0) / 2000.0
	h.note("chamber stone _process", {"us_per_frame": per_frame_us, "extra_draw_calls": cost["shown_draw_calls"] - cost["hidden_draw_calls"]})
	h.check("the stone's own work is under 20 us a frame", per_frame_us < 20.0, per_frame_us)
	h.check("and it costs at most 3 draw calls", cost["shown_draw_calls"] - cost["hidden_draw_calls"] <= 3.0, cost)
