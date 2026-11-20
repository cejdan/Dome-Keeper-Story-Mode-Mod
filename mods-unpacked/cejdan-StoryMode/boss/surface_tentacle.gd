extends "res://content/monster/Monster.gd"

# A tentacle on the surface, in the final battle (#162, #171, third pass #173).
# It is a real Monster (an Area2D in the "monster" group on the monster layer),
# so every dome weapon aims at it, hits it and kills it the vanilla way; only
# its looks and its behaviour are the mod's.
#
# It breaks out of the ground beside the dome: the earth splits, rock is thrown
# up, and the tentacle whips out past its full height before it settles. It
# sways, and slams the dome after a telegraph.
#
# It comes up with a row of eyes. Every few seconds one of them tears free
# (`eye_freed`) and the finale turns it into a flyer, the lowest first and the
# one at the tip last, until the tentacle has none left. The eyes still on a
# tentacle when it dies all tear free at once.
#
# Velle's great eye is its own monster: boss/great_eye.gd.
#
# Built in code by make(); nothing here needs a scene file.
#
# Online (#230) the host's tentacle is the real one. A client builds a
# `puppet` copy (make_copy(), from net_record()): the same id, so the client's
# own dome weapon hits reach the host's tentacle through vanilla's monster
# synchronizer, which also brings the host's health and the death back. The
# copy draws itself on its own clocks and takes its slams and lost eyes from
# the host (net_apply()); it never decides anything, nor hurts the dome.

const Pix = preload("res://mods-unpacked/cejdan-StoryMode/boss/pix.gd")
const Sfx = preload("res://mods-unpacked/cejdan-StoryMode/boss/sfx.gd")
const Boss = preload("res://mods-unpacked/cejdan-StoryMode/data/boss.gd")
const BossMonster = preload("res://mods-unpacked/cejdan-StoryMode/boss/boss_monster.gd")

const TECH := "storytentacle"

signal eye_freed(at: Vector2)

static var _uid: int = 900000

var great: bool = false          # always false here; the great eye is boss/great_eye.gd
var eyes_total: int = 4
var eyes_left: int = 4
var pop_t: float = 0.0           # seconds since the last eye tore free
var popped: int = 0
var height: float = 96.0
var dome_dir: float = 1.0        # +1 when the dome is to the right
var time: float = 0.0
var emerge_t: float = 0.0        # seconds since it broke the ground
var emerge: float = 0.0          # 0 underground .. 1 fully out (overshoots on the way)
var slam_t: float = -1.0         # seconds into a slam, -1 when idle
var next_slam: float = 3.0
var flinch: float = 0.0
var fury: float = 1.0            # the finale shortens every wait as the fight drags on
var flash: float = 0.0
var sink: float = 0.0
var slams: int = 0
var seed_f: float = 0.0
var crack_seed: int = 0
var debris: Array = []
var _cracks: Array = []
var _burst_flash: float = 0.0
var _hitbox: CollisionShape2D = null
var _did_hit: bool = false
var puppet: bool = false

const EMERGE_TIME := 0.75
const SLAM_TELE := 1.0
const SLAM_STRIKE := 0.18
const SLAM_HOLD := 0.35
const SLAM_BACK := 0.6
const POP_WARN := 0.8            # seconds an eye swells before it tears free
const EARTH: Array = [Color("2a2130"), Color("3b2f44"), Color("1c1622"), Color("4a3d52")]


static func register(tentacle_hp: float) -> void:
	BossMonster.register(TECH, tentacle_hp, 3, CONST.MONSTER_MEDIUM)


# A new tentacle at `pos` (global), not yet in the tree. `p_crack_seed` is the
# seed the finale drew its warning cracks from, so the break matches them.
static func make(pos: Vector2, dome_x: float, p_crack_seed: int = 0):
	_uid += 1
	var m = BossMonster.make("res://mods-unpacked/cejdan-StoryMode/boss/surface_tentacle.gd", "StoryTentacle", TECH, _uid, RectangleShape2D.new())
	m.height = randf_range(88.0, 108.0)
	m.eyes_total = Boss.FINALE_TENTACLE_EYES
	m.eyes_left = m.eyes_total
	m.dome_dir = 1.0 if dome_x > pos.x else -1.0
	m.crack_seed = p_crack_seed
	m._hitbox = m.get_node("HitboxDefault")
	m._fit_hitbox()
	m.global_position = pos
	return m


func _fit_hitbox() -> void:
	_hitbox.shape.size = Vector2(22.0, height)
	_hitbox.position = Vector2(0, -height * 0.5)


# ---------------------------------------------------------------- the break

# The cracks around a break: jagged lines from the middle, along the surface
# and down into the ground. Each is a list of points (this node's space).
static func crack_lines(crack_seed: int, big: bool) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = crack_seed
	var out: Array = []
	var n: int = 9 if big else 7
	for i in n:
		# Fanned from flat-left, down through the soil, to flat-right.
		var ang: float = lerpf(0.0, PI, (i + 0.5) / n) + rng.randf_range(-0.15, 0.15)
		var dir: Vector2 = Vector2(-cos(ang), sin(ang) * 0.75)
		var flat: bool = i == 0 or i == n - 1
		var length: float = rng.randf_range(22.0, 40.0) * (1.5 if big else 1.0) * (2.2 if flat else 1.0)
		var pts: PackedVector2Array = PackedVector2Array()
		var p: Vector2 = Vector2(rng.randf_range(-4, 4), 1.0)
		pts.append(p)
		var steps: int = 4 + rng.randi() % 3
		for j in steps:
			p += dir.rotated(rng.randf_range(-0.6, 0.6)) * (length / steps)
			p.y = maxf(p.y, 1.0)
			pts.append(p)
		out.append(pts)
	return out


# Draws `lines` from `origin`, the first `grow` (0..1) of each; `glow` (0..1)
# lights them violet from inside.
static func draw_cracks(ci: CanvasItem, origin: Vector2, lines: Array, grow: float, glow: float) -> void:
	for pass_i in 2:
		for pts: PackedVector2Array in lines:
			var total: float = float(pts.size() - 1) * clampf(grow, 0.0, 1.0)
			for j in pts.size() - 1:
				var part: float = clampf(total - j, 0.0, 1.0)
				if part <= 0.0:
					break
				var a: Vector2 = (origin + pts[j]).round()
				var b: Vector2 = (origin + pts[j].lerp(pts[j + 1], part)).round()
				var w: float = 3.0 if j == 0 else (2.0 if j < 3 else 1.0)
				if pass_i == 0:
					# The split itself, and the glow spilling out of it.
					ci.draw_line(a, b, Color("0a0612"), w + 2.0)
					if glow > 0.0:
						ci.draw_line(a, b, Color(Pix.VIOLET, glow * 0.45), w + 4.0)
				elif glow > 0.0:
					ci.draw_line(a, b, Color(Pix.VIOLET_LIGHT, minf(1.0, glow * 1.2)), maxf(1.0, w - 1.0))


# Shafts of light standing up out of the split ground at `origin`.
static func draw_light(ci: CanvasItem, origin: Vector2, crack_seed: int, grow: float, glow: float, big: bool) -> void:
	if glow <= 0.0 or grow <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = crack_seed + 77
	var n: int = 9 if big else 6
	var spread: float = 44.0 if big else 30.0
	for i in n:
		var x: float = rng.randf_range(-spread, spread) * clampf(grow * 1.3, 0.0, 1.0)
		var hgt: float = rng.randf_range(26.0, 64.0) * (1.6 if big else 1.0) * grow
		var w: float = float(1 + rng.randi() % 3)
		var flick: float = 0.75 + 0.25 * sin(grow * 40.0 + i * 1.7)
		for k in 4:
			var y0: float = -hgt * k / 4.0
			ci.draw_rect(Rect2(Vector2(origin.x + x - w * 0.5, origin.y + y0 - hgt / 4.0).round(), Vector2(w, ceil(hgt / 4.0))),
				Color(Pix.VIOLET_LIGHT, glow * flick * [0.5, 0.32, 0.18, 0.08][k]))


func init():
	next_slam = 2.2 + randf() * 2.2
	invulnerable = true
	_cracks = crack_lines(crack_seed, great)
	_burst_flash = 1.0
	# Rock thrown up by the break, and a column of dust.
	var n: int = 38
	for i in n:
		var up: float = randf_range(140.0, 400.0)
		debris.append({"p": Vector2(randf_range(-12, 12), -2.0), "v": Vector2(randf_range(-170, 170), -up), "s": float(2 + randi() % 5),
			"col": EARTH[randi() % EARTH.size()], "life": randf_range(2.5, 5.0), "rest": false})
	for i in 14:
		debris.append({"p": Vector2(randf_range(-16, 16), -2.0), "v": Vector2(randf_range(-40, 40), randf_range(-90, -30)), "s": float(3 + randi() % 3),
			"col": Color(0.42, 0.36, 0.47, 0.5), "life": randf_range(0.6, 1.3), "rest": false, "dust": true})
	Sfx.play("grow", -3.0, randf_range(0.9, 1.2))
	Sfx.play("boom", -8.0, randf_range(1.0, 1.3))
	InputSystem.shake(16.0, 0.5, 20.0, global_position)


static func _back_out(x: float) -> float:
	var c1: float = 2.6
	var c3: float = c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


func _update_debris(delta: float) -> void:
	_burst_flash = maxf(0.0, _burst_flash - delta * 3.5)
	for i in range(debris.size() - 1, -1, -1):
		var d: Dictionary = debris[i]
		d["life"] -= delta
		if d["life"] <= 0.0:
			debris.remove_at(i)
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
				d["v"] = Vector2(d["v"].x * 0.5, -d["v"].y * 0.3)   # one bounce
			else:
				d["rest"] = true


# ---------------------------------------------------------------- behaviour

func _slam_bend() -> float:
	# 0 upright .. 1 bent onto the dome; negative while rearing back.
	if slam_t < 0.0:
		return 0.0
	if slam_t < SLAM_TELE:
		return -0.35 * sin(slam_t / SLAM_TELE * PI * 0.5)
	var t: float = slam_t - SLAM_TELE
	if t < SLAM_STRIKE:
		return lerpf(-0.35, 1.0, t / SLAM_STRIKE)
	t -= SLAM_STRIKE
	if t < SLAM_HOLD:
		return 1.0
	t -= SLAM_HOLD
	return maxf(0.0, 1.0 - t / SLAM_BACK)


# The tip, in this node's space.
func tip() -> Vector2:
	var h: float = height * emerge * (1.0 - sink)
	var bend: float = _slam_bend()
	var sway: float = sin(time * 1.3 + seed_f) * 9.0
	var reach: float = absf(_dome_gap()) - 26.0
	var x: float = sway + dome_dir * reach * maxf(bend, 0.0) + dome_dir * 30.0 * minf(bend, 0.0)
	var y: float = -h * (1.0 - 0.62 * maxf(bend, 0.0))
	if flinch > 0.0:
		x -= dome_dir * 14.0 * flinch
	return Vector2(x, y)


func _dome_gap() -> float:
	var dome = Level.getDome(teamId)
	return (dome.global_position.x - global_position.x) if dome != null else dome_dir * 150.0


func _dome_top() -> Vector2:
	var dome = Level.getDome(teamId)
	if dome == null:
		return Vector2(dome_dir * 150.0, -40.0)
	return to_local(dome.getCupolaClosestPos(to_global(tip()), teamId))


func subProcess(delta: float) -> void:
	time += delta
	flash = maxf(0.0, flash - delta)
	flinch = maxf(0.0, flinch - delta * 1.2)
	_update_debris(delta)
	if emerge_t < EMERGE_TIME:
		emerge_t += delta
		emerge = _back_out(clampf(emerge_t / EMERGE_TIME, 0.0, 1.0))
		if emerge_t >= EMERGE_TIME:
			emerge = 1.0
			invulnerable = false
	elif slam_t >= 0.0:
		slam_t += delta
		if slam_t >= SLAM_TELE + SLAM_STRIKE and not _did_hit:
			_did_hit = true
			_hit_dome()
		if slam_t >= SLAM_TELE + SLAM_STRIKE + SLAM_HOLD + SLAM_BACK:
			slam_t = -1.0
			next_slam = Boss.FINALE_SLAM_EVERY * randf_range(0.8, 1.25) * fury
	elif not puppet:
		next_slam -= delta
		if next_slam <= 0.0:
			_did_hit = false
			slam_t = 0.0
	if emerge_t >= EMERGE_TIME and eyes_left > 0 and not puppet:
		pop_t += delta
		if pop_t >= Boss.FINALE_EYE_POP_EVERY:
			pop_t = 0.0
			_pop_eye()
	if _hitbox != null:
		var t: Vector2 = tip()
		_hitbox.position = Vector2(t.x * 0.5, t.y * 0.5)
	queue_redraw()


# The body's points, root to tip (this node's space).
func _points() -> PackedVector2Array:
	var bend: float = _slam_bend()
	return Pix.tentacle_points(Vector2.ZERO, tip(), time, 7.0 * (1.0 - absf(bend) * 0.6), seed_f, 1.0, -dome_dir * 16.0 * (1.0 - maxf(bend, 0.0)) + dome_dir * 34.0 * maxf(bend, 0.0))


# Where eye `k` sits (0 the lowest, eyes_total - 1 the one at the tip).
func eye_slot(k: int, pts: PackedVector2Array = PackedVector2Array()) -> Vector2:
	if pts.is_empty():
		pts = _points()
	var u: float = lerpf(0.4, 1.0, float(k) / float(maxi(1, eyes_total - 1)))
	return pts[clampi(int(round(u * (pts.size() - 1))), 0, pts.size() - 1)]


# The next eye tears free: the lowest one still there.
func _pop_eye() -> void:
	var k: int = eyes_total - eyes_left
	eyes_left -= 1
	popped += 1
	flash = 0.08
	Sfx.play("pop", -5.0, randf_range(1.3, 1.6))
	for i in 6:
		debris.append({"p": eye_slot(k), "v": Vector2(randf_range(-60, 60), randf_range(-90, -20)), "s": 2.0,
			"col": Color(Pix.IRIS_DEEP, 0.9), "life": randf_range(0.3, 0.6), "rest": false, "dust": true})
	eye_freed.emit(to_global(eye_slot(k)))


func _hit_dome() -> void:
	var dome = Level.getDome(teamId)
	if dome == null or (not multiplayer.is_server() and not puppet):
		return
	slams += 1
	if not puppet:
		dome.requestMeleeDamage(int(Boss.FINALE_SLAM_DAMAGE), to_global(tip()), self)
	InputSystem.shake(16.0, 0.4, 20.0, global_position)
	Sfx.play("whip", -2.0, 1.0)


func handleDamage():
	flash = 0.1


# ---------------------------------------------------------------- online (#230)

# A client's copy takes no damage itself: the hit goes to the host (vanilla's
# weapon sends it), whose health comes back through the synchronizer.
func hit(source: String, damage: float, stun: float, immediateStun: = false):
	if puppet:
		if hittable:
			flash = maxf(flash, 0.05)
		return
	super(source, damage, stun, immediateStun)


# What a client needs to build this tentacle and draw it: [kind, id, dead,
# place, looks..., state].
func net_record() -> Array:
	return ["tentacle", UID, dead, global_position, crack_seed, height, eyes_total, seed_f, dome_dir,
		PackedFloat32Array([slam_t, eyes_left, emerge_t, time])]


# A client's copy of the host's tentacle from net_record(), not yet in the tree.
static func make_copy(r: Array):
	var m = make(r[3], 0.0, int(r[4]))
	m.puppet = true
	m.UID = int(r[1])
	m.height = float(r[5])
	m.eyes_total = int(r[6])
	m.eyes_left = m.eyes_total
	m.seed_f = float(r[7])
	m.dome_dir = float(r[8])
	m._fit_hitbox()
	return m


func net_apply(d: PackedFloat32Array) -> void:
	if d.size() < 4 or dead:
		return
	var hs: float = d[0]
	# (A slam already near its end on the host is the tail of one this copy
	# has just finished, not a new one.)
	if hs >= 0.0 and (slam_t >= 0.0 or hs < SLAM_TELE + SLAM_STRIKE + SLAM_HOLD) and (slam_t < 0.0 or absf(slam_t - hs) > 0.25):
		if slam_t < 0.0:
			# A new slam: its blow is still to come unless it is long past.
			_did_hit = hs > SLAM_TELE + SLAM_STRIKE + 0.2
		slam_t = hs
	while eyes_left > int(d[1]):
		_pop_eye()
	if emerge_t < EMERGE_TIME and absf(emerge_t - d[2]) > 0.3:
		emerge_t = d[2]
	if absf(time - d[3]) > 0.5:
		time = d[3]


func animateDeath():
	Sfx.play("pop", -2.0, randf_range(0.8, 1.1))
	InputSystem.shake(12.0, 0.6, 18.0, global_position)
	slam_t = -1.0
	# The eyes it still had all tear free at once.
	while eyes_left > 0:
		_pop_eye()
	var tw := create_tween()
	tw.tween_property(self, "sink", 1.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): remainingFreeBlockers = 0)


func _process(_delta: float) -> void:
	if dead:
		time += _delta
		_update_debris(_delta)
		queue_redraw()


func leave(_delta: float):
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	# The broken ground stays, even once the tentacle is gone.
	var after: float = clampf(1.0 - emerge_t / 2.2, 0.0, 1.0) if not dead else 0.0
	draw_cracks(self, Vector2.ZERO, _cracks, 1.0, after)
	draw_light(self, Vector2.ZERO, crack_seed, 1.0, after * after, great)
	for i in 7:
		var rx: float = (i - 3) * 6.0 + sin(seed_f + i) * 2.0
		Pix.disc(self, Vector2(rx, -1.0 - absf(sin(seed_f * 3.0 + i)) * 3.0), 3.0 + (i % 2), EARTH[i % EARTH.size()])
	if emerge > 0.01 and sink < 0.99:
		_draw_body()
	for d: Dictionary in debris:
		var a: float = clampf(d["life"] * 1.5, 0.0, 1.0) * d["col"].a
		draw_rect(Rect2((d["p"] - Vector2(d["s"], d["s"]) * 0.5).round(), Vector2(d["s"], d["s"])), Color(d["col"], a))
	if _burst_flash > 0.0:
		var r: float = (26.0 if great else 18.0) * (1.6 - _burst_flash * 0.6)
		Pix.ellipse(self, Vector2(0, -2), r * 1.8, r * 0.7, Color(Pix.VIOLET_LIGHT, _burst_flash * 0.8), -1.0, 0.2)
		# A column of light where it came through.
		var cw: float = (22.0 if great else 14.0) * _burst_flash
		var chh: float = 170.0 if great else 120.0
		draw_rect(Rect2(Vector2(-cw, -chh).round(), Vector2(cw * 2.0, chh)), Color(Pix.VIOLET_LIGHT, _burst_flash * 0.35))
		draw_rect(Rect2(Vector2(-cw * 0.4, -chh).round(), Vector2(cw * 0.8, chh)), Color(1, 1, 1, _burst_flash * 0.6))
		# The shock runs out along the ground both ways.
		var run: float = (1.0 - _burst_flash) * 70.0
		draw_rect(Rect2(Vector2(-run - 10.0, -1).round(), Vector2(10, 2)), Color(Pix.SCLERA, _burst_flash))
		draw_rect(Rect2(Vector2(run, -1).round(), Vector2(10, 2)), Color(Pix.SCLERA, _burst_flash))


func _draw_body() -> void:
	var col: Color = Pix.FLESH_MID
	if flash > 0.0:
		col = Color.WHITE
	elif dead:
		col = Color("231a30")
	var pts: PackedVector2Array = _points()
	var tipp: Vector2 = Pix.tentacle(self, pts, 9.0, 3.5, col)
	var look: Vector2 = Vector2(_dome_gap(), -30.0)
	var gone: int = eyes_total - eyes_left
	for k in eyes_total:
		var c: Vector2 = eye_slot(k, pts)
		var at_tip: bool = k == eyes_total - 1
		if k < gone:
			# A torn socket: this eye has gone.
			Pix.disc(self, c, 5.0 if at_tip else 4.0, Pix.EDGE)
			Pix.disc(self, c, 3.0 if at_tip else 2.0, Pix.IRIS_DEEP)
			continue
		var r: float = 9.0 if at_tip else 8.0
		var mod: Color = Color.WHITE if flash <= 0.0 else Color(3, 3, 3)
		if dead:
			mod = Color(0.4, 0.35, 0.45)
		elif k == gone and pop_t > Boss.FINALE_EYE_POP_EVERY - POP_WARN:
			# About to tear free: it swells and strains.
			var f: float = (pop_t - (Boss.FINALE_EYE_POP_EVERY - POP_WARN)) / POP_WARN
			r += 3.0 * f
			c += Vector2(sin(time * 60.0), cos(time * 47.0)) * f * 1.5
			if fposmod(time * 12.0, 1.0) < 0.5:
				mod = Color(2.2, 2.2, 2.2)
			Pix.disc(self, c, r + 2.0, Color(Pix.VIOLET_LIGHT, 0.5 * f))
		Pix.disc(self, c, r, Pix.EDGE)
		Pix.eye(self, c, Pix.eye_frame_toward(c, look, time, seed_f + k * 0.37), 1.0, mod)
	# The slam's warning: the tip glows red while it rears back.
	if slam_t >= 0.0 and slam_t < SLAM_TELE:
		var f2: float = slam_t / SLAM_TELE
		var blink: float = 0.4 + 0.6 * absf(sin(slam_t * (10.0 + 16.0 * f2)))
		draw_arc(tipp, 13.0 + 4.0 * (1.0 - f2), 0.0, TAU, 20, Color(Pix.WARN, blink), 2.0)
