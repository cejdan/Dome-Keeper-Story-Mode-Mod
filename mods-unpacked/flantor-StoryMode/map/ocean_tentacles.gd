extends Node2D

# The lava ocean's two climbable tentacles (#364, End game 2.0 #363). They rise
# out of the lava from the ocean's floor to just under its ceiling, chained
# down, waving barely at first ("alive but held down") and wider and faster
# with every chain broken. They are how the Beastmaster and the Infiltrator
# get around the ocean (#324). Each is a map/tentacle_rig.gd: moving bodies
# keepers stand on, grab and hook.
#
# Placement comes from the map generator (map/story_gen.gd place_tentacles,
# meta "story_tentacles"), so every peer builds the same two from the map facts.
#
# Wake: the chains broken, 0..10 (data/tentacles.gd CHAINS), saved in Data
# (CHAINS_KEY) and mapped smoothly onto the test room's wake stages 0..4. The
# end-game state (endgame/end_game.gd, #365) calls set_chains_broken(n) on the
# host as each chain anchor breaks and after a load; `--chains=N` (dev) breaks
# the first N anchors at a run's start (map/chain_anchors.gd).
#
# Online (#222): the host owns the chains broken (Data, which clients get with
# everything else) and the wave clock: it sends each rig's clock, swing and
# speed to clients NET_HZ times a second (net/story_net.gd tentacle_clock), and
# a client's copy glides onto them, so every peer's keeper stands on the same
# tentacle.
#
# Cost: 2 x ~30 bodies posed per physics frame while any keeper is near the
# ocean or any view shows a tentacle, nothing but the clock otherwise; each
# segment redraws only when it crosses into or out of the lava.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const TentData = preload("res://mods-unpacked/flantor-StoryMode/data/tentacles.gd")
static var _TentData = TentData  # calls go through this: lazy_preload makes const-preload calls slow
const Rig = preload("res://mods-unpacked/flantor-StoryMode/map/tentacle_rig.gd")
static var _Rig = Rig  # calls go through this: lazy_preload makes const-preload calls slow
const StoryNet = preload("res://mods-unpacked/flantor-StoryMode/net/story_net.gd")
static var _StoryNet = StoryNet  # calls go through this: lazy_preload makes const-preload calls slow

const NAME := "StoryOceanTentacles"
const META := "story_tentacles"
const CHAINS_KEY := "team1.story.chainsbroken"
const T := 24.0
const SEEN_EVERY := 0.5
const NEAR_EVERY := 0.25
const NEAR_GROW := 6.0 * T       # a keeper this close to a tentacle's reach wakes the pose
const NET_HZ := 5.0
const NET_SNAP := 0.6            # clock error (radians of wave) a client jumps instead of gliding

var rigs: Array = []
var places: Array = []           # the generator's placements
var seen: bool = false
var near: bool = false           # posing (a keeper near or a view on it)
var lava_y: float = INF
var _bounds: Array = []          # per rig: Rect2 it can reach, global
var _probe: Array = []
var _seen_acc: float = 0.0
var _near_acc: float = 0.0
var _chains: int = -1
var _net_t: float = 0.0
var _net: PackedFloat32Array = PackedFloat32Array()   # client: the host's last word
var _net_age: float = 0.0
var net_client: bool = false


static func find():
	if Level.map == null or not is_instance_valid(Level.map):
		return null
	return Level.map.get_node_or_null(NAME)


# --- the chains (the API for #365) ----------------------------------------------

# Chains broken so far, 0..CHAINS (saved with the run).
static func chains_broken() -> int:
	return clampi(int(Data.ofOr(CHAINS_KEY, 0)), 0, _TentData.CHAINS)


# The host sets the chains broken (the chain anchors, #365, after each break;
# also safe to call again after a load). The tentacles ease to the new wake.
# A client's call does nothing: its anchors ask the host.
static func set_chains_broken(n: int) -> void:
	if Network.is_client():
		push_warning("Story Mode: set_chains_broken on a client is ignored (the host owns it)")
		return
	n = clampi(n, 0, _TentData.CHAINS)
	if int(Data.ofOr(CHAINS_KEY, -1)) == n:
		return
	Data.apply(CHAINS_KEY, n)
	ModLoaderLog.info("Ocean tentacles: %d of %d chains broken, wake %.2f" % [n, _TentData.CHAINS, wake_for(n)], _Story.LOG)


# The wake stage (0..4, smooth) for `n` chains broken.
static func wake_for(n: int) -> float:
	return 4.0 * clampf(float(n) / float(_TentData.CHAINS), 0.0, 1.0)


static func _stage_value(table: Array, w: float) -> float:
	var i: int = clampi(int(floor(w)), 0, table.size() - 1)
	var j: int = mini(i + 1, table.size() - 1)
	return lerpf(float(table[i]), float(table[j]), clampf(w - float(i), 0.0, 1.0))


static func share_for(w: float) -> float:
	return _stage_value(_TentData.WAKE_SHARE, w)


static func speed_for(w: float) -> float:
	return _stage_value(_TentData.WAKE_SPEED, w)


# --- setup ----------------------------------------------------------------------

func setup(map) -> bool:
	var td = map.tileData
	places = td.get_meta(META, [])
	var ocean: Dictionary = td.get_meta("story_ocean", {})
	if places.is_empty() or ocean.is_empty():
		return false
	name = NAME
	z_index = 7          # over the lava (6), with the chains, under the keepers
	net_client = Network.is_client()
	lava_y = map.getTilePos(Vector2(0, int(ocean["top"]))).y - T * 0.5
	var i: int = 0
	for p: Dictionary in places:
		var x: int = int(p["x"])
		var base_row: int = int(p["base_row"])
		var tip_row: int = int(p["tip_row"])
		var r = _Rig.new()
		r.name = "OceanTentacle%d" % i
		r.base = map.getTilePos(Vector2(x, base_row)) + Vector2(0.0, -T * 0.5 + 8.0)
		var top_y: float = map.getTilePos(Vector2(x, tip_row)).y - T * 0.5
		var length: float = r.base.y - top_y - _TentData.PAD_HEIGHT
		r.count = int(p["segments"])
		r.seg_len = length / float(r.count)
		r.base_angle = -PI / 2.0
		r.width0 = _TentData.WIDTH_BASE
		r.width1 = _TentData.WIDTH_TIP
		r.pad_width = _TentData.PAD_WIDTH
		r.pad_height = _TentData.PAD_HEIGHT
		r.tip_level = _TentData.TIP_LEVEL
		r.sweep = _TentData.SWEEP_TILES * T
		r.wave_k = _TentData.WAVE_K
		r.tempo = _TentData.TEMPO
		r.ease_share = _TentData.EASE_SHARE
		r.ease_speed = _TentData.EASE_SPEED
		r.phase = 1.9 * float(i)
		r.lava_y = lava_y
		var reach: float = r.sweep + _TentData.PAD_WIDTH
		_bounds.append(Rect2(r.base.x - reach, top_y, reach * 2.0, r.base.y - top_y))
		add_child(r)
		r.add_child(_Splash.new())
		rigs.append(r)
		# Seen once the cells round its tip or along its column are in sight.
		for y in range(tip_row - 1, base_row):
			_probe.append(Vector2(x, y))
		for dx in [-3, -2, -1, 1, 2, 3]:
			_probe.append(Vector2(x + dx, tip_row))
		i += 1
	_apply_chains(true)
	visible = false
	_check_seen()
	near = true      # so the first check settles every rig's `active`
	refresh_near()
	ModLoaderLog.info("Ocean tentacles: %d, %s segments, %d chains broken" % [rigs.size(), str(rigs.map(func(r): return r.count)), chains_broken()], _Story.LOG)
	return true


func _apply_chains(snap: bool) -> void:
	var n: int = chains_broken()
	if n == _chains and not snap:
		return
	_chains = n
	var w: float = wake_for(n)
	for r in rigs:
		r.target_share = share_for(w)
		r.target_speed = speed_for(w)
		if snap:
			r.snap_to_target()


func _check_seen() -> void:
	var vis: Dictionary = Level.map.visibleTileCoords
	for c in _probe:
		if vis.has(c):
			seen = true
			visible = true
			return


# Posing only matters where a keeper can touch a tentacle or a view shows one.
# Checked a few times a second; call it after moving a keeper by hand
# (a teleport) so the bodies are posed before it lands.
func refresh_near() -> void:
	var on: bool = false
	var keepers: Array = Keepers.getAll()
	for b: Rect2 in _bounds:
		var g: Rect2 = b.grow(NEAR_GROW)
		for k in keepers:
			if k != null and is_instance_valid(k) and g.has_point(k.global_position):
				on = true
				break
		if not on and seen:
			for v: Rect2 in _Story.view_rects(T):
				if v.intersects(b):
					on = true
					break
		if on:
			break
	if on != near:
		near = on
		for r in rigs:
			r.active = on   # the next physics frame poses it


# --- every frame ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_apply_chains(false)
	if net_client:
		_net_glide(delta)
	else:
		_net_host(delta)


func _process(delta: float) -> void:
	if not seen:
		_seen_acc += delta
		if _seen_acc >= SEEN_EVERY:
			_seen_acc = 0.0
			_check_seen()
	_near_acc += delta
	if _near_acc >= NEAR_EVERY:
		_near_acc = 0.0
		refresh_near()


# Where every rig's clock, swing and speed stand: [t, share, speed] per rig.
func clock_state() -> PackedFloat32Array:
	var d := PackedFloat32Array()
	# A beat or the pause menu holds the host's tentacles: clients hold too.
	var held: bool = GameWorld.paused
	for r in rigs:
		d.append_array([r.t, r.share, 0.0 if held else r.speed])
	return d


func _net_host(delta: float) -> void:
	if Network.is_offline_mode() or Network.clients.is_empty():
		return
	_net_t -= delta
	if _net_t > 0.0:
		return
	_net_t = 1.0 / NET_HZ
	_StoryNet.tentacle_clock(clock_state())


# A client: the host's clock, swing and speed.
func net_apply(d: PackedFloat32Array) -> void:
	if not net_client or d.size() < rigs.size() * 3:
		return
	_net = d
	_net_age = 0.0


# A client's rigs run on their own clocks and glide onto the host's: its
# last word plus the time since, at its speed.
func _net_glide(delta: float) -> void:
	if _net.is_empty():
		return
	_net_age += delta
	for i in rigs.size():
		var r = rigs[i]
		var want: float = _net[i * 3] + _net_age * _net[i * 3 + 2] * r.tempo
		var err: float = want - r.t
		if absf(err) > NET_SNAP:
			r.t = want
		else:
			r.t += err * minf(1.0, delta * 4.0)
		r.share = _net[i * 3 + 1]
		r.target_share = r.share
		r.speed = _net[i * 3 + 2]
		r.target_speed = r.speed


# --- the look: where a tentacle leaves the lava ----------------------------------

# A hot collar and ripples where the body breaks the lava's surface, drawn
# over the segments.
class _Splash extends Node2D:
	var _rig
	var _t: float = 0.0

	func _ready() -> void:
		_rig = get_parent()
		z_index = 1
		var mat := CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		material = mat

	func _process(delta: float) -> void:
		if _rig.active and is_visible_in_tree():
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var ly: float = _rig.lava_y
		if ly == INF or _rig.segments.is_empty():
			return
		# The root: a flared foot sunk into the ocean's floor, not a round end.
		var s0 = _rig.segments[0]
		var root: Vector2 = to_local(s0.global_transform * Vector2(-s0.length * 0.5, 0.0))
		var rw: float = s0.w_root * 0.5
		var foot := PackedVector2Array([root + Vector2(-rw, -6.0), root + Vector2(rw, -6.0), root + Vector2(rw * 1.9, 10.0), root + Vector2(-rw * 1.9, 10.0)])
		draw_colored_polygon(foot, Color(0.10, 0.02, 0.05))
		draw_polyline(PackedVector2Array([foot[3], foot[0], foot[1], foot[2]]), Color(1.0, 0.86, 0.45, 0.8), 1.5)
		# The segment that crosses the surface.
		for s in _rig.segments:
			var a: Vector2 = s.global_transform * Vector2(-s.length * 0.5, 0.0)
			var b: Vector2 = s.global_transform * Vector2(s.length * 0.5, 0.0)
			if (a.y - ly) * (b.y - ly) > 0.0:
				continue
			var u: float = (ly - a.y) / (b.y - a.y) if b.y != a.y else 0.5
			var p: Vector2 = to_local(a.lerp(b, u))
			var hw: float = lerpf(s.w_root, s.w_tip, u) * 0.5 + 3.0
			# Ripples running out along the surface.
			for k in 3:
				var f: float = fposmod(_t * 0.6 + float(k) / 3.0, 1.0)
				var c := Color(1.0, 0.85, 0.4, 0.55 * (1.0 - f))
				var w: float = hw + 6.0 + f * 30.0
				draw_line(p + Vector2(-w, 0.5), p + Vector2(-w + 8.0, 0.5), c, 2.0)
				draw_line(p + Vector2(w - 8.0, 0.5), p + Vector2(w, 0.5), c, 2.0)
			# The collar: bright where the lava clings to it.
			draw_rect(Rect2(p + Vector2(-hw, -2.0), Vector2(hw * 2.0, 4.0)), Color(1.0, 0.62, 0.18))
			draw_rect(Rect2(p + Vector2(-hw + 2.0, -1.0), Vector2(hw * 2.0 - 4.0, 2.0)), Color(1.0, 0.92, 0.55))
			return
