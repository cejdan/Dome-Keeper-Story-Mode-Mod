extends Node2D

# One climbable tentacle made of moving bodies (#364, from the #359 test room).
# Used by the lava ocean's two tentacles (map/ocean_tentacles.gd) and the dev
# test room (dev/dev_tentacle_test.gd).
#
# A chain of AnimatableBody2D segments on the tile layer (layer 1): keepers
# stand on it and wall-slide on its sides, the Beastmaster's claws and the
# Infiltrator's hook and kunai hit it. No "destructable" meta, so nothing mines
# it. Each segment tapers joint to joint (a rect per piece left a ledge at
# every joint that stopped a walking keeper) with a round knuckle on its lower
# joint; the tip is a club with a flat top (Pad) the Infiltrator can stand on.
# Grips on a moving body follow it through script extensions:
# extensions/content/keeper/keeper4/Tentacle.gd, Keeper4.gd and
# extensions/content/keeper/keeper3/Hook.gd look for the GRIP_META meta.
#
# The pose is a pure function of the wave clock `t` and the swing `share`
# (0..1 of `sweep` px at the tip), so every peer that has the same clock draws
# and collides with the same tentacle (map/ocean_tentacles.gd syncs it).
#
# Each segment's angle off the rest line (`base_angle`) is
#   amp * share * ((0.25 + 0.75 f) sin(2t + phase - k i) + LEAN f sin(t/2 + 0.7 phase))
# for segment i at f = i / (n - 1) of the way up: a wave running from the base
# to the tip plus a slow lean. `amp` is fitted once (unit_amp) so the tip
# swings `sweep` px each way at share 1; envelope() gives every joint's reach,
# which the map generator keeps clear of rock.

const GRIP_META := "story_moving_grip"   # on every body here: grips follow it
const LEAN := 0.6
const SAMPLES := 96          # clock samples over one full cycle (4 pi) for the fit
const T := 24.0

var base: Vector2            # global: the root joint
var base_angle: float = -PI / 2.0
var count: int = 10          # segments under the pad
var seg_len: float = 24.0
var width0: float = 30.0
var width1: float = 16.0
var phase: float = 0.0
var wave_k: float = 0.55
var sweep: float = 96.0      # px the tip swings each way at share 1
var tempo: float = 1.0       # clock speed multiplier
var pad_width: float = 36.0
var pad_height: float = 12.0
var tip_level: float = 0.0   # 0: the pad follows the tip; 1: it stays level
var level_up := Vector2.UP   # "level" for the pad: its top faces this way
var ease_share: float = 0.12
var ease_speed: float = 0.5
var lava_y: float = INF      # global y of the lava's surface: segments below look soaked

var share: float = 0.0       # swing now, 0..1 of `sweep`
var speed: float = 1.0       # wave speed now (clock units a second, before tempo)
var target_share: float = 0.0
var target_speed: float = 1.0
var t: float = 0.0           # the wave clock
var active: bool = true      # false: the pose holds (nobody near, nothing on screen)
var amp: float = 0.0         # radians at share 1 (fitted)
var segments: Array = []
var pad = null
var poses: int = 0           # poses done (cost accounting)
var pose_us: int = 0         # microseconds spent posing, in all

var _ang := PackedFloat32Array()


func _ready() -> void:
	process_physics_priority = -10   # before the keepers and their grips
	amp = unit_amp(count, seg_len, sweep, wave_k)
	_ang.resize(count)
	for i in count:
		var s := Segment.new()
		var f0: float = float(i) / float(count)
		var f1: float = float(i + 1) / float(count)
		s.w_root = lerpf(width0, width1, f0)
		s.w_tip = lerpf(width0, width1, f1)
		s.width = (s.w_root + s.w_tip) * 0.5
		s.length = seg_len
		s.index = i
		s.name = "Seg%d" % i
		add_child(s)
		segments.append(s)
	pad = Pad.new()
	pad.name = "Pad"
	pad.w_root = width1
	pad.width = pad_width
	pad.height = pad_height
	add_child(pad)
	pose()


func _physics_process(delta: float) -> void:
	# A story beat or the pause menu holds the keepers: hold still with them.
	if GameWorld.paused:
		return
	share = move_toward(share, target_share, delta * ease_share)
	speed = move_toward(speed, target_speed, delta * ease_speed)
	t += delta * speed * tempo
	if active:
		pose()


# Sets the swing at once (a run's start or a load: no easing in).
func snap_to_target() -> void:
	share = target_share
	speed = target_speed


func pose() -> void:
	var n: int = segments.size()
	if n == 0:
		return
	var us0: int = Time.get_ticks_usec()
	poses += 1
	angles(n, t, phase, amp * share, wave_k, _ang)
	var pos: Vector2 = base
	var a: float = base_angle
	for i in n:
		a = base_angle + _ang[i]
		var dir := Vector2.from_angle(a)
		var s = segments[i]
		s.global_transform = Transform2D(a, pos + dir * seg_len * 0.5)
		s.set_soak(lava_y)
		pos += dir * seg_len
	# The pad: on the tip joint, turned back toward level by tip_level.
	var up_a: float = level_up.angle()
	var pa: float = lerp_angle(a, up_a, tip_level)
	pad.global_transform = Transform2D(pa, pos)
	pad.set_soak(lava_y)
	pose_us += Time.get_ticks_usec() - us0


# Where every body (segments, then the pad) would be for clock `tt` and swing
# `sh`, global, without moving anything (checks and the map generator's
# tests; pose() itself moves the bodies, and only takes in a physics frame:
# they sync to physics).
func transforms_at(tt: float, sh: float) -> Array:
	var n: int = segments.size()
	var ang := PackedFloat32Array()
	ang.resize(n)
	angles(n, tt, phase, amp * sh, wave_k, ang)
	var out: Array = []
	var pos: Vector2 = base
	var a: float = base_angle
	for i in n:
		a = base_angle + ang[i]
		var dir := Vector2.from_angle(a)
		out.append(Transform2D(a, pos + dir * seg_len * 0.5))
		pos += dir * seg_len
	out.append(Transform2D(lerp_angle(a, level_up.angle(), tip_level), pos))
	return out


# The tip joint (under the pad) and the pad's top middle, global.
func tip() -> Vector2:
	return pad.global_position if pad != null else base


func pad_top() -> Vector2:
	return pad.global_transform * Vector2(pad_height, 0.0)


# The pad's top middle by the rig's clock now, whether or not it has posed
# (it holds still while nobody is near).
func pad_top_now() -> Vector2:
	return transforms_at(t, share).back() * Vector2(pad_height, 0.0)


# The pad top's tilt off level, radians (0 = flat).
func pad_tilt() -> float:
	return absf(angle_difference(pad.global_rotation, level_up.angle()))


# Every body of this tentacle (segments and pad).
func bodies() -> Array:
	var out: Array = segments.duplicate()
	if pad != null:
		out.append(pad)
	return out


# ---------------------------------------------------------------- the math

# Each segment's angle off the rest line for clock `t` (radians).
static func angles(n: int, t: float, phase: float, a: float, k: float, out: PackedFloat32Array) -> void:
	var lean: float = a * LEAN * sin(0.5 * t + 0.7 * phase)
	var d: float = maxf(1.0, float(n - 1))
	for i in n:
		var f: float = float(i) / d
		out[i] = a * (0.25 + 0.75 * f) * sin(2.0 * t + phase - k * float(i)) + lean * f


# Each joint's offset across the rest line (px) for angles `ang`; joint 0 is
# the base, joint n the tip.
static func _offsets(ang: PackedFloat32Array, seg_len: float, out: PackedFloat32Array) -> void:
	var x: float = 0.0
	out[0] = 0.0
	for i in ang.size():
		x += sin(ang[i]) * seg_len
		out[i + 1] = x


static var _unit_cache: Dictionary = {}

# The `amp` that swings the tip `sweep` px each way at share 1, fitted in the
# small-angle range (where the swing is linear in amp) over a full cycle.
# Real swings at share 1 come out a little under `sweep` (sin < angle).
static func unit_amp(n: int, seg_len: float, sweep: float, k: float) -> float:
	var key := [n, snappedf(seg_len, 0.01), k]
	var per_px: float
	if _unit_cache.has(key):
		per_px = _unit_cache[key]
	else:
		var a_ref: float = 0.01
		var env: PackedFloat32Array = _envelope_raw(n, seg_len, k, a_ref)
		per_px = a_ref / maxf(0.001, env[n])
		_unit_cache[key] = per_px
	return per_px * sweep


# Each joint's farthest reach across the rest line (px) over a full cycle at
# share 1, joint 0 (base) to n (tip): the map generator keeps it clear of rock.
static func envelope(n: int, seg_len: float, sweep: float, k: float) -> PackedFloat32Array:
	return _envelope_raw(n, seg_len, k, unit_amp(n, seg_len, sweep, k))


static func _envelope_raw(n: int, seg_len: float, k: float, a: float) -> PackedFloat32Array:
	var env := PackedFloat32Array()
	env.resize(n + 1)
	var ang := PackedFloat32Array()
	ang.resize(n)
	var off := PackedFloat32Array()
	off.resize(n + 1)
	# Two phases (the rigs use their own): the lean and the wave line up
	# differently with each, and the reach takes the worse.
	for ph in [0.0, 1.7]:
		for s in SAMPLES:
			var tt: float = TAU * 2.0 * float(s) / float(SAMPLES)
			angles(n, tt, ph, a, k, ang)
			_offsets(ang, seg_len, off)
			for j in n + 1:
				env[j] = maxf(env[j], absf(off[j]))
	return env


# ---------------------------------------------------------------- the look

const COL_DARK := Color(0.14, 0.07, 0.24)
const COL_BODY := Color(0.36, 0.17, 0.55)
const COL_LIGHT := Color(0.55, 0.33, 0.78)
const COL_SUCKER := Color(0.76, 0.58, 0.88)
const COL_VEIN := Color(1.0, 0.55, 0.2)
# Under the lava: scorched, with a hot rim, so it reads on the orange.
const COL_SOAK_DARK := Color(0.10, 0.02, 0.05)
const COL_SOAK_BODY := Color(0.27, 0.06, 0.12)
const COL_SOAK_LIGHT := Color(0.55, 0.16, 0.10)
const COL_SOAK_RIM := Color(1.0, 0.86, 0.45)


# The bodies' shared look: soak 0 in the air .. 6 a tile and a half under the
# lava's surface (a body redraws only when its step changes).
class _Body extends AnimatableBody2D:
	var soak: int = -1

	func set_soak(lava_y: float) -> void:
		var s: int = 0
		if lava_y != INF:
			s = clampi(int(ceil((global_position.y - lava_y) / (T * 1.5) * 6.0)), 0, 6)
		if s != soak:
			soak = s
			queue_redraw()

	func _mix(a: Color, b: Color, s: float) -> Color:
		return a.lerp(b, s)


class Segment extends _Body:
	var width: float = 24.0     # mean width, for callers
	var w_root: float = 24.0    # at the joint toward the base
	var w_tip: float = 24.0     # at the joint toward the tip
	var length: float = 24.0    # joint to joint: neighbours meet exactly
	var index: int = 0

	func _ready() -> void:
		sync_to_physics = true
		set_meta(GRIP_META, true)
		# Unshaded: seen in the dark, not only in the keeper's light.
		var mat := CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		material = mat
		collision_layer = 1
		collision_mask = 0
		var shape := CollisionShape2D.new()
		var poly := ConvexPolygonShape2D.new()
		poly.points = _outline(0.0)
		shape.shape = poly
		add_child(shape)
		var knuckle := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = w_root * 0.5
		knuckle.shape = c
		knuckle.position = Vector2(-length * 0.5, 0)
		add_child(knuckle)

	func _outline(inset: float) -> PackedVector2Array:
		var hl: float = length * 0.5
		var a: float = w_root * 0.5 - inset
		var b: float = w_tip * 0.5 - inset
		return PackedVector2Array([Vector2(-hl, -a), Vector2(hl, -b), Vector2(hl, b), Vector2(-hl, a)])

	func _draw() -> void:
		var hl: float = length * 0.5
		var s: float = float(maxi(soak, 0)) / 6.0
		var dark: Color = _mix(COL_DARK, COL_SOAK_DARK, s)
		var body: Color = _mix(COL_BODY, COL_SOAK_BODY, s)
		var light: Color = _mix(COL_LIGHT, COL_SOAK_LIGHT, s)
		if s > 0.0:
			# A hot rim round the soaked part, so it stands out on the lava.
			var rim: Color = COL_SOAK_RIM
			rim.a = s
			var o: PackedVector2Array = _outline(-1.5)
			draw_colored_polygon(o, rim)
			draw_circle(Vector2(-hl, 0), w_root * 0.5 + 1.5, rim)
		draw_colored_polygon(_outline(0.0), dark)
		draw_circle(Vector2(-hl, 0), w_root * 0.5, dark)
		var a: float = w_root * 0.5 - 2.0
		var b: float = w_tip * 0.5 - 2.0
		draw_colored_polygon(_outline(2.0), body)
		draw_circle(Vector2(-hl, 0), a, body)
		# A light stripe down one side, suckers down the other.
		draw_colored_polygon(PackedVector2Array([Vector2(-hl, -a), Vector2(hl, -b), Vector2(hl, -b + 3), Vector2(-hl, -a + 3)]), light)
		var sy: float = (a + b) * 0.5 - 4.0
		draw_circle(Vector2(0, sy), 3.5, _mix(COL_SUCKER, COL_SOAK_LIGHT, s))
		draw_circle(Vector2(0, sy), 1.7, dark)
		if index % 2 == 0:
			var v: Color = COL_VEIN
			v.a = 1.0 - 0.5 * s
			draw_line(Vector2(-5, -2), Vector2(2, 3), v, 1.5)


# The tip: a club with a flat top. Local +x points out of the tentacle; the
# flat face is at x = height, `width` across.
class Pad extends _Body:
	var w_root: float = 16.0
	var width: float = 36.0
	var height: float = 12.0

	func _ready() -> void:
		sync_to_physics = true
		set_meta(GRIP_META, true)
		var mat := CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		material = mat
		collision_layer = 1
		collision_mask = 0
		var shape := CollisionShape2D.new()
		var poly := ConvexPolygonShape2D.new()
		poly.points = outline(0.0)
		shape.shape = poly
		add_child(shape)
		# A knuckle on the joint under it, like every segment.
		var knuckle := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = w_root * 0.5
		knuckle.shape = c
		add_child(knuckle)

	# Neck at the joint (x 0, as wide as the tip), flaring to the flat top.
	func outline(inset: float) -> PackedVector2Array:
		var hw: float = width * 0.5 - inset
		var hn: float = w_root * 0.5 - inset
		var h: float = height - inset
		return PackedVector2Array([
			Vector2(-2.0 + inset, -hn), Vector2(h * 0.45, -hw + 2.0), Vector2(h - 3.0, -hw),
			Vector2(h, -hw + 3.0), Vector2(h, hw - 3.0), Vector2(h - 3.0, hw),
			Vector2(h * 0.45, hw - 2.0), Vector2(-2.0 + inset, hn)])

	func _draw() -> void:
		var s: float = float(maxi(soak, 0)) / 6.0
		var dark: Color = _mix(COL_DARK, COL_SOAK_DARK, s)
		var body: Color = _mix(COL_BODY, COL_SOAK_BODY, s)
		var light: Color = _mix(COL_LIGHT, COL_SOAK_LIGHT, s)
		draw_colored_polygon(outline(0.0), dark)
		draw_circle(Vector2.ZERO, w_root * 0.5, dark)
		draw_colored_polygon(outline(2.0), body)
		draw_circle(Vector2.ZERO, w_root * 0.5 - 2.0, body)
		# The flat top: a pale rim of suckers.
		var h: float = height
		var hw: float = width * 0.5 - 3.0
		draw_rect(Rect2(Vector2(h - 4.0, -hw), Vector2(2.0, hw * 2.0)), light)
		var n: int = 4
		for i in n:
			var y: float = lerpf(-hw + 4.0, hw - 4.0, float(i) / float(n - 1))
			draw_circle(Vector2(h - 6.5, y), 2.2, _mix(COL_SUCKER, COL_SOAK_LIGHT, s))
			draw_circle(Vector2(h - 6.5, y), 1.0, dark)
