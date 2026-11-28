extends Node2D

# The last-chain cutscene (#367, End game 2.0 map #363): the horror hands the
# ship over. Values in data/last_chain.gd.
#
# When the last chain breaks (EndGame.when_free, live):
#   hold     play freezes (the beats' own pause: keepers, monsters, waves, lava
#            and gas all stop, nothing takes damage). Every local camera leans
#            toward the ship in the ocean; the coil that holds it lets go of
#            the ocean and drags it down under the lava (Ship.take_over(),
#            release_ocean(true): the coil sinks, the ship sinks with it).
#   rise     every local camera eases up from the ocean to the dome, pulling
#            back halfway; something huge climbs through the rock with it
#            (violet light in the cracks, a glow, dust) and the ground rumbles.
#   crack    the ground left of the ship's spot by the dome splits and glows
#            (the finale's break-out: boss/surface_tentacle.gd's cracks and light).
#   burst    the coil breaks out of the ground with the ship in it: rock thrown
#            up, a column of light, a roar, a big shake.
#   carry    it swings the ship over toward the dome, legs coming out;
#   set      and sets it down on its spot, with a thud and dust.
#   mend     the horror's light runs over the hull: the burns are gone, the
#            lights flicker on (the broken toy, fixed).
#   release  the coil unwinds from the hull and the arm pulls back into the
#            ground. The ship stands at the dome (Ship.land_now(true)) and its
#            boarding tube comes out to the dome (the ship's own).
#   beat     the story beat (data/beats.gd BEAT_ID) over the docked ship.
#   return   every camera eases back down to its keeper.
#   done     play resumes. `cutscene_finished(true)` and the when_done waiters.
#
# The lair seal's opening (#366) waits while play is frozen, so it plays the
# first time the seal is seen after this. The rising lava (#369) starts on
# `LastChain.when_done(cb)`.
#
# Saves: Data DONE_KEY is -1 while the cutscene runs (the host writes it at the
# start) and the run time once it is over. A run loaded with the last chain
# already broken never replays it (the ship stands at the dome by itself,
# Ship.should_be_landed()); if it was saved mid-cutscene (-1) the beat is
# queued instead, so the story is not lost. A late joiner gets the after-state.
#
# Online: every peer plays its own copy from the live last chain (the host's
# EndGame tells clients live), so each instance moves its own cameras and its
# own ship. The host leads: it opens the beat for the team (the beats' own
# team pause) and tells clients when to start back (StoryNet.last_chain_step:
# "beat", "return", "skip"); a client waits at the beat for the host's word.
#
# Skipping: holding the use or accept key SKIP_HOLD_S (a ring fills, no words)
# sets the ship down at once and goes to the beat. Online only the host can.
#
# API (#369 and anyone after):
#   LastChain.find()                 the node (under the map, every peer)
#   LastChain.is_playing() -> bool   the cutscene is on screen here
#   LastChain.is_done() -> bool      it is over (or a load/late join skipped it)
#   LastChain.when_done(cb)          cb(live: bool), once per run: live = at the
#                                    end of the live cutscene; false (deferred)
#                                    when it was already over or never played
#                                    here (a load, a late join, `--free`)
#   node.cutscene_finished(live)     signal, the same moment
#   node.step_changed(step)          signal, each step (playtests)

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const EndGame = preload("res://mods-unpacked/flantor-StoryMode/endgame/end_game.gd")
static var _EndGame = EndGame  # calls go through this: lazy_preload makes const-preload calls slow
const Ship = preload("res://mods-unpacked/flantor-StoryMode/endgame/ship.gd")
static var _Ship = Ship  # calls go through this: lazy_preload makes const-preload calls slow
const ShipArt = preload("res://mods-unpacked/flantor-StoryMode/endgame/ship_art.gd")
static var _ShipArt = ShipArt  # calls go through this: lazy_preload makes const-preload calls slow
const ShipData = preload("res://mods-unpacked/flantor-StoryMode/data/ship.gd")
const Cut = preload("res://mods-unpacked/flantor-StoryMode/data/last_chain.gd")
const Sfx = preload("res://mods-unpacked/flantor-StoryMode/boss/sfx.gd")
static var _Sfx = Sfx  # calls go through this: lazy_preload makes const-preload calls slow
const Pix = preload("res://mods-unpacked/flantor-StoryMode/boss/pix.gd")
static var _Pix = Pix  # calls go through this: lazy_preload makes const-preload calls slow
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
static var _StoryBeats = StoryBeats  # calls go through this: lazy_preload makes const-preload calls slow
const BeatData = preload("res://mods-unpacked/flantor-StoryMode/data/beats.gd")
const StoryNet = preload("res://mods-unpacked/flantor-StoryMode/net/story_net.gd")
static var _StoryNet = StoryNet  # calls go through this: lazy_preload makes const-preload calls slow
const TENTACLE := "res://mods-unpacked/flantor-StoryMode/boss/surface_tentacle.gd"

const NAME := "StoryLastChain"
const DONE_KEY := "team1.story.lastchaincut"   # float: -1 while it plays, the run time once over
const STEPS := ["idle", "hold", "rise", "crack", "burst", "carry", "set", "mend", "release", "dock", "beat", "return", "done"]
const EARTH: Array = [Color("2a2130"), Color("3b2f44"), Color("1c1622"), Color("4a3d52")]
const COIL_DARK := Color(0.11, 0.05, 0.19)
const COIL_BODY := Color(0.29, 0.13, 0.45)
const COIL_LIGHT := Color(0.45, 0.26, 0.64)

signal cutscene_finished(live: bool)
signal step_changed(step: String)

static var events: Array = []       # for playtests: {"what", ...}
static var _waiters: Array = []     # [seed, Callable]
static var _done_seed: int = -1     # this peer finished (or skipped) it for that run

var step: String = "idle"
var t: float = 0.0                  # seconds into the step
var total: float = 0.0              # seconds since the last chain (frozen time)
var live: bool = false
var proc_us: int = 0
var skipped: bool = false

var _ship = null
var _ST = null                      # boss/surface_tentacle.gd, for its cracks and light
var _input = null
var _frozen: bool = false
var _cams: Dictionary = {}          # playerId -> {"cam", "from", "z0", "hold_end"}
var _shot_c: Vector2                # the dome shot's middle (global)
var _shot_w: float = 640.0
var _hole: Vector2                  # where it breaks out (global, on the ground)
var _spot: Vector2                  # where the ship stands (global, its centre)
var _ground: float = 0.0
var _has_dome: bool = false
var _rise_s: float = 3.0
var _ret_s: float = 2.4
var _sink_from: Vector2
var _sink_rot: float = 0.0
var _sink_t: float = -1.0
var _burrow_from: Vector2
var _cracks: Array = []
var _crack_seed: int = 0
var _crack_grow: float = 0.0
var _crack_glow: float = 0.0
var _scar: float = 0.0              # the broken ground's glow after it went back in
var _flash: float = 0.0
var _hull_glow: float = 0.0
var _debris: Array = []
var _glints: Array = []             # [pos, life, max, pts]
var _glint_acc: float = 0.0
var _rumble_acc: float = 0.0
var _grip_back: Node2D = null
var _grip_front: Node2D = null
var _arm: Array = []                # the arm's Line2Ds (edge, body, light)
var _pieces: Array = []             # the coil round the hull: {"pts","ws","s0","len","cum","lines"}
var _coil_len: float = 0.0
var _arm_to: Vector2                # ship space: where the arm meets the coil
var _host_step: String = ""         # client: what the host said last
var _skip_held: float = 0.0
var _beat_seen_open: bool = false
var _beat_wait: float = 0.0
var _rng := RandomNumberGenerator.new()


static func find():
	if Level.map == null or not is_instance_valid(Level.map):
		return null
	return Level.map.get_node_or_null(NAME)


static func is_playing() -> bool:
	var n = find()
	return n != null and n.step != "idle" and n.step != "done"


static func is_done() -> bool:
	if float(Data.ofOr(DONE_KEY, -1.0)) >= 0.0:
		return true
	return _done_seed == Level.levelSeed


static func when_done(cb: Callable) -> void:
	if is_done():
		cb.call_deferred(false)
	else:
		_waiters.append([Level.levelSeed, cb])


# --- setup ------------------------------------------------------------------------

func setup(map) -> bool:
	if not _Story.is_story():
		return false
	name = NAME
	z_as_relative = false
	z_index = 40               # over the surface's foreground rocks, so the broken ground shows
	process_priority = 100      # after the cameras, the beats and the ship
	_rng.seed = hash([Level.levelSeed, "lastchain"])
	_ST = load(TENTACLE)
	_waiters = _waiters.filter(func(w): return int(w[0]) == Level.levelSeed)
	_done_seed = -1             # a new map: a new run (even with the same seed)
	_EndGame.when_free(_on_free)
	return true


func _on_free(is_live: bool) -> void:
	if step != "idle":
		return
	if not is_live:
		_after_state()
		return
	_start()


# A run that is already free here (a load, a late join, a dev route): no
# cutscene. A save made mid-cutscene queues its beat, so the story isn't lost.
func _after_state() -> void:
	step = "done"
	var mid: bool = Data.ofOr(DONE_KEY, null) != null and float(Data.ofOr(DONE_KEY, 0.0)) < 0.0
	if not Network.is_client():
		if mid:
			_StoryBeats.fire(Cut.BEAT_ID)
			Data.apply(DONE_KEY, GameWorld.runTime)
	events.append({"what": "after_state", "mid": mid})
	ModLoaderLog.info("Last chain: already free (%s): no cutscene" % ("saved mid-cutscene, the beat queued" if mid else "after it"), _Story.LOG)
	_mark_done(false)


func _mark_done(was_live: bool) -> void:
	_done_seed = Level.levelSeed
	cutscene_finished.emit(was_live)
	var now: Array = _waiters.filter(func(w): return int(w[0]) == Level.levelSeed)
	_waiters.clear()
	for w in now:
		var cb: Callable = w[1]
		if cb.is_valid():
			cb.call(was_live)


# --- the start --------------------------------------------------------------------

func _start() -> void:
	live = true
	_ship = _Ship.find()
	if _ship != null:
		_ship.take_over()
		_sink_from = _ship.carrier.global_position
		_sink_rot = _ship.carrier.rotation
		_burrow_from = _sink_from + Vector2(0, 260)
	else:
		_burrow_from = Vector2.ZERO
	_has_dome = _dome_geo()
	if not Network.is_client():
		Data.apply(DONE_KEY, -1.0)
	_freeze()
	_block_input()
	for k in _Story.local_keepers():
		var cam = _cam_of(k)
		if cam == null:
			continue
		var from: Vector2 = cam.global_position
		var lean_to: Vector2 = from
		if _ship != null and from.distance_to(_sink_from) < Cut.OCEAN_LEAN_RANGE:
			lean_to = from.lerp(_sink_from + Vector2(0, 30), Cut.OCEAN_LEAN)
		_cams[k.playerId] = {"cam": cam, "keeper": k, "from": from, "z0": cam.zoom.x, "hold_end": lean_to}
	if _burrow_from == Vector2.ZERO:
		for pid in _cams:
			_burrow_from = _cams[pid]["from"]
			break
	_Sfx.play("pull", -3.0, 0.7)
	InputSystem.shake(8.0, 0.4, 14.0)
	ModLoaderLog.info("Last chain: the cutscene starts (%d camera(s), the dome %s)" % [_cams.size(), "found" if _has_dome else "missing"], _Story.LOG)
	_go("hold")


func _dome_geo() -> bool:
	if _ship == null:
		return false
	var s: Vector2 = _Ship.dome_spot()
	if s == Vector2.INF:
		return false
	_spot = s
	_ground = _ship.ground_y()
	_hole = Vector2(_spot.x - Cut.HOLE_BACK, _ground)
	var d = Level.getDome("team1")
	var dome_x: float = d.global_position.x if d != null else _spot.x + 210.0
	_shot_w = Cut.SHOT_W
	_shot_c = Vector2(dome_x - Cut.SHOT_LEFT, _ground - Cut.SHOT_DROP)
	_crack_seed = hash([Level.levelSeed, "lastchain-crack"])
	_cracks = []
	_cracks = _ST.crack_lines(_crack_seed, true)
	return true


func _cam_of(k):
	if Level.viewports == null or not is_instance_valid(Level.viewports) or k == null:
		return null
	var cam = Level.viewports.getPlayerCam(k.playerId)
	if cam == null or not is_instance_valid(cam) or not cam.is_inside_tree():
		return null
	return cam


func _local_keeper():
	return _Story.local_keeper()


# --- freezing play ------------------------------------------------------------------

# The beats' own freeze (vanilla's group pause, beats/story_beats.gd): keepers,
# monsters, the wave clock, lava, gas and every Story Mode system stop.
func _freeze() -> void:
	_frozen = true
	if GameWorld.paused:
		return
	GameWorld.pause(true)
	var stage = Level.stage
	if stage != null and stage.has_node("Tween"):
		stage.get_node("Tween").stop_all()
	get_tree().call_group("monster", "pause")
	for n in get_tree().get_nodes_in_group("pauseL"):
		if n.name == "PauseLabel" and n.has_method("moveOut"):
			n.moveOut()


func _unfreeze() -> void:
	_frozen = false
	GameWorld.unpause()
	var stage = Level.stage
	if stage != null and stage.has_method("checkForGroupPause"):
		if stage.has_node("Tween"):
			stage.get_node("Tween").resume_all()
		get_tree().call_group("monster", "unpause")
		if not Network.is_offline_mode() and multiplayer.is_server():
			stage.checkForGroupPause()


func _block_input() -> void:
	var k = _local_keeper()
	if k == null or Level.stage == null:
		return
	_input = load(_Story.MOD_DIR + "endgame/cutscene_input.gd").new()
	_input.deviceId = k.deviceId
	_input.globalInput = true
	_input.cutscene = self
	_input.integrate(Level.stage)


func _unblock_input() -> void:
	if _input != null and is_instance_valid(_input) and not _input.desintegrating:
		_input.desintegrate()
	_input = null


# --- every frame --------------------------------------------------------------------

func _process(delta: float) -> void:
	if step == "idle" or (step == "done" and _scar <= 0.0 and _debris.is_empty()):
		return
	var us0: int = Time.get_ticks_usec()
	if step == "done":
		_scar = maxf(0.0, _scar - delta * 0.25)
		_step_fx(delta)
		queue_redraw()
		proc_us += Time.get_ticks_usec() - us0
		return
	var stage = Level.stage
	var menu: bool = stage != null and "pauseMenuOpen" in stage and stage.pauseMenuOpen
	# Play stays frozen all through (the pause menu or the beat may unpause it).
	if _frozen and not GameWorld.paused and not menu:
		_freeze()
	if not menu:
		_tick(delta)
	if step != "done":
		_cameras()
	queue_redraw()
	proc_us += Time.get_ticks_usec() - us0


func _go(s: String) -> void:
	step = s
	t = 0.0
	events.append({"what": "step", "step": s, "total": snappedf(total, 0.01)})
	ModLoaderLog.info("Last chain: %s (%.2f s)" % [s, total], _Story.LOG)
	match s:
		"rise":
			_rise_s = Cut.RISE_MIN_S
			for pid in _cams:
				var c: Dictionary = _cams[pid]
				_rise_s = maxf(_rise_s, Cut.RISE_MIN_S * 0.6 + c["hold_end"].distance_to(_shot_c) / Cut.RISE_PX_PER_S)
			_rise_s = minf(_rise_s, Cut.RISE_MAX_S)
			_Sfx.play("burrow", -2.0, 0.55)
			_Sfx.play("eerie", -10.0, 0.7)
		"crack":
			_Sfx.play("drop", -3.0, 0.6)
		"burst":
			_burst_out()
		"carry":
			_Sfx.play("pull", -5.0, 0.9)
		"mend":
			_Sfx.play("heart", -5.0, 0.75)
		"release":
			_Sfx.play("burrow", -4.0, 0.8)
		"return":
			_ret_s = Cut.RETURN_MIN_S
			for pid in _cams:
				var c: Dictionary = _cams[pid]
				_ret_s = maxf(_ret_s, Cut.RETURN_MIN_S * 0.6 + _shot_c.distance_to(_rest_of(c)) / Cut.RETURN_PX_PER_S)
			_ret_s = minf(_ret_s, Cut.RETURN_MAX_S)
	step_changed.emit(s)


func _tick(delta: float) -> void:
	t += delta
	total += delta
	_step_fx(delta)
	_tick_skip(delta)
	if step == "idle" or step == "done":
		return
	match step:
		"hold":
			if t >= Cut.RELEASE_AT and _sink_t < 0.0 and _ship != null:
				_ship.release_ocean(true)
				_sink_t = 0.0
				_Sfx.play("burrow", -3.0, 0.7)
			_sink_ship(delta)
			if t >= Cut.HOLD_S:
				_go("rise")
		"rise":
			_sink_ship(delta)
			_burrow(delta)
			_rumble(delta, Cut.SHAKE_RISE * (0.6 + 0.4 * sin(t * 3.0)), 0.55)
			if t >= _rise_s:
				if _ship != null:
					_ship.carrier.visible = false
				_go("crack" if _has_dome else "dock")
				if not _has_dome and _ship != null:
					_ship.place_at_dome(false)
		"crack":
			var u: float = clampf(t / Cut.CRACK_S, 0.0, 1.0)
			_crack_grow = u * u * (3.0 - 2.0 * u)
			_crack_glow = 0.4 + 0.6 * u
			_rumble(delta, Cut.SHAKE_CRACK * (0.4 + 0.6 * u), 0.3)
			if _rng.randf() < delta * 26.0 * u:
				_pebble(Vector2(_rng.randf_range(-70, 70), 0), 90.0)
			if t >= Cut.CRACK_S:
				_go("burst")
		"burst":
			var u: float = clampf(t / Cut.BURST_S, 0.0, 1.0)
			var e: float = _ST._back_out(u)
			_place(_hole + Cut.START_UNDER.lerp(Cut.PEAK, e), lerpf(Cut.START_TILT, Cut.PEAK_TILT, minf(1.0, e)))
			_arm_follow(0.0)
			if t >= Cut.BURST_S:
				_go("carry")
		"carry":
			var u: float = clampf(t / Cut.CARRY_S, 0.0, 1.0)
			var e: float = u * u * (3.0 - 2.0 * u)
			var p0: Vector2 = _hole + Cut.PEAK
			var p3: Vector2 = _spot + Vector2(0, -Cut.HOVER_PX)
			var p1: Vector2 = p0 + Vector2(70, -80)
			var p2: Vector2 = p3 + Vector2(-30, -110)
			var at: Vector2 = p0.bezier_interpolate(p1, p2, p3, e)
			var tilt: float = lerpf(Cut.PEAK_TILT, Cut.DIP_TILT, smoothstep(0.0, 0.8, u)) * (1.0 - smoothstep(0.8, 1.0, u)) + sin(t * 4.0) * 0.03 * (1.0 - u)
			_place(at + Vector2(0, sin(t * 5.0) * 3.0 * (1.0 - u)), tilt)
			_ship.set_legs(lerpf(0.15, 1.0, smoothstep(0.45, 1.0, u)))
			_arm_follow(0.0)
			if t >= Cut.CARRY_S:
				_go("set")
		"set":
			var u: float = clampf(t / Cut.SET_S, 0.0, 1.0)
			_place(_spot + Vector2(0, -Cut.HOVER_PX * (1.0 - u * u)), 0.0)
			_arm_follow(0.0)
			if t >= Cut.SET_S:
				_touch_down()
				_go("mend")
		"mend":
			_place(_spot, 0.0)
			_arm_follow(0.0)
			_hull_glow = clampf(1.0 - absf(t - 0.4) / 0.4, 0.0, 1.0)
			if t >= 0.4 and _ship._scorched:
				_ship.set_scorched(false)
				_flash = 0.7
				_Sfx.play("seal_settle", -8.0, 1.25)
			# The lights flicker on.
			var on: bool = t >= 0.55 and not (t >= 0.62 and t < 0.7) and not (t >= 0.76 and t < 0.8)
			if on != _ship._lights_on:
				_ship.set_lights(on)
				if on and t >= 0.8:
					_Sfx.play("ship_ready", -6.0, 0.8)
			if t >= Cut.MEND_S:
				_ship.set_lights(true)
				_go("release")
		"release":
			_place(_spot, 0.0)
			var u: float = clampf(t / Cut.RELEASE_S, 0.0, 1.0)
			_set_coil_shown(1.0 - smoothstep(0.0, 0.5, u))
			_arm_follow(smoothstep(0.42, 1.0, u))
			_rumble(delta, 4.0, 0.3)
			if t >= Cut.RELEASE_S:
				_land()
				_go("dock")
		"dock":
			if t >= Cut.DOCK_S + Cut.BEAT_DELAY_S:
				_start_beat()
		"beat":
			if Network.is_client():
				_client_wait_beat(delta)
		"return":
			if t >= _ret_s:
				_finish()


# The coil drags the ship down into the lava with it (the ship's own sink).
func _sink_ship(delta: float) -> void:
	if _ship == null or _sink_t < 0.0 or not _ship.carrier.visible:
		return
	_sink_t += delta
	var u: float = clampf(_sink_t / ShipData.OCEAN_SINK_S, 0.0, 1.0)
	var jolt: float = sin(_sink_t * 9.0) * 0.01 * (1.0 - u)
	_ship.carrier.global_position = _sink_from + Vector2(sin(_sink_t * 13.0) * 1.5 * (1.0 - u), 300.0 * u * u)
	_ship.carrier.rotation = _sink_rot + jolt
	if u >= 1.0:
		_ship.carrier.visible = false


func _place(at: Vector2, rot: float) -> void:
	if _ship == null:
		return
	_ship.carrier.visible = true
	_ship.carrier.global_position = at
	_ship.carrier.rotation = rot


# --- the break-out --------------------------------------------------------------------

func _burst_out() -> void:
	if _ship == null:
		return
	_ship.clip_to_ground(true)
	_ship.set_legs(0.15)
	_build_grip()
	_place(_hole + Cut.START_UNDER, Cut.START_TILT)
	_crack_grow = 1.0
	_crack_glow = 1.0
	_flash = 1.0
	for i in 54:
		var up: float = _rng.randf_range(160.0, 470.0)
		_debris.append({"p": Vector2(_rng.randf_range(-30, 30), -2.0), "v": Vector2(_rng.randf_range(-230, 230), -up), "s": float(2 + _rng.randi() % 6),
			"col": EARTH[_rng.randi() % EARTH.size()], "life": _rng.randf_range(2.5, 5.0), "rest": false})
	for i in 22:
		_debris.append({"p": Vector2(_rng.randf_range(-40, 40), -2.0), "v": Vector2(_rng.randf_range(-70, 70), _rng.randf_range(-120, -30)), "s": float(4 + _rng.randi() % 4),
			"col": Color(0.42, 0.36, 0.47, 0.5), "life": _rng.randf_range(0.8, 1.6), "rest": false, "dust": true})
	_Sfx.play("grow", 0.0, 0.75)
	_Sfx.play("boom", -3.0, 0.65)
	_Sfx.play("roar", -9.0, 0.75)
	InputSystem.shake(Cut.SHAKE_BURST, 0.9, 18.0)


func _touch_down() -> void:
	_Sfx.play("ship_land", -3.0, 0.85)
	InputSystem.shake(Cut.SHAKE_SET, 0.45, 16.0)
	for x in [-94.0, 66.0]:
		for i in 8:
			_debris.append({"p": Vector2(_spot.x + x - _hole.x + _rng.randf_range(-8, 8), -1.0), "v": Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-50, -10)), "s": float(3 + _rng.randi() % 3),
				"col": Color(0.42, 0.36, 0.47, 0.45), "life": _rng.randf_range(0.6, 1.2), "rest": false, "dust": true})


# The ship stands at the dome now: the ship takes over again.
func _land() -> void:
	_free_grip()
	if _ship == null:
		return
	_ship.clip_to_ground(false)
	_ship.land_now(true)
	_scar = 1.0
	events.append({"what": "landed"})


# --- the coil and its arm ---------------------------------------------------------------

func _build_grip() -> void:
	_free_grip()
	var carrier: Node2D = _ship.carrier
	_grip_back = Node2D.new()
	_grip_back.name = "CutGripBack"
	carrier.add_child(_grip_back)
	carrier.move_child(_grip_back, 0)
	_grip_front = Node2D.new()
	_grip_front.name = "CutGripFront"
	carrier.add_child(_grip_front)
	# The coil round the hull: the ship's own coil (endgame/ship_art.gd COIL)
	# from its first band on, then its free tip.
	var ctrl: Array = []
	for i in range(4, ShipArt.COIL.size()):
		ctrl.append(ShipArt.COIL[i][0])
	var sp: Array = _ShipArt.spline(ctrl, 6.0)
	var pts: PackedVector2Array = sp[0]
	var ts: PackedFloat32Array = sp[1]
	var runs: Array = []
	var cur: Dictionary = {}
	for i in pts.size():
		var ci: int = clampi(int(floor(ts[i])), 0, ctrl.size() - 1)
		var cj: int = mini(ci + 1, ctrl.size() - 1)
		var share: float = lerpf(float(ShipArt.COIL[4 + ci][1]), float(ShipArt.COIL[4 + cj][1]), ts[i] - float(ci))
		var front: bool = bool(ShipArt.COIL[4 + ci][2])
		if cur.is_empty() or bool(cur["front"]) != front:
			var nxt := {"pts": PackedVector2Array(), "ws": PackedFloat32Array(), "front": front}
			if not cur.is_empty():
				nxt["pts"].append(cur["pts"][cur["pts"].size() - 1])
				nxt["ws"].append(cur["ws"][cur["ws"].size() - 1])
			runs.append(nxt)
			cur = nxt
		cur["pts"].append(pts[i])
		cur["ws"].append(_ShipArt.width_at(share))
	var tip := {"pts": PackedVector2Array(), "ws": PackedFloat32Array(), "front": true}
	for i in ShipArt.TIP.size():
		tip["pts"].append(ShipArt.TIP[i])
		tip["ws"].append(_ShipArt.width_at(float(ShipArt.TIP_SHARE[i])))
	runs.append(tip)
	_pieces = []
	var s0: float = 0.0
	for r in runs:
		var cum := PackedFloat32Array([0.0])
		var p: PackedVector2Array = r["pts"]
		for i in range(1, p.size()):
			cum.append(cum[i - 1] + p[i].distance_to(p[i - 1]))
		var piece := {"pts": p, "ws": r["ws"], "s0": s0, "len": cum[cum.size() - 1], "cum": cum, "lines": []}
		var parent: Node2D = _grip_front if r["front"] else _grip_back
		piece["lines"] = _make_lines(parent, r["front"])
		_pieces.append(piece)
		s0 += float(piece["len"])
	_coil_len = s0
	_arm_to = ctrl[0]
	_set_coil_shown(1.0)
	# The arm, from the hole to the coil (behind the hull).
	_arm = _make_lines(_grip_back, false)
	for i in _arm.size():
		_grip_back.move_child(_arm[i], i)


func _make_lines(parent: Node2D, suckers: bool) -> Array:
	var out: Array = []
	for layer in [["edge", COIL_DARK], ["body", COIL_BODY], ["light", COIL_LIGHT]]:
		var l := Line2D.new()
		l.name = "Cut_" + str(layer[0])
		l.default_color = layer[1]
		l.joint_mode = Line2D.LINE_JOINT_ROUND
		l.begin_cap_mode = Line2D.LINE_CAP_ROUND
		l.end_cap_mode = Line2D.LINE_CAP_ROUND
		l.round_precision = 4
		l.antialiased = false
		parent.add_child(l)
		out.append(l)
	if suckers:
		var s = Ship._Suckers.new()
		s.name = "Cut_suckers"
		parent.add_child(s)
		out.append(s)
	return out


# Points and widths on `lines` (edge, body, light[, suckers]).
func _set_lines(lines: Array, pts: PackedVector2Array, ws: PackedFloat32Array) -> void:
	var show: bool = pts.size() >= 2
	for l in lines:
		l.visible = show
	if not show:
		return
	var wmax: float = 1.0
	for w in ws:
		wmax = maxf(wmax, w)
	var curve := Curve.new()
	var total_len: float = 0.0
	var acc := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		total_len += pts[i].distance_to(pts[i - 1])
		acc.append(total_len)
	for i in pts.size():
		curve.add_point(Vector2(clampf(acc[i] / maxf(total_len, 1.0), 0.0, 1.0), ws[i] / wmax))
	lines[0].points = pts
	lines[0].width = wmax + 3.0
	lines[0].width_curve = curve
	lines[1].points = pts
	lines[1].width = wmax
	lines[1].width_curve = curve
	var side := PackedVector2Array()
	for i in pts.size():
		var a: Vector2 = pts[maxi(i - 1, 0)]
		var b: Vector2 = pts[mini(i + 1, pts.size() - 1)]
		side.append(pts[i] + (b - a).normalized().orthogonal() * ws[i] * -0.24)
	lines[2].points = side
	lines[2].width = wmax * 0.2
	lines[2].width_curve = curve
	if lines.size() > 3:
		lines[3].pts = pts
		lines[3].widths = ws
		lines[3].queue_redraw()


# The coil shown from its start (at the arm) out to `share` of its length:
# it unwinds from the tip back.
func _set_coil_shown(share: float) -> void:
	var show_len: float = _coil_len * clampf(share, 0.0, 1.0)
	for p in _pieces:
		var s0: float = p["s0"]
		var pts: PackedVector2Array = p["pts"]
		var ws: PackedFloat32Array = p["ws"]
		var cum: PackedFloat32Array = p["cum"]
		var keep: float = show_len - s0
		if keep >= float(p["len"]):
			_set_lines(p["lines"], pts, ws)
			continue
		var vp := PackedVector2Array()
		var vw := PackedFloat32Array()
		if keep > 0.0:
			for i in pts.size():
				if cum[i] <= keep:
					vp.append(pts[i])
					vw.append(ws[i])
				else:
					var f: float = (keep - cum[i - 1]) / maxf(0.001, cum[i] - cum[i - 1])
					vp.append(pts[i - 1].lerp(pts[i], f))
					vw.append(lerpf(ws[i - 1], ws[i], f))
					break
		_set_lines(p["lines"], vp, vw)


# The arm from the hole to the coil, in the carrier's space. `back` 0..1: it
# pulls back down into the hole (the far end comes free and sinks in).
func _arm_follow(back: float) -> void:
	if _arm.is_empty() or _ship == null:
		return
	var carrier: Node2D = _ship.carrier
	var b: Vector2 = carrier.to_global(_arm_to)
	var under: Vector2 = _hole + Vector2(0, 90)
	var e: float = back * back
	var p3: Vector2 = b.lerp(under, e) + Vector2(0, -26.0 * sin(back * PI))
	var p0: Vector2 = _hole + Vector2(0, 30)
	var p1: Vector2 = _hole + Vector2(0, -110).lerp(Vector2(0, 40), e)
	var p2: Vector2 = (b + Vector2(-75, -5)).lerp(_hole + Vector2(-20, 20), e)
	var pts := PackedVector2Array()
	var ws := PackedFloat32Array()
	var n: int = 18
	for i in n + 1:
		var u: float = float(i) / float(n)
		var w: Vector2 = p0.bezier_interpolate(p1, p2, p3, u)
		w += Vector2(sin(u * 7.0 - total * 3.0), 0) * 3.0 * sin(u * PI)
		pts.append(carrier.to_local(w))
		ws.append(lerpf(Cut.ARM_ROOT_W, ShipData.COIL_BAND_W, u))
	_set_lines(_arm, pts, ws)


func _free_grip() -> void:
	for n in [_grip_back, _grip_front]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_grip_back = null
	_grip_front = null
	_arm = []
	_pieces = []


# --- the beat and back ------------------------------------------------------------------

func _start_beat() -> void:
	_go("beat")
	if Network.is_client():
		if _host_step == "return":
			_go("return")
		return
	var sb = _StoryBeats.instance()
	if sb == null or _StoryBeats.has_played(Cut.BEAT_ID) or BeatData.by_id(Cut.BEAT_ID).is_empty():
		events.append({"what": "beat_skipped", "played": _StoryBeats.has_played(Cut.BEAT_ID)})
		_StoryNet.last_chain_step("return")
		_go("return")
		return
	_StoryNet.last_chain_step("beat")
	events.append({"what": "beat_open"})
	await sb.play_now(Cut.BEAT_ID)
	if not is_inside_tree() or step != "beat":
		return
	# The beat's close unpaused play: frozen again in the same frame.
	_freeze()
	events.append({"what": "beat_closed"})
	_StoryNet.last_chain_step("return")
	_go("return")


# A client waits at the beat for the host's word (it opens the beat for the
# team and says when it closed). If the word is lost, the beat's own key: once
# it has been open and is clear again, the beat is over.
func _client_wait_beat(delta: float) -> void:
	if _host_step == "return":
		_go("return")
		return
	var open: bool = str(Data.ofOr(_StoryBeats.OPEN, "")) != ""
	if open:
		_beat_seen_open = true
	_beat_wait += delta
	if (_beat_seen_open and not open and _beat_wait > 1.0) or _beat_wait > 120.0:
		events.append({"what": "client_beat_fallback", "seen": _beat_seen_open})
		_go("return")


# The host's word (online, StoryNet.last_chain_step).
func host_step(s: String) -> void:
	_host_step = s
	events.append({"what": "host_step", "step": s, "at": step})
	if step == "idle" or step == "done":
		return
	match s:
		"skip":
			_skip()
		"beat":
			if STEPS.find(step) < STEPS.find("beat"):
				_jump_landed()
				_go("beat")
		"return":
			if STEPS.find(step) < STEPS.find("return"):
				_jump_landed()
				_go("return")


# Everything up to the beat at once: the ship stands at the dome.
func _jump_landed() -> void:
	if _ship != null:
		if _sink_t < 0.0:
			_ship.release_ocean(false)
		if _ship.mode != "dome":
			_free_grip()
			_ship.clip_to_ground(false)
			if _has_dome:
				_ship.land_now(true)
			else:
				_ship.place_at_dome(false)
	_crack_grow = 1.0
	_scar = maxf(_scar, 0.6)


func _skip() -> void:
	if STEPS.find(step) >= STEPS.find("beat"):
		return
	skipped = true
	events.append({"what": "skip", "at": step})
	ModLoaderLog.info("Last chain: skipped at %s" % step, _Story.LOG)
	_jump_landed()
	_start_beat()


func _tick_skip(delta: float) -> void:
	var can: bool = (Network.is_offline_mode() or not Network.is_client()) and total >= Cut.SKIP_AFTER_S and STEPS.find(step) < STEPS.find("beat")
	var held: bool = can and _input != null and is_instance_valid(_input) and _input.holding
	_skip_held = clampf(_skip_held + (delta if held else -delta * 2.0), 0.0, Cut.SKIP_HOLD_S)
	if held and _skip_held >= Cut.SKIP_HOLD_S:
		_skip_held = 0.0
		_StoryNet.last_chain_step("skip")
		_skip()


func _finish() -> void:
	step = "done"
	t = 0.0
	_unblock_input()
	_cameras_rest()
	# A hot suit cooled a little: the player had their eyes on the dome.
	var lava = Level.map.get_node_or_null("StoryLavaField") if Level.map != null else null
	if lava != null and lava.has_method("set_heat_of"):
		for k in _Story.local_keepers():
			if lava.keeper_in_lava(k):
				lava.set_heat_of(k, minf(lava.heat_of(k), lava.HEAT_MAX * Cut.RESUME_HEAT_MAX))
	_unfreeze()
	if not Network.is_client():
		Data.apply(DONE_KEY, GameWorld.runTime)
	if _ship != null and _ship.mode != "dome":
		_ship.place_at_dome(false)
	events.append({"what": "step", "step": "done", "total": snappedf(total, 0.01)})
	ModLoaderLog.info("Last chain: the cutscene is over (%.1f s%s); play resumes" % [total, ", skipped" if skipped else ""], _Story.LOG)
	step_changed.emit("done")
	_mark_done(true)


# --- the cameras -----------------------------------------------------------------------

func _shot_zoom(cam) -> float:
	var vs: Vector2 = cam.get_viewport_rect().size
	var z: float = minf(vs.x / (_shot_w * 1.04), vs.y / Cut.SHOT_H)
	# A narrow split view crops the sides rather than show past the sky's top.
	z = maxf(z, vs.y / (Cut.SHOT_H * 1.25))
	return clampf(z, 0.5, Cut.SHOT_MAX_ZOOM)


# Where camera `c`'s keeper's own camera rests (what it will follow next).
func _rest_of(c: Dictionary) -> Vector2:
	var cam = c["cam"]
	var k = c["keeper"]
	if not is_instance_valid(cam) or not is_instance_valid(k):
		return c["from"]
	if k.isInsideDome and "cameraRestPositionInDome" in cam:
		return cam.get_parent().to_global(cam.cameraRestPositionInDome) if cam.get_parent() is Node2D else cam.cameraRestPositionInDome
	return k.global_position + (cam.targetOffset if "targetOffset" in cam else Vector2.ZERO)


func _rest_zoom(c: Dictionary) -> float:
	var cam = c["cam"]
	return float(cam.zoomStagePx) if "zoomStagePx" in cam else float(c["z0"])


static func _smoother(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)


func _cameras() -> void:
	for pid in _cams:
		var c: Dictionary = _cams[pid]
		var cam = c["cam"]
		if not is_instance_valid(cam):
			continue
		var at: Vector2 = c["from"]
		var z: float = c["z0"]
		var zs: float = _shot_zoom(cam) if _has_dome else z
		match step:
			"hold":
				at = c["from"].lerp(c["hold_end"], _smoother(t / (Cut.HOLD_S * 0.8)))
			"rise":
				var u: float = clampf(t / _rise_s, 0.0, 1.0)
				var s: float = _smoother(u)
				at = c["hold_end"].lerp(_shot_c, s)
				z = exp(lerpf(log(float(c["z0"])), log(zs), s)) * (1.0 - Cut.ZOOM_DIP * sin(u * PI))
			"return":
				var u: float = clampf(t / _ret_s, 0.0, 1.0)
				var s: float = _smoother(u)
				at = _shot_c.lerp(_rest_of(c), s)
				z = exp(lerpf(log(zs), log(_rest_zoom(c)), s)) * (1.0 - Cut.ZOOM_DIP * 0.6 * sin(u * PI))
			_:
				at = _shot_c
				z = zs
		cam.global_position = at
		cam.zoom = Vector2(z, z)


func _cameras_rest() -> void:
	for pid in _cams:
		var c: Dictionary = _cams[pid]
		var cam = c["cam"]
		if not is_instance_valid(cam):
			continue
		cam.global_position = _rest_of(c)
		cam.zoom = Vector2.ONE * _rest_zoom(c)


# --- the look ------------------------------------------------------------------------------

func _rumble(delta: float, amount: float, every: float) -> void:
	_rumble_acc += delta
	if _rumble_acc >= every:
		_rumble_acc = 0.0
		InputSystem.shake(amount, every * 1.6, 22.0)


# Something climbs through the rock with the camera: its glow and the light in
# the cracks round it, and dust.
func _burrow(delta: float) -> void:
	var head: Vector2 = _burrow_head()
	_glint_acc += delta * Cut.GLINTS_PER_S
	while _glint_acc >= 1.0:
		_glint_acc -= 1.0
		var p: Vector2 = head + Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-30, 50))
		var pts := PackedVector2Array([Vector2.ZERO])
		var dir := Vector2.from_angle(_rng.randf_range(0, TAU))
		for j in 3:
			pts.append(pts[j] + dir.rotated(_rng.randf_range(-0.8, 0.8)) * _rng.randf_range(5, 11))
		var life: float = _rng.randf_range(0.6, 1.1)
		_glints.append([p, life, life, pts])


func _burrow_head() -> Vector2:
	var u: float = clampf(t / _rise_s + Cut.BURROW_LEAD, 0.0, 1.0)
	var to: Vector2 = _hole + Vector2(0, 60) if _has_dome else _shot_c
	return _burrow_from.lerp(to, _smoother(u))


func _pebble(at: Vector2, up: float) -> void:
	_debris.append({"p": at + Vector2(0, -1), "v": Vector2(_rng.randf_range(-40, 40), -_rng.randf_range(up * 0.4, up)), "s": float(1 + _rng.randi() % 3),
		"col": EARTH[_rng.randi() % EARTH.size()], "life": _rng.randf_range(0.8, 1.6), "rest": false})


func _step_fx(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 2.6)
	if step != "mend":
		_hull_glow = maxf(0.0, _hull_glow - delta * 2.0)
	if step in ["carry", "set", "mend", "release", "dock", "beat", "return", "done"]:
		_crack_glow = maxf(0.0, _crack_glow - delta * 0.6)
	for i in range(_glints.size() - 1, -1, -1):
		_glints[i][1] -= delta
		if _glints[i][1] <= 0.0:
			_glints.remove_at(i)
	for i in range(_debris.size() - 1, -1, -1):
		var d: Dictionary = _debris[i]
		d["life"] -= delta
		if d["life"] <= 0.0:
			_debris.remove_at(i)
			continue
		if d["rest"]:
			continue
		if d.get("dust", false):
			d["v"] *= 1.0 - delta * 1.5
			d["p"] += d["v"] * delta
			continue
		d["v"].y += 620.0 * delta
		d["p"] += d["v"] * delta
		if d["p"].y >= 0.0 and d["v"].y > 0.0:
			d["p"].y = 0.0
			if d["v"].y > 120.0:
				d["v"] = Vector2(d["v"].x * 0.5, -d["v"].y * 0.3)
			else:
				d["rest"] = true


func _draw() -> void:
	# The climb through the rock.
	if step == "rise":
		var head: Vector2 = to_local(_burrow_head())
		var f: float = clampf(t / 0.4, 0.0, 1.0) * clampf((_rise_s - t) / 0.5, 0.0, 1.0)
		for k in 16:
			var r: float = Cut.BURROW_GLOW_R * (0.25 + k * 0.14)
			draw_circle(head, r, Color(Pix.VIOLET, 0.022 * f))
		draw_circle(head, Cut.BURROW_GLOW_R * 0.18, Color(Pix.VIOLET_LIGHT, 0.25 * f))
	for g in _glints:
		var a: float = clampf(g[1] / g[2], 0.0, 1.0)
		var o: Vector2 = to_local(g[0])
		var pts: PackedVector2Array = g[3]
		for j in pts.size() - 1:
			draw_line((o + pts[j]).round(), (o + pts[j + 1]).round(), Color("0a0612", a), 3.0)
			draw_line((o + pts[j]).round(), (o + pts[j + 1]).round(), Color(Pix.VIOLET_LIGHT, a), 1.0)
	if not _has_dome:
		return
	var hole: Vector2 = to_local(_hole)
	# The broken ground.
	if _crack_grow > 0.0:
		var glow: float = maxf(_crack_glow, _scar * 0.35)
		# The finale's cracks, drawn bigger (wider, and thicker lines).
		if _crack_glow > 0.0:
			_Pix.ellipse(self, hole + Vector2(0, -2), 70.0 * _crack_grow, 12.0 * _crack_grow, Color(Pix.VIOLET, 0.22 * _crack_glow * (0.8 + 0.2 * sin(total * 14.0))), -1.0, 1.0)
		draw_set_transform(hole, 0.0, Vector2(2.3, 1.7))
		_ST.draw_cracks(self, Vector2.ZERO, _cracks, _crack_grow, glow)
		draw_set_transform(hole, 0.0, Vector2(2.0, 1.6))
		_ST.draw_light(self, Vector2.ZERO, _crack_seed, _crack_grow, _crack_glow * _crack_glow * (0.6 if step == "crack" else 1.0), true)
		draw_set_transform(Vector2.ZERO)
	if STEPS.find(step) >= STEPS.find("burst") or step == "done":
		_Pix.ellipse(self, hole + Vector2(0, -1), 40.0, 6.0, Color("0a0612", 0.85 if step != "done" else 0.85 * _scar), -1.0, 0.1)
	for d: Dictionary in _debris:
		var a: float = clampf(d["life"] * 1.5, 0.0, 1.0) * d["col"].a
		var p: Vector2 = hole + d["p"]
		draw_rect(Rect2((p - Vector2(d["s"], d["s"]) * 0.5).round(), Vector2(d["s"], d["s"])), Color(d["col"], a))
	if _flash > 0.0 and step in ["burst", "carry"]:
		var cw: float = 34.0 * _flash
		var chh: float = 260.0
		draw_rect(Rect2(hole + Vector2(-cw, -chh), Vector2(cw * 2.0, chh)), Color(Pix.VIOLET_LIGHT, _flash * 0.35))
		draw_rect(Rect2(hole + Vector2(-cw * 0.4, -chh), Vector2(cw * 0.8, chh)), Color(1, 1, 1, _flash * 0.55))
		var run: float = (1.0 - _flash) * 130.0
		draw_rect(Rect2((hole + Vector2(-run - 14.0, -1)).round(), Vector2(14, 2)), Color(Pix.SCLERA, _flash))
		draw_rect(Rect2((hole + Vector2(run, -1)).round(), Vector2(14, 2)), Color(Pix.SCLERA, _flash))
	# The horror's light over the hull as it mends it.
	if _hull_glow > 0.0 and _ship != null:
		draw_set_transform_matrix(get_global_transform().affine_inverse() * _ship.carrier.get_global_transform())
		var col := Color(Pix.VIOLET_LIGHT, 0.55 * _hull_glow)
		for poly in [ShipArt.HULL, ShipArt.VISOR, ShipArt.BRIDGE, ShipArt.FIN, ShipArt.ENG_TOP, ShipArt.ENG_BOT, ShipArt.POD]:
			draw_colored_polygon(PackedVector2Array(poly), col)
		draw_set_transform(Vector2.ZERO)
	if _flash > 0.0 and step == "mend" and _ship != null:
		draw_circle(to_local(_ship.carrier.global_position), 150.0 * (1.2 - _flash * 0.4), Color(Pix.VIOLET_LIGHT, _flash * 0.18))
	_draw_skip_ring()


# The skip's ring, bottom right of the first view, filling while held.
func _draw_skip_ring() -> void:
	if _skip_held <= 0.0 or _cams.is_empty():
		return
	var c: Dictionary = _cams[_cams.keys()[0]]
	var cam = c["cam"]
	if not is_instance_valid(cam):
		return
	var z: float = cam.zoom.x
	var vs: Vector2 = cam.get_viewport_rect().size / z
	var at: Vector2 = to_local(cam.get_screen_center_position() + vs * 0.5 - Vector2(48, 48) / z)
	var r: float = 18.0 / z
	var f: float = _skip_held / Cut.SKIP_HOLD_S
	draw_arc(at, r, 0.0, TAU, 40, Color(0, 0, 0, 0.55), 7.0 / z)
	draw_arc(at, r, -PI * 0.5, -PI * 0.5 + TAU * f, 40, Color(Pix.SCLERA, 0.95), 4.0 / z)
	# A fast-forward mark: two small triangles.
	for dx in [-6.0, 0.0]:
		draw_colored_polygon(PackedVector2Array([at + Vector2(dx, -5.0) / z, at + Vector2(dx + 6.0, 0.0) / z, at + Vector2(dx, 5.0) / z]), Color(Pix.SCLERA, 0.95))
