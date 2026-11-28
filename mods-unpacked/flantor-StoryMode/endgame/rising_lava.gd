extends Node2D

# The rising lava (#369, End game 2.0 map #363): after the last chain the
# lava rises from the ocean up through the mine. It is the timer: no clock and
# no HUD, only the lava behind the keeper and a rumble that grows as it comes.
# Values in data/rising_lava.gd.
#
# The level is one number, the lava's surface in tile rows (`row`, smaller is
# higher), rising at a set speed. The lava field turns it into lava
# (lava/lava_field.gd, "the flood line": a thin band of real cells at the top,
# implied lava under it, rock stays rock).
#
#   armed     the last chain broke (EndGame.when_free, live); the cutscene plays
#   rising    from the end of the last-chain cutscene (LastChain.when_done,
#             live): from the ocean's surface, slowly at first, then at the
#             set speed. A load resumes it where it was saved (and eases in
#             again).
#   stopped   a keeper entered the lair (EndGame.when_lair_entered): it never
#             rises again (the boss state also stops it; after the boss dies it
#             stays where it is). What is under the line stays lava.
#   surfaced  it reached the surface (data SURFACE_ROW) with nobody boarded or
#             fighting: the "too late" loss (Storymode.too_late("surface")).
#
# The rule that comes with it: from the last chain until a keeper enters the
# lair, a suit death (lava, the depth's heat or gas) ends the run, "too late"
# (Storymode.too_late), instead of the recall to the dome: a recall would be a
# free ride to the ship. lava_field.gd overheat() asks RisingLava.ends_run().
#
# The warning: each local keeper's camera shakes, more the closer the lava's
# surface is below it, with a low rumble loop (made in code) and now and then
# a jolt and a deep boom. All of it fades out when the rise stops.
#
# Saves: Data STATE_KEY (written by the host at each change) and ROW_KEY (at
# each change and every save, serialize()). Online the host owns the level and
# sends it (StoryNet.flood_level: the row and its speed, a few times a second;
# StoryNet.flood_state on a change); each client extrapolates between words and
# fills its own band from it. A late joiner reads Data, then the stream.
#
# API (#370 and anyone after):
#   RisingLava.find()               the node (under the map, every peer)
#   RisingLava.state() -> String    "" | armed | rising | stopped | surfaced
#   RisingLava.level_row() -> float the lava's surface, tile rows (INF before)
#   RisingLava.level_y() -> float   ... global y (INF before)
#   RisingLava.is_rising() -> bool
#   RisingLava.ends_run() -> bool   a suit death now is the "too late" loss
#   node.started(live) / node.stopped(why) / node.surfaced()   signals (every peer)
#   node.closeness                  playerId -> 0..1, the warning's strength (playtests)

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const EndGame = preload("res://mods-unpacked/flantor-StoryMode/endgame/end_game.gd")
static var _EndGame = EndGame  # calls go through this: lazy_preload makes const-preload calls slow
const LastChain = preload("res://mods-unpacked/flantor-StoryMode/endgame/last_chain.gd")
static var _LastChain = LastChain  # calls go through this: lazy_preload makes const-preload calls slow
const StoryNet = preload("res://mods-unpacked/flantor-StoryMode/net/story_net.gd")
static var _StoryNet = StoryNet  # calls go through this: lazy_preload makes const-preload calls slow
const Sfx = preload("res://mods-unpacked/flantor-StoryMode/boss/sfx.gd")
static var _Sfx = Sfx  # calls go through this: lazy_preload makes const-preload calls slow
const Flood = preload("res://mods-unpacked/flantor-StoryMode/data/rising_lava.gd")

const NAME := "StoryRisingLava"
const STATE_KEY := "team1.story.floodstate"   # "" | armed | rising | stopped | surfaced
const ROW_KEY := "team1.story.floodrow"       # float: the level (rows) at the last change or save
const TILE := 24.0

signal started(live: bool)
signal stopped(why: String)
signal surfaced()

static var events: Array = []       # playtests: {"what", ...}
static var _lost: Dictionary = {}    # "<seed>:<playerId>" -> true: that keeper's death was reported

var row: float = INF                # the lava's surface (rows)
var speed_px: float = Flood.RISE_PX_PER_S
var start_row: float = 0.0          # the ocean's surface
var surface_row: float = 0.0
var closeness: Dictionary = {}      # playerId -> 0..1
var proc_us: int = 0                # this node's own time (dev timing)

var _state: String = ""
var _map = null
var _lava = null
var _rise_t: float = 0.0            # seconds risen since the start or the load (the ease-in)
var _rate: float = 0.0              # rows a second right now (host)
var _fade: float = 1.0              # the warning after the rise stopped: 1 -> 0
var _shake_t: Dictionary = {}       # playerId -> seconds to the next shake
var _jolt_t: Dictionary = {}        # playerId -> seconds to the next jolt
var _rumble: AudioStreamPlayer = null
var _net_t: float = 0.0
var _host_row: float = INF          # client: the host's last word
var _host_rate: float = 0.0
var _host_at: float = 0.0
var _clock: float = 0.0
var _rng := RandomNumberGenerator.new()


static func find():
	if Level.map == null or not is_instance_valid(Level.map):
		return null
	return Level.map.get_node_or_null(NAME)


static func state() -> String:
	var n = find()
	if n != null:
		return n._state
	return str(Data.ofOr(STATE_KEY, ""))


static func level_row() -> float:
	var n = find()
	return n.row if n != null else INF


static func level_y() -> float:
	var n = find()
	if n == null or n._lava == null or not n._lava.flood_active():
		return INF
	return n._lava.flood_y()


static func is_rising() -> bool:
	return state() == "rising"


# A suit death now (lava, the depth's heat, gas) ends the run: from the last
# chain until a keeper enters the lair (then the boss sequence's hearts take
# over; after the boss, a death is a recall again).
static func ends_run() -> bool:
	if not _Story.is_story():
		return false
	var s: String = state()
	if not (s in ["armed", "rising", "surfaced"]):
		return false
	return _EndGame.is_free() and not _EndGame.is_lair_entered() and str(Data.ofOr(_Story.BOSS_STATE, "")) == ""


# A keeper of this instance died in the suit while ends_run(): the run is
# lost. The host decides (a client's keeper asks it).
static func lost_in_lava(keeper, cause: String) -> void:
	# Once per keeper and run (the bar stays full while the ending starts).
	var key: String = "%d:%s" % [Level.levelSeed, keeper.playerId]
	if _lost.has(key) or (Level.mode != null and Level.mode.has_method("is_ending") and Level.mode.is_ending()):
		return
	_lost[key] = true
	events.append({"what": "death", "pid": keeper.playerId, "cause": cause})
	ModLoaderLog.info("Rising lava: %s died (%s): too late" % [keeper.playerId, cause], _Story.LOG)
	if Network.is_client():
		_StoryNet.too_late(keeper.playerId, cause)
	elif Level.mode != null and Level.mode.has_method("too_late"):
		Level.mode.too_late(cause, keeper.playerId)


# --- setup ------------------------------------------------------------------------

func setup(map) -> bool:
	if not _Story.is_story():
		return false
	var om: Dictionary = map.tileData.get_meta("story_ocean", {})
	_lava = map.get_node_or_null("StoryLavaField")
	if om.is_empty() or _lava == null:
		return false
	_map = map
	name = NAME
	_lost.clear()               # a new map: a new run (even with the same seed)
	process_priority = 110     # after the cutscene (100) and the cameras
	_rng.seed = hash([Level.levelSeed, "rising"])
	start_row = float(int(om["top"]))
	surface_row = float(Flood.SURFACE_ROW)
	var secs: float = float(_Story.user_arg("rise", "0"))
	var px: float = float(_Story.user_arg("risespeed", "0"))
	if secs > 0.0:
		speed_px = (start_row - surface_row) * TILE / secs
	elif px > 0.0:
		speed_px = px
	add_to_group("saveable")
	# A loaded run (or a late joiner) has the level in Data: the lava goes
	# back where it was at once.
	_state = str(Data.ofOr(STATE_KEY, ""))
	var r = Data.ofOr(ROW_KEY, null)
	if _state in ["rising", "stopped", "surfaced"] and r != null:
		row = float(r)
		_lava.flood_set(row)
		_fade = 1.0 if _state == "rising" else 0.0
		events.append({"what": "restored", "state": _state, "row": snappedf(row, 0.01)})
		ModLoaderLog.info("Rising lava: restored %s at row %.2f" % [_state, row], _Story.LOG)
	_EndGame.when_free(_on_free)
	_LastChain.when_done(_on_cut_done)
	_EndGame.when_lair_entered(_on_lair)
	ModLoaderLog.info("Rising lava: ready (%.0f px/s, %.0f s from the ocean to the surface)" % [speed_px, (start_row - surface_row) * TILE / speed_px], _Story.LOG)
	return true


func _on_free(live: bool) -> void:
	if not live or Network.is_client() or _state != "":
		return
	_set_state("armed")


func _on_cut_done(live: bool) -> void:
	if Network.is_client():
		return
	if live:
		start(true)
		return
	match _state:
		"armed":
			# Saved while the cutscene played: it starts now.
			start(true)
		"rising":
			_rise_t = 0.0
			_send_state(false)
		"":
			# A run made free by a dev route rises only when asked (--flood).
			if _Story.has_user_arg("flood") and _EndGame.is_free():
				start(true)


func _on_lair(_live: bool) -> void:
	if _state in ["armed", "rising"]:
		stop("lair")


# --- the host's moves ----------------------------------------------------------------

# Host: the rise begins at the ocean's surface (or where it was, after a load).
func start(live: bool) -> void:
	if Network.is_client() or _state in ["rising", "stopped", "surfaced"]:
		return
	if row == INF:
		row = start_row
	_rise_t = 0.0
	_fade = 1.0
	_lava.flood_set(row)
	_set_state("rising")
	_send_state(live)
	_started_fx(live)


# Host: it stops for good. `why`: "lair", "boss".
func stop(why: String) -> void:
	if Network.is_client():
		# The lair's word reached this client: stop here at once (the host's
		# state follows).
		if _state == "rising":
			_state = "stopped"
			_stopped_fx(why)
		return
	if _state == "stopped" or _state == "surfaced":
		return
	_set_state("stopped")
	_send_state(false)
	_stopped_fx(why)


# Dev and playtests (host): the rise at `at` (rows; default the ocean), now.
func dev_start(at: float = INF) -> void:
	if Network.is_client():
		return
	if at != INF:
		row = at
	start(true)


# Dev and playtests (host): jumps the level to `at` (it only goes up).
func dev_set_row(at: float) -> void:
	if Network.is_client() or _state != "rising":
		return
	row = minf(row, at)
	_lava.flood_set(row)


func _set_state(s: String) -> void:
	_state = s
	if not Network.is_client():
		Data.apply(STATE_KEY, s)
		if row != INF:
			Data.apply(ROW_KEY, row)
	events.append({"what": "state", "state": s, "row": snappedf(row, 0.01) if row != INF else null, "t": snappedf(GameWorld.runTime, 0.01)})
	ModLoaderLog.info("Rising lava: %s (row %s)" % [s, "%.2f" % row if row != INF else "-"], _Story.LOG)


# Vanilla's save asks every "saveable" node first: the level goes into Data.
func serialize() -> Dictionary:
	if not Network.is_client() and _state != "" and row != INF:
		Data.apply(ROW_KEY, row)
	return {"meta.priority": 8990, "meta.kind": "storyflood"}


# --- every frame ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if _map == null or not is_instance_valid(_map):
		return
	var us0: int = Time.get_ticks_usec()
	_clock += delta
	if _state == "rising":
		if Network.is_client():
			_client_follow()
		else:
			_host_rise(delta)
	elif _fade > 0.0:
		_fade = maxf(0.0, _fade - delta / Flood.STOP_FADE_S)
	_warn(delta)
	_tentacles()
	proc_us += Time.get_ticks_usec() - us0


func _halted() -> bool:
	if GameWorld.paused:
		return true
	return Level.mode != null and Level.mode.has_method("is_ending") and Level.mode.is_ending()


func _host_rise(delta: float) -> void:
	_rate = 0.0
	if str(Data.ofOr(_Story.BOSS_STATE, "")) != "":
		stop("boss")
		return
	if not _halted():
		_rise_t += delta
		var share: float = lerpf(Flood.START_SHARE, 1.0, smoothstep(0.0, Flood.RAMP_S, _rise_t))
		_rate = speed_px * share / TILE
		row = maxf(surface_row, row - _rate * delta)
		_lava.flood_set(row)
		if row <= surface_row:
			_reach_surface()
			return
	_net_t += delta
	if _net_t >= Flood.NET_EVERY:
		_net_t = 0.0
		_StoryNet.flood_level(row, _rate, _state)


func _reach_surface() -> void:
	_set_state("surfaced")
	_send_state(false)
	surfaced.emit()
	events.append({"what": "surfaced", "t": snappedf(GameWorld.runTime, 0.01)})
	if Level.mode != null and Level.mode.has_method("too_late"):
		Level.mode.too_late("surface", "")


# --- online ----------------------------------------------------------------------------

func _send_state(live: bool) -> void:
	if Network.is_client():
		return
	_StoryNet.flood_state(row, _state, live)


# Client: the host's level, a few times a second.
func net_level(at: float, rate: float, s: String) -> void:
	_host_row = at
	_host_rate = rate
	_host_at = _clock
	if s != _state:
		net_state(at, s, false)


# Client: the host's state changed (or a stream word says another state).
func net_state(at: float, s: String, live: bool) -> void:
	_host_row = at
	_host_at = _clock
	var was: String = _state
	_state = s
	row = minf(row, at) if row != INF else at
	if s != "armed" and s != "":
		_lava.flood_set(row)
	events.append({"what": "net_state", "state": s, "row": snappedf(at, 0.01), "live": live})
	if s == "rising" and was != "rising":
		_fade = 1.0
		_started_fx(live)
	elif s == "stopped" and was == "rising":
		_stopped_fx("host")
	elif s == "surfaced":
		surfaced.emit()


func _client_follow() -> void:
	if _host_row == INF:
		return
	var est: float = _host_row
	if not _halted():
		est -= _host_rate * minf(_clock - _host_at, 0.6)
	est = maxf(est, surface_row)
	if row == INF or est < row:
		row = est
		_lava.flood_set(row)


# --- the look and the sound ------------------------------------------------------------------

func _started_fx(live: bool) -> void:
	started.emit(live)
	events.append({"what": "started", "live": live, "row": snappedf(row, 0.01)})
	if not live:
		return
	_Sfx.play("roar", -3.0, 0.62)
	_Sfx.play("burrow", -4.0, 0.7)
	for k in _Story.local_keepers():
		var cam = _cam_of(k)
		if cam != null:
			cam.shake(Flood.START_SHAKE, 1.1, 14.0)


func _stopped_fx(why: String) -> void:
	stopped.emit(why)
	events.append({"what": "stopped", "why": why, "row": snappedf(row, 0.01)})
	# A deep groan far below: it has turned to face whoever came.
	_Sfx.play("roar", -12.0, 0.48)


func _cam_of(k):
	if Level.viewports == null or not is_instance_valid(Level.viewports) or k == null:
		return null
	var cam = Level.viewports.getPlayerCam(k.playerId)
	if cam == null or not is_instance_valid(cam) or not cam.is_inside_tree():
		return null
	return cam


# The warning, for each local keeper: how close the lava's surface is below
# it (0 far .. 1 at the screen's edge or in it), a camera shake and jolts that
# grow with it, and the rumble at the closest keeper's strength.
func _warn(delta: float) -> void:
	var on: bool = (_state == "rising" or _fade > 0.0) and _lava.flood_active() and not _halted()
	var loudest: float = 0.0
	var ly: float = _lava.flood_y() if on else INF
	for k in _Story.local_keepers():
		if k == null or not is_instance_valid(k):
			continue
		var pid: String = k.playerId
		var u: float = 0.0
		if on:
			var d: float = (ly - k.global_position.y) / TILE
			u = 1.0 - clampf((d - Flood.NEAR_ROWS) / (Flood.FAR_ROWS - Flood.NEAR_ROWS), 0.0, 1.0)
			if _lava.keeper_in_lava(k):
				u = 1.0
			u *= _fade if _state != "rising" else 1.0
		closeness[pid] = snappedf(u, 0.001)
		loudest = maxf(loudest, u)
		if u <= 0.01:
			continue
		var cam = _cam_of(k)
		if cam == null:
			continue
		_shake_t[pid] = float(_shake_t.get(pid, 0.0)) - delta
		if _shake_t[pid] <= 0.0:
			_shake_t[pid] = Flood.SHAKE_EVERY
			cam.shake(lerpf(Flood.SHAKE_MIN, Flood.SHAKE_MAX, pow(u, 1.5)), Flood.SHAKE_EVERY * 1.6, 18.0)
		if u >= Flood.JOLT_CLOSE and _state == "rising":
			_jolt_t[pid] = float(_jolt_t.get(pid, 1.0)) - delta
			if _jolt_t[pid] <= 0.0:
				var w: float = (u - Flood.JOLT_CLOSE) / (1.0 - Flood.JOLT_CLOSE)
				_jolt_t[pid] = lerpf(Flood.JOLT_EVERY[0], Flood.JOLT_EVERY[1], w) * _rng.randf_range(0.8, 1.25)
				cam.shake(Flood.JOLT_SHAKE * (0.6 + 0.4 * w), 0.6, 12.0)
				_Sfx.play("boom", lerpf(-20.0, -9.0, w), _rng.randf_range(0.45, 0.6))
	_rumble_at(loudest)


func _rumble_at(u: float) -> void:
	if u <= 0.01:
		if _rumble != null and _rumble.playing:
			_rumble.stop()
		return
	if DisplayServer.get_name() == "headless":
		return
	if _rumble == null:
		_rumble = AudioStreamPlayer.new()
		_rumble.stream = _make_rumble()
		_rumble.bus = &"Mine"
		add_child(_rumble)
	_rumble.volume_db = lerpf(Flood.RUMBLE_DB[0], Flood.RUMBLE_DB[1], u)
	_rumble.pitch_scale = 0.85 + 0.25 * u
	if not _rumble.playing:
		_rumble.play()


# A low rumble, made in code (no file to ship): brown noise through a low
# one-pole filter with a slow swell, looped, its end blended into its start.
static func _make_rumble() -> AudioStreamWAV:
	var rate := 22050
	var n: int = rate * 4
	var fade: int = rate / 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 369
	var s := PackedFloat32Array()
	s.resize(n + fade)
	var brown := 0.0
	var lp := 0.0
	var loudest := 0.0001
	for i in n + fade:
		brown = clampf(brown + rng.randf_range(-1.0, 1.0) * 0.02, -1.0, 1.0) * 0.998
		lp += (brown - lp) * 0.06
		var swell: float = 0.75 + 0.25 * sin(float(i) / float(rate) * TAU * 0.5) * sin(float(i) / float(rate) * TAU * 1.25 + 0.7)
		s[i] = lp * swell
		loudest = maxf(loudest, absf(s[i]))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v: float = s[i]
		if i < fade:
			var a: float = float(i) / float(fade)
			v = v * a + s[n + i] * (1.0 - a)
		data.encode_s16(i * 2, int(clampf(v / loudest * 0.85, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


# The ocean's climbable tentacles look soaked up to the lava's surface: it
# rises over them.
func _tentacles() -> void:
	if not _lava.flood_active():
		return
	var t = _map.get_node_or_null("StoryOceanTentacles")
	if t == null:
		return
	var y: float = _lava.flood_y()
	if y < float(t.lava_y) - 0.5:
		t.lava_y = y
		for r in t.rigs:
			r.lava_y = y
