extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t365_anchors.gd"

# #366: the lair seal before the last chain (huge map, seed 12345). The keeper
# (`-Extra "--keeper=keeper2|3|4"`; the Beastmaster only through this dev
# harness) tries to get through the blue seal over an entry its own way from
# the lava above, by real input (the Engineer and the Beastmaster push and
# drill or punch into it, the Assessor shoots spheres, the Infiltrator throws
# kunai, then hooks the seal and pulls): the crust stays, the keeper never
# gets into the roof row, the seal crackles and throws it back.
# The Engineer's run (the default) also checks the other ways in: big
# explosions, the dev cheat's freeTiles, Map.destroyTile itself; the old boss
# routes (Awakening.wake(), EndGame.record_lair_entered, a keeper teleported
# into the chamber: no fight, no awakening); the crust gone (an old save
# drilled open): the seal's body still stops the keeper and a dropped
# mineral; and the seal's frame cost.

const LairSeal = preload("res://mods-unpacked/flantor-StoryMode/endgame/lair_seal.gd")
static var _LairSeal = LairSeal  # calls go through this: lazy_preload makes const-preload calls slow
const Keeper2Run = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t297_keeper2.gd")
const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const Sfx = preload("res://mods-unpacked/flantor-StoryMode/boss/sfx.gd")
const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow

const LavaData = preload("res://mods-unpacked/flantor-StoryMode/data/lava.gd")
const T := 24.0

var seal
var ch: Rect2i
var _track_k = null
var _deepest: float = -INF
var _inside: int = 0


func boot() -> Dictionary:
	return {"seed": 12345, "keeper": _Story.user_arg("keeper", "keeper1")}


func _track() -> void:
	var k = _track_k
	if k == null or not is_instance_valid(k) or seal == null or not is_instance_valid(seal):
		return
	var p: Vector2 = seal.to_local(k.global_position)
	_deepest = maxf(_deepest, p.y)
	if Rect2(Vector2.ZERO, Vector2(ch.size) * T).has_point(p):
		_inside += 1


func _start_track(h, k) -> void:
	_track_k = k
	_deepest = -INF
	_inside = 0
	if not h.get_tree().physics_frame.is_connected(_track):
		h.get_tree().physics_frame.connect(_track)


func crust_cells() -> Array:
	var out: Array = []
	for col in LavaData.BOSS_CHAMBER_ENTRY:
		out.append(Vector2i(ch.position.x + int(col), ch.position.y - 1))
	return out


func standing(cells: Array) -> int:
	return cells.filter(func(c): return Level.map.tileData.get_resourcev(c) != Data.TILE_EMPTY).size()


func run(h) -> void:
	if not await setup(h):
		return
	seal = _LairSeal.find()
	if not h.check("the run has a lair seal", seal != null):
		return
	ch = Level.map.tileData.get_meta("story_boss_chamber")
	var k = h.keeper()
	var kid: String = _Story.user_arg("keeper", "keeper1")
	h.check("the keeper is the %s" % kid, k.techId == kid, k.techId)
	await Keeper2Run.close_tutorials(h)
	h.check("hidden before the lair is seen", not seal.visible and not seal.seen)
	await reveal_ocean(h)
	await h.wait(0.8)
	h.check("shown once seen", seal.visible and seal.seen)
	h.check("two entries, sealed, its bodies on", seal.entries.size() == 2 and seal.mode == "sealed" and seal.blocking and seal.entries.all(func(e): return not e["shape"].disabled), seal.state())
	var cells: Array = crust_cells()
	h.check("the four crust tiles are there", standing(cells) == 4, cells)
	var e0: Dictionary = seal.entries[0]
	var c0: Vector2i = cells[0]

	# ---- the look
	await look_at(h, seal.to_global(Vector2(e0["x1"] + 30.0, -T * 2.5)))
	h.snap_camera(k)
	await h.wait(1.0)
	cool(h)
	await h.shot("blue_seal")
	await h.burst("blue_seal_idle", 6, 4)

	# ---- the keeper's own way in, from the lava over the entry
	_start_track(h, k)
	var touches0: int = seal.touches
	var refused0: int = seal.hits_refused
	var zaps0: int = int(Sfx.played.get("seal_zap", 0))
	await h.teleport_tile(c0 + Vector2i(0, -1))
	cool(h)
	await h.wait(0.3)
	var t_end: float = h.now() + 9.0
	var shot_done := false
	while h.now() < t_end:
		if k.global_position.distance_to(seal.to_global(Vector2((e0["x0"] + e0["x1"]) * 0.5, -T))) > 90.0:
			await h.teleport_tile(c0 + Vector2i(0, -1))
		if not shot_done:
			shot_done = true
			Keeper2Run.dig(h, k, "ui_down", 2.0)
			await h.burst("%s_bounces_off" % kid, 12, 3)
			await h.wait(1.0)
		else:
			await Keeper2Run.dig(h, k, "ui_down", 2.0)
		cool(h)
	if kid == "keeper2" or kid == "keeper3":
		# From farther up, out of the seal's reach: spheres or kunai at the crust.
		var r0: int = seal.hits_refused
		for i in 3:
			await h.teleport_tile(c0 + Vector2i(0, -4))
			cool(h)
			await h.wait(0.2)
			await Keeper2Run.dig(h, k, "ui_down", 2.0)
		h.note("%s from above" % kid, {"hits_refused": seal.hits_refused - r0})
		h.check("%s: the crust stands" % kid, standing(cells) == 4)
		if kid == "keeper3":
			h.check("%s: its kunai at the crust are refused" % kid, seal.hits_refused > r0, seal.hits_refused - r0)
	if kid == "keeper3":
		# The hook into the seal, then pulling down on the rope.
		await h.teleport_tile(c0 + Vector2i(0, -3))
		k.networkThrowHook(Vector2.DOWN, k.global_position)
		await h.wait(0.6)
		await h.hold("ui_down", 2.5)
		h.note("hook", {"hooked": is_instance_valid(k.hook) and k.hook.has_hit})
		cool(h)
	await h.wait(0.5)
	await h.shot("%s_after_trying" % kid)
	var result := {"deepest_px_below_roof_top": snappedf(_deepest + T, 0.1), "frames_inside": _inside,
		"touches": seal.touches - touches0, "hits_refused": seal.hits_refused - refused0, "zaps": int(Sfx.played.get("seal_zap", 0)) - zaps0}
	h.note("%s against the seal" % kid, result)
	h.check("%s: the crust is still whole" % kid, standing(cells) == 4, cells)
	h.check("%s: never got into the roof row, never into the lair" % kid, _deepest < -T + 4.0 and _inside == 0, result)
	h.check("%s: the seal threw it back or took its hits, with the zap" % kid, (result["touches"] > 0 or result["hits_refused"] > 0) and result["zaps"] > 0, result)
	h.check("%s: still sealed, nothing woke" % kid, seal.mode == "sealed" and seal.blocking and not _EndGame.is_lair_entered() and not bool(Data.ofOr("team1.story.awake", false)) and _Director.current() == "", [seal.state(), _Director.current()])
	if kid != "keeper1":
		return

	# ---- other ways at the crust
	var refused1: int = seal.hits_refused
	Level.map.damageTileCircleArea(Level.map.getTilePos(Vector2(c0)), 2.0, 9999.0, "team1")
	await h.wait(1.0)
	h.check("a big explosion on the entry leaves the crust", standing(cells) == 4 and seal.hits_refused > refused1, seal.hits_refused - refused1)
	await h.clear_tiles([c0, cells[1]])
	h.check("the dev cheat's freeTiles leaves it", standing(cells) == 4)
	var tile = Level.map.tiles.get(Vector2(c0))
	if tile != null:
		Level.map.destroyTile("team1", "", tile)
	await h.wait(0.3)
	h.check("Map.destroyTile itself leaves it", standing(cells) == 4 and Level.map.tiles.has(Vector2(c0)))
	var t2 = Level.map.tiles.get(Vector2(c0))
	h.check("... at full health", t2 != null and t2.health == t2.max_health, [t2.health if t2 else -1, t2.max_health if t2 else -1])

	# ---- the old routes to the boss
	load("res://mods-unpacked/flantor-StoryMode/beats/awakening.gd").wake()
	h.check("Awakening.wake() is refused before the last chain", not bool(Data.ofOr("team1.story.awake", false)))
	h.check("EndGame.record_lair_entered is refused before it", not _EndGame.record_lair_entered(k.playerId) and not _EndGame.is_lair_entered())
	await h.teleport_tile(ch.position + Vector2i(4, ch.size.y - 2))
	await h.wait(3.0)
	h.check("a keeper put inside the sealed lair starts nothing", _Director.current() == "" and not _EndGame.is_lair_entered() and not bool(Data.ofOr("team1.story.awake", false)), [_Director.current(), _EndGame.state()])
	await h.shot("inside_sealed_nothing")

	# ---- the crust gone (an old save drilled open): the body holds
	Data.apply("team1.story.awake", true)
	for c in [c0, cells[1]]:
		var t = Level.map.tiles.get(Vector2(c))
		if t != null:
			Level.map.destroyTile("team1", "", t)
	Data.apply("team1.story.awake", false)
	await h.frames(2)
	h.check("the crust over the left entry is gone (the test's own doing)", standing(cells) == 2)
	h.check("the seal still blocks there", seal.blocking and not e0["shape"].disabled, seal.state())
	_start_track(h, k)
	await h.teleport_tile(c0 + Vector2i(0, -2))
	cool(h)
	h.down("ui_down")
	await h.wait(1.0)
	await h.burst("open_hole_bounces", 8, 3)
	await h.wait(2.0)
	h.up("ui_down")
	cool(h)
	h.check("flying down into the open hole: the seal holds the keeper", _deepest < -T * 0.5 and _inside == 0, {"deepest": snappedf(_deepest + T, 0.1), "inside": _inside})
	var drop = Level.drops.network_spawn({"type": "iron", "position": seal.to_global(Vector2((e0["x0"] + e0["x1"]) * 0.5, -T * 2.0)), "impulse": Vector2.ZERO})
	await h.wait(3.0)
	if drop != null and is_instance_valid(drop):
		var dp: Vector2 = seal.to_local(drop.global_position)
		h.check("a dropped mineral rests on it, out of the lair", dp.y < 0.0, dp)
	else:
		h.note("no drop to test")
	await h.shot("hole_still_sealed")
	h.check("still nothing woke", seal.mode == "sealed" and _Director.current() == "" and not _EndGame.is_lair_entered())

	# ---- frame cost: its own work on screen, and the frame with it shown or hidden
	await look_at(h, seal.to_global(Vector2(e0["x1"] + 30.0, -T * 2.5)))
	h.snap_camera(k)
	await h.wait(0.5)
	seal.process_us = 0
	seal.process_frames = 0
	await h.wait(3.0)
	var per_frame: float = float(seal.process_us) / maxf(1.0, float(seal.process_frames))
	var cost: Dictionary = {}
	for shown in [false, true, false, true, false, true]:
		seal.visible = shown
		await h.frames(20)
		var ms: float = 0.0
		for i in 90:
			await h.frames(1)
			ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var key: String = "shown" if shown else "hidden"
		cost[key] = float(cost.get(key, 0.0)) + ms / 90.0 / 3.0
	seal.visible = true
	h.note("frame cost", {"seal_us_per_frame": snappedf(per_frame, 0.1), "process_ms": cost})
	h.check("the seal's own work is under 0.15 ms a frame", per_frame < 150.0, per_frame)




# --- shared with t366_open, t366_reload, t366_mp_* -----------------------------------

# Drills down through crust cell `c0` from the lava over it by real input
# (the Engineer's drill), into the lair. Returns whether the keeper got in.
func drill_in(h, k, c0: Vector2i, label: String = "passing_in") -> bool:
	_start_track(h, k)
	await h.teleport_tile(c0 + Vector2i(0, -1), k)
	cool(h)
	await h.wait(0.3)
	var t0: float = h.now()
	var shot_done := false
	h.down("ui_down")
	while h.now() - t0 < 20.0 and _inside == 0:
		await h.wait(0.05)
		cool(h)
		# A burst as the keeper reaches the membrane (the chamber's top edge).
		if not shot_done and Level.map.tileData.get_resourcev(c0) == Data.TILE_EMPTY and seal.to_local(k.global_position).y > -14.0:
			shot_done = true
			await h.burst(label, 10, 2)
	h.up("ui_down")
	await h.wait(0.3)
	return _inside > 0
