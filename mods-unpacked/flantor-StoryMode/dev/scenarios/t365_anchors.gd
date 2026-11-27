extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #365: the chain anchors in a real run (huge map, seed 12345). No
# Unobtainium; ten anchors, five per tentacle, each a 2 x 2 block of anchor
# tiles with a chain to its tentacle, hidden until the ocean is seen. Then the
# anchors break one by one: the first by the Engineer's own drill (pushing
# into it), the next five by hits on one of their tiles (the four tiles share
# every hit). After each: the count, the record, the live chain event, the
# tentacles' wake. Frame cost with the anchors on screen against them
# switched off. Saves to slot 40 with six broken for t365_reload.
# Shots: the ocean round each tentacle, a drilling burst (cracks, the jolt),
# a break burst (flash, chunks, the chain whipping back), after six.

const EndGame = preload("res://mods-unpacked/flantor-StoryMode/endgame/end_game.gd")
static var _EndGame = EndGame  # calls go through this: lazy_preload makes const-preload calls slow
const Anchors = preload("res://mods-unpacked/flantor-StoryMode/map/chain_anchors.gd")
static var _Anchors = Anchors  # calls go through this: lazy_preload makes const-preload calls slow
const Ocean = preload("res://mods-unpacked/flantor-StoryMode/map/ocean_tentacles.gd")
static var _Ocean = Ocean  # calls go through this: lazy_preload makes const-preload calls slow
const AnchorData = preload("res://mods-unpacked/flantor-StoryMode/data/anchors.gd")
const Awakening = preload("res://mods-unpacked/flantor-StoryMode/beats/awakening.gd")
static var _Awakening = Awakening  # calls go through this: lazy_preload makes const-preload calls slow

const TIMEOUT := 600
const SLOT := 40

var lava
var anchors
var tents
var chain_events: Array = []
var last_events: int = 0


func boot() -> Dictionary:
	return {"seed": 12345, "boss": false}


# --- shared with t365_reload, t365_keepers, t365_mp_* ------------------------------

func cool(h) -> void:
	if lava != null:
		for k in h.local_keepers():
			lava.set_heat_of(k, 0.0)


func setup(h) -> bool:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	var ok: bool = await h.until(func(): return _Anchors.find() != null and _Ocean.find() != null and h.keeper() != null, 30.0)
	if not h.check("the run has chain anchors and tentacles", ok):
		return false
	await h.wait(1.0)
	anchors = _Anchors.find()
	tents = _Ocean.find()
	lava = Level.map.get_node_or_null("StoryLavaField")
	h.disable_waves()
	if not Network.is_client():
		load("res://mods-unpacked/flantor-StoryMode/dev/boss_dev.gd").give_gear()
	_EndGame.node().chain_broken.connect(func(id, n): chain_events.append([id, n]))
	_EndGame.node().last_chain_broken.connect(func(): last_events += 1)
	return true


# Every cell of the ocean and the chamber, as breaking in does.
func reveal_ocean(h) -> void:
	var td = Level.map.tileData
	var ocean: Dictionary = td.get_meta("story_ocean")
	var room: Rect2i = td.get_meta("story_boss_chamber")
	var cells: Array = []
	for y in range(int(ocean["ceiling"]), room.end.y + 1):
		for x in range(int(ocean["x0"]) - 2, int(ocean["x1"]) + 3):
			cells.append(Vector2i(x, y))
	await h.reveal(cells)
	await h.wait(1.2)


# An open cell next to anchor `a` (the side nearest its tentacle first) and
# the direction from it into the anchor, or {}.
func stand_by(a: Dictionary) -> Dictionary:
	var td = Level.map.tileData
	var cell: Vector2i = a["cell"]
	var toward: float = -signf(a["side"])
	var tries: Array = []
	for dy in [0, 1]:
		tries.append([cell + Vector2i(-1 if toward < 0 else 2, dy), Vector2(-toward, 0)])
	for dy in [0, 1]:
		tries.append([cell + Vector2i(2 if toward < 0 else -1, dy), Vector2(toward, 0)])
	for dx in [0, 1]:
		tries.append([cell + Vector2i(dx, -1), Vector2(0, 1)])
		tries.append([cell + Vector2i(dx, 2), Vector2(0, -1)])
	for t in tries:
		var c: Vector2i = t[0]
		if td.get_resourcev(c) == Data.TILE_EMPTY and td.get_biomev(c) >= 0:
			return {"cell": c, "dir": t[1]}
	return {}


func dir_action(d: Vector2) -> String:
	if d.x > 0.5:
		return "ui_right"
	if d.x < -0.5:
		return "ui_left"
	return "ui_down" if d.y > 0.0 else "ui_up"


# Breaks anchor `a` by hits on one of its tiles (the shared damage path).
# Returns whether the four tiles' health stayed equal on the way.
func hit_break(h, a: Dictionary) -> bool:
	var equal: bool = true
	var c: Vector2i = a["cells"][0]
	if not Level.map.tiles.has(Vector2(c)):
		Level.map.revealTile(Vector2(c))
	for i in 12:
		var t = Level.map.tiles.get(Vector2(c))
		if t == null or not is_instance_valid(t) or t.health <= 0:
			if i == 0:
				h.note("anchor %d: no tile to hit at %s" % [a["id"], c])
			break
		var lethal: bool = t.health <= t.max_health * 0.3
		t.hit(Vector2.RIGHT, t.max_health * 0.3, "team1", "keeper1")
		if not lethal:
			for o in a["cells"]:
				var u = Level.map.tiles.get(Vector2(o))
				if u == null or not is_instance_valid(u) or absf(u.health - t.health) > 0.01:
					equal = false
		await h.wait(0.15)
	await h.until(func(): return a["broken"], 3.0)
	return equal


func look_at(h, at: Vector2) -> void:
	h.keeper().teleport(at)
	tents.refresh_near()
	h.snap_camera()
	await h.wait(0.6)
	cool(h)


# --- the run ----------------------------------------------------------------------

func run(h) -> void:
	if not await setup(h):
		return
	var td = Level.map.tileData
	h.check("no unobtainium tile on the map", td.get_resource_cells_by_id(47).is_empty(), td.get_resource_cells_by_id(47).size())
	h.check("ten anchors", anchors.anchors.size() == 10, anchors.anchors.size())
	var per: Dictionary = {}
	var full: bool = true
	for a in anchors.anchors:
		per[a["tentacle"]] = int(per.get(a["tentacle"], 0)) + 1
		for c in a["cells"]:
			full = full and td.get_resourcev(c) == AnchorData.TILE_ID
	h.check("five per tentacle", per.get(0, 0) == 5 and per.get(1, 0) == 5, per)
	h.check("each anchor is a full block of anchor tiles", full)
	h.check("nothing broken at the start", _EndGame.chains_broken() == 0 and not _EndGame.is_free() and _Ocean.chains_broken() == 0, _EndGame.state())
	h.check("the anchors are hidden until the ocean is seen", anchors.anchors.all(func(a): return not a["seen"]))
	await reveal_ocean(h)
	h.check("every anchor shows once the ocean is seen", anchors.anchors.all(func(a): return a["seen"]))
	# The look: each tentacle with its anchors.
	for ti in 2:
		var r = tents.rigs[ti]
		var mid: Vector2 = Vector2.ZERO
		for a in anchors.anchors.filter(func(x): return x["tentacle"] == ti):
			mid += a["centre"] / 5.0
		await look_at(h, mid.lerp(r.segments[r.count / 2].global_position, 0.5))
		await h.shot("anchors_tentacle_%d" % ti)
	# The waiters: one before the last chain (live), checked in t365_reload.
	var low: Array = anchors.anchors.duplicate()
	low.sort_custom(func(x, y): return x["centre"].y > y["centre"].y)
	# 1. The Engineer drills the lowest anchor of tentacle 0.
	var first: Dictionary = low.filter(func(x): return x["tentacle"] == 0)[0]
	var spot: Dictionary = stand_by(first)
	h.check("an open cell beside the first anchor", not spot.is_empty(), first["cell"])
	if spot.is_empty():
		return
	var k = h.keeper()
	var share0: float = tents.rigs[0].target_share
	await h.teleport_tile(spot["cell"])
	tents.refresh_near()
	cool(h)
	await h.wait(0.3)
	var t0: float = h.now()
	var act: String = dir_action(spot["dir"])
	h.down(act)
	await h.wait(0.6)
	await h.burst("drilling", 8, 5)
	var broke: bool = await h.until(func():
		cool(h)
		return first["broken"], 25.0)
	var secs: float = h.now() - t0
	await h.burst("break", 12, 3)
	h.up(act)
	h.note("the Engineer (max drill) broke an anchor in %.1f s" % secs)
	h.check("the Engineer breaks an anchor with its drill", broke, secs)
	await h.wait(0.6)
	h.check("1 chain broken: recorded, live event, the tentacles wake", _EndGame.chains_broken() == 1 and _EndGame.is_anchor_broken(first["id"]) and chain_events.size() == 1 and _Ocean.chains_broken() == 1 and tents.rigs[0].target_share > share0, [_EndGame.state(), chain_events, tents.rigs[0].target_share])
	h.check("its four tiles are gone", first["cells"].all(func(c): return td.get_resourcev(c) == Data.TILE_EMPTY))
	h.check("the seal weakens (awakening level)", _Awakening.level() > 0.0 and _Awakening.chains() == 1, _Awakening.level())
	await h.wait(1.5)
	await h.shot("after_first")
	# 2..6: hits on one tile; shares rise each time.
	var order: Array = anchors.anchors.filter(func(x): return not x["broken"])
	var shares: Array = [tents.rigs[0].target_share]
	var equal: bool = true
	for i in 5:
		var a: Dictionary = order[i]
		if i == 2:
			await look_at(h, a["centre"] + Vector2(-signf(a["side"]) * 70.0, -40.0))
		equal = equal and await hit_break(h, a)
		if i == 2:
			await h.burst("break_hits", 10, 3)
		shares.append(tents.rigs[0].target_share)
		cool(h)
	h.check("the four tiles share every hit", equal)
	h.check("six broken: count, record and one live event each", _EndGame.chains_broken() == 6 and chain_events.size() == 6 and last_events == 0, [_EndGame.state(), chain_events])
	var rising: bool = true
	for i in range(1, shares.size()):
		rising = rising and shares[i] > shares[i - 1]
	h.check("the tentacles wake a step with every chain", rising, shares)
	h.check("not free yet", not _EndGame.is_free())
	await h.wait(2.0)
	await look_at(h, tents.rigs[0].segments[tents.rigs[0].count - 6].global_position + Vector2(90, 0))
	await h.shot("six_broken_tentacle_0")
	# Frame cost, anchors on and off, on screen.
	var mid0: Vector2 = Vector2.ZERO
	for a in anchors.anchors.filter(func(x): return x["tentacle"] == 1):
		mid0 += a["centre"] / 5.0
	await look_at(h, mid0)
	var on: float = await _frame_ms(h, 180)
	anchors.visible = false
	anchors.set_process(false)
	var off: float = await _frame_ms(h, 180)
	anchors.visible = true
	anchors.set_process(true)
	var on2: float = await _frame_ms(h, 180)
	h.note("frame ms by tentacle 1's anchors", {"on": on, "off": off, "on again": on2, "process us per frame": float(anchors.process_us) / maxf(1, anchors.frames), "chains drawn": anchors.draw_count})
	h.check("anchors cost under 0.5 ms a frame on screen", minf(on, on2) <= off + 0.5, [on, off, on2])
	h.check("their own process time is small (under 0.15 ms a frame)", float(anchors.process_us) / maxf(1, anchors.frames) < 150.0, float(anchors.process_us) / maxf(1, anchors.frames))
	await SaveGame.saveGame("singleplayer", SLOT, true)
	await h.wait(1.0)
	h.note("saved slot %d" % SLOT, _EndGame.state())


func _frame_ms(h, n: int) -> float:
	var t0: int = Time.get_ticks_usec()
	for i in n:
		await h.get_tree().process_frame
		if i % 30 == 0:
			cool(h)
	return (Time.get_ticks_usec() - t0) / 1000.0 / n
