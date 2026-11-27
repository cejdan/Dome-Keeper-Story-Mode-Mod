extends "res://content/monster/Monster.gd"

# Velle's great eye, in the last round of the final battle (#173). It rises
# from behind the dome on a thick stalk and hangs straight above it. The stalk
# is only looks, drawn behind the dome; the target is the eye itself. A real
# Monster, so the dome's weapon aims at it, hits it and kills it the vanilla
# way.
#
# It pounds the dome after a telegraph, and it has the gaze: it charges a beam
# for a few seconds, and only enough damage in that time makes it flinch and
# lose the shot.
#
# At no health it does not go away: it closes and hangs there until the finale
# calls fall(side). Then it sways, topples to that side of the dome and hits
# the ground (`crashed`).
#
# Built in code by make().
#
# Online (#230) a client draws a `puppet` copy (make_copy()) on its own
# clocks, taking the host's pounds, gazes, flinches and fall (net_apply());
# see surface_tentacle.gd.

const Pix = preload("res://mods-unpacked/flantor-StoryMode/boss/pix.gd")
static var _Pix = Pix  # calls go through this: lazy_preload makes const-preload calls slow
const Sfx = preload("res://mods-unpacked/flantor-StoryMode/boss/sfx.gd")
static var _Sfx = Sfx  # calls go through this: lazy_preload makes const-preload calls slow
const Boss = preload("res://mods-unpacked/flantor-StoryMode/data/boss.gd")
const BossMonster = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_monster.gd")
static var _BossMonster = BossMonster  # calls go through this: lazy_preload makes const-preload calls slow

const TECH := "storygreateye"

signal crashed

static var _uid: int = 980000

var great: bool = true
var time: float = 0.0
var seed_f: float = 0.0
var emerge_t: float = 0.0
var emerge: float = 0.0          # 0 behind the dome .. 1 at its full height
var slam_t: float = -1.0         # seconds into a pound, -1 when idle
var next_slam: float = 3.0
var gaze_t: float = -1.0         # seconds into the gaze, -1 when idle
var gaze_hp: float = 0.0         # health when the gaze began
var flinch: float = 0.0
var attacks_done: int = 0
var fury: float = 1.0
var flash: float = 0.0
var slams: int = 0
var gazes_fired: int = 0
var gazes_broken: int = 0
var fall_t: float = -1.0         # seconds since fall() was called, -1 before
var fall_side: float = 1.0       # +1 falls to the right of the dome
var fallen: bool = false
var debris: Array = []
var stalk: Node2D = null
var _did_hit: bool = false
var _land_flash: float = 0.0
var _sway_a0: float = 0.0
var puppet: bool = false

const RISE := 1.5
const SLAM_TELE := 1.0
const SLAM_STRIKE := 0.18
const SLAM_HOLD := 0.35
const SLAM_BACK := 0.6
const GAZE_FIRE := 0.7
const FALL_SWAY := 2.2           # seconds it sways before it goes
const FALL_DROP := 0.95          # seconds from upright to the ground
const FALL_ANGLE := 1.46         # radians from upright when it lies on the ground
const FALL_REACH := 152.0        # px from the dome's middle to where it lands
const RX := 26.0
const RY := 21.0
const EARTH: Array = [Color("2a2130"), Color("3b2f44"), Color("1c1622"), Color("4a3d52")]


static func register(hp: float) -> void:
	_BossMonster.register(TECH, hp, 3, CONST.MONSTER_LARGE)


# A new great eye, not yet in the tree. It places itself over the dome.
static func make():
	var shape := CircleShape2D.new()
	shape.radius = 22.0
	_uid += 1
	var m = _BossMonster.make("res://mods-unpacked/flantor-StoryMode/boss/great_eye.gd", "StoryGreatEye", TECH, _uid, shape)
	# The stalk: drawn behind the dome, whatever this node's own layer.
	var st := Node2D.new()
	st.name = "Stalk"
	st.z_as_relative = false
	st.z_index = Boss.FINALE_STALK_Z
	st.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	m.add_child(st)
	m.stalk = st
	return m


func init():
	next_slam = 3.5
	invulnerable = true
	stalk.draw.connect(_draw_stalk)
	global_position = _place()
	_Sfx.play("grow", -1.0, 0.6)
	InputSystem.shake(30.0, RISE, 20.0)


func _base() -> Vector2:
	var dome = Level.getDome(teamId)
	return dome.global_position if dome != null else global_position + Vector2(0, Boss.FINALE_EYE_HEIGHT)


func _cupola_top() -> Vector2:
	var dome = Level.getDome(teamId)
	var b: Vector2 = _base()
	if dome == null:
		return b + Vector2(0, -50)
	return dome.getCupolaClosestPos(b + Vector2(0, -Boss.FINALE_EYE_HEIGHT), teamId)


func _slam_bend() -> float:
	# 0 hanging .. 1 down on the dome; negative while it draws back.
	if slam_t < 0.0:
		return 0.0
	if slam_t < SLAM_TELE:
		return -sin(slam_t / SLAM_TELE * PI * 0.5)
	var t: float = slam_t - SLAM_TELE
	if t < SLAM_STRIKE:
		return lerpf(-1.0, 1.0, t / SLAM_STRIKE)
	t -= SLAM_STRIKE
	if t < SLAM_HOLD:
		return 1.0
	t -= SLAM_HOLD
	return maxf(0.0, 1.0 - t / SLAM_BACK)


# The angle from upright (radians, + to the right) while it sways and falls.
func _fall_angle() -> float:
	if fall_t < 0.0:
		return 0.0
	if fall_t < FALL_SWAY:
		var f: float = fall_t / FALL_SWAY
		return fall_side * sin(fall_t * 4.2) * 0.24 * f
	var u: float = clampf((fall_t - FALL_SWAY) / FALL_DROP, 0.0, 1.0)
	return lerpf(_sway_a0, fall_side * FALL_ANGLE, u * u)


# Where the eye is now (global).
func _place() -> Vector2:
	var b: Vector2 = _base()
	var full: float = Boss.FINALE_EYE_HEIGHT
	if fall_t >= 0.0:
		var a: float = _fall_angle()
		var u: float = clampf((fall_t - FALL_SWAY) / FALL_DROP, 0.0, 1.0)
		var length: float = lerpf(full, FALL_REACH, u)
		var p: Vector2 = b + Vector2(sin(a), -cos(a)) * length
		if fallen:
			# One small bounce, then it lies still.
			var since: float = fall_t - FALL_SWAY - FALL_DROP
			p.y -= maxf(0.0, sin(clampf(since / 0.35, 0.0, 1.0) * PI)) * 7.0
		return p
	var h: float = lerpf(30.0, full, emerge)
	var off: Vector2 = Vector2(sin(time * 0.7 + seed_f) * 9.0 * emerge, -h + sin(time * 1.1 + seed_f) * 4.0 * emerge)
	if dead:
		# Closed: it hangs a little lower, slack.
		off.y += 8.0
	var bend: float = _slam_bend()
	if bend < 0.0:
		off.y += 16.0 * bend
	elif bend > 0.0:
		off = off.lerp(_cupola_top() - b + Vector2(0, -RY + 4.0), bend)
	off.y -= 10.0 * flinch
	return b + off


func subProcess(delta: float) -> void:
	time += delta
	flash = maxf(0.0, flash - delta)
	flinch = maxf(0.0, flinch - delta * 1.2)
	if emerge_t < RISE:
		emerge_t += delta
		var x: float = clampf(emerge_t / RISE, 0.0, 1.0)
		emerge = 1.0 - pow(1.0 - x, 3.0)
		if emerge_t >= RISE:
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
	elif gaze_t >= 0.0:
		_update_gaze(delta)
	elif not puppet:
		next_slam -= delta
		if next_slam <= 0.0:
			attacks_done += 1
			_did_hit = false
			if attacks_done % 2 == 0:
				gaze_t = 0.0
				gaze_hp = currentHealth
				_Sfx.play("charge", -2.0, 0.6)
			else:
				slam_t = 0.0
	global_position = _place()
	queue_redraw()
	stalk.queue_redraw()


# How much of the damage that breaks the gaze has been dealt (0..1).
func gaze_broken_share() -> float:
	return clampf((gaze_hp - currentHealth) / (maxHealth * Boss.FINALE_GAZE_BREAK), 0.0, 1.0)


func _update_gaze(delta: float) -> void:
	gaze_t += delta
	if gaze_t < Boss.FINALE_GAZE_CHARGE:
		if gaze_broken_share() >= 1.0 and not puppet:
			# Hurt enough: it flinches and the shot is lost.
			gaze_t = -1.0
			gazes_broken += 1
			flinch = 1.0
			flash = 0.3
			next_slam = Boss.FINALE_SLAM_EVERY * 0.9 * fury
			_Sfx.play("hurt", 0.0, 0.7)
			InputSystem.shake(18.0, 0.4, 22.0, global_position)
		return
	if not _did_hit:
		_did_hit = true
		gazes_fired += 1
		var dome = Level.getDome(teamId)
		if dome != null and multiplayer.is_server():
			dome.requestMeleeDamage(int(Boss.FINALE_GAZE_DAMAGE), _cupola_top(), self)
		InputSystem.shake(34.0, 0.7, 26.0)
		_Sfx.play("beam", 2.0, 0.6)
	if gaze_t >= Boss.FINALE_GAZE_CHARGE + GAZE_FIRE:
		gaze_t = -1.0
		next_slam = Boss.FINALE_SLAM_EVERY * randf_range(0.8, 1.1) * fury


func _hit_dome() -> void:
	var dome = Level.getDome(teamId)
	if dome == null or (not multiplayer.is_server() and not puppet):
		return
	slams += 1
	if not puppet:
		dome.requestMeleeDamage(int(Boss.FINALE_SLAM_DAMAGE * 2.0), _cupola_top(), self)
	InputSystem.shake(26.0, 0.4, 20.0, global_position)
	_Sfx.play("whip", -2.0, 0.7)


func handleDamage():
	flash = 0.1


# ---------------------------------------------------------------- online (#230)

func hit(source: String, damage: float, stun: float, immediateStun: = false):
	if puppet:
		if hittable:
			flash = maxf(flash, 0.05)
		return
	super(source, damage, stun, immediateStun)


func net_record() -> Array:
	return ["great", UID, dead, global_position, seed_f,
		PackedFloat32Array([emerge_t, slam_t, gaze_t, fall_t, fall_side, gazes_broken, time])]


static func make_copy(r: Array):
	var m = make()
	m.puppet = true
	m.UID = int(r[1])
	m.seed_f = float(r[4])
	return m


func net_apply(d: PackedFloat32Array) -> void:
	if d.size() < 7:
		return
	if emerge_t < RISE and absf(emerge_t - d[0]) > 0.3:
		emerge_t = d[0]
	if not dead:
		var hs: float = d[1]
		if hs >= 0.0 and (slam_t >= 0.0 or hs < SLAM_TELE + SLAM_STRIKE + SLAM_HOLD) and (slam_t < 0.0 or absf(slam_t - hs) > 0.25):
			if slam_t < 0.0:
				_did_hit = hs > SLAM_TELE + SLAM_STRIKE + 0.2
			slam_t = hs
		var hg: float = d[2]
		if hg >= 0.0 and gaze_t < 0.0 and hg < Boss.FINALE_GAZE_CHARGE + GAZE_FIRE - 0.2:
			# The gaze begins.
			gaze_t = hg
			gaze_hp = currentHealth
			_did_hit = hg > Boss.FINALE_GAZE_CHARGE + 0.2
			_Sfx.play("charge", -2.0, 0.6)
		elif hg >= 0.0 and gaze_t >= 0.0 and absf(gaze_t - hg) > 0.25:
			gaze_t = hg
		if int(d[5]) > gazes_broken:
			# Broken: it flinches and the shot is lost.
			gazes_broken = int(d[5])
			gaze_t = -1.0
			flinch = 1.0
			flash = 0.3
			_Sfx.play("hurt", 0.0, 0.7)
			InputSystem.shake(18.0, 0.4, 22.0, global_position)
	if d[3] >= 0.0 and fall_t < 0.0:
		fall(d[4])
		fall_t = d[3]
	elif fall_t >= 0.0 and not fallen and absf(fall_t - d[3]) > 0.3:
		fall_t = d[3]
	if absf(time - d[6]) > 0.5:
		time = d[6]


# Beaten: the eye closes. It stays where it is until fall().
func animateDeath():
	_Sfx.play("die", -2.0, 0.8)
	InputSystem.shake(24.0, 0.6, 18.0, global_position)
	slam_t = -1.0
	gaze_t = -1.0
	flinch = 1.0


# The end: it sways, then topples to `side` (+1 right, -1 left) of the dome.
func fall(side: float) -> void:
	if fall_t >= 0.0:
		return
	fall_side = 1.0 if side >= 0.0 else -1.0
	fall_t = 0.0
	slam_t = -1.0
	gaze_t = -1.0
	_Sfx.play("hurt", -2.0, 0.5)


func _land() -> void:
	fallen = true
	_land_flash = 1.0
	_Sfx.play("boom", 2.0, 0.6)
	_Sfx.play("drop", 0.0, 0.7)
	InputSystem.shake(42.0, 0.9, 16.0)
	for i in 54:
		debris.append({"p": Vector2(randf_range(-26, 26), RY - 4.0), "v": Vector2(randf_range(-190, 190) + fall_side * 60.0, -randf_range(90.0, 330.0)), "s": float(2 + randi() % 5),
			"col": EARTH[randi() % EARTH.size()], "life": randf_range(2.0, 4.5), "rest": false})
	for i in 18:
		debris.append({"p": Vector2(randf_range(-30, 30), RY - 4.0), "v": Vector2(randf_range(-70, 70), randf_range(-70, -20)), "s": float(3 + randi() % 4),
			"col": Color(0.42, 0.36, 0.47, 0.5), "life": randf_range(0.8, 1.6), "rest": false, "dust": true})
	crashed.emit()


func _update_debris(delta: float) -> void:
	_land_flash = maxf(0.0, _land_flash - delta * 3.0)
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
		if d["p"].y >= RY - 2.0 and d["v"].y > 0.0:
			d["p"].y = RY - 2.0
			if d["v"].y > 120.0:
				d["v"] = Vector2(d["v"].x * 0.5, -d["v"].y * 0.3)
			else:
				d["rest"] = true


# The vanilla Monster stops calling subProcess once it is dead; the closed
# eye, its sway and its fall run from here.
func _process(delta: float) -> void:
	if not dead or GameWorld.paused:
		return
	time += delta
	flash = maxf(0.0, flash - delta)
	flinch = maxf(0.0, flinch - delta * 0.8)
	if fall_t >= 0.0:
		var before: float = fall_t
		fall_t += delta
		if before < FALL_SWAY and fall_t >= FALL_SWAY:
			_sway_a0 = fall_side * sin(FALL_SWAY * 4.2) * 0.24
			_Sfx.play("whip", -4.0, 0.5)
		if not fallen and fall_t >= FALL_SWAY + FALL_DROP:
			_land()
	_update_debris(delta)
	global_position = _place()
	queue_redraw()
	stalk.queue_redraw()


func leave(_delta: float):
	queue_redraw()


# ---------------------------------------------------------------- drawing

# The stalk, from the ground behind the dome up to the eye (drawn by the
# Stalk child, behind the dome).
func _draw_stalk() -> void:
	var root: Vector2 = to_local(_base() + Vector2(0, 10.0))
	var top: Vector2 = Vector2(0, RY - 6.0)
	if root.distance_to(top) < 4.0:
		return
	var col: Color = Pix.FLESH_MID
	if flash > 0.0:
		col = Color.WHITE
	elif dead:
		col = Color("231a30")
	# It bows as it falls, and lies in an arch on the ground.
	var bow: float = 0.0
	if fall_t >= 0.0:
		bow = fall_side * 30.0 * clampf(absf(_fall_angle()) / FALL_ANGLE, 0.0, 1.0)
	var pts: PackedVector2Array = _Pix.tentacle_points(root, top, time, 6.0 if not fallen else 1.5, seed_f, 1.0, bow)
	_Pix.tentacle(stalk, pts, 18.0, 11.0, col)
	if not dead:
		var look: Vector2 = Vector2(0, RY + 40.0)
		for j in range(8, pts.size() - 5, 9):
			_Pix.small_eye(stalk, pts[j], look, time, j * 0.3 + seed_f)


func _draw() -> void:
	var c: Vector2 = Vector2.ZERO
	var look: Vector2 = to_local(_cupola_top())
	_Pix.ellipse(self, c, RX, RY, Pix.EDGE)
	_Pix.ellipse(self, c, RX - 2.0, RY - 2.0, Pix.FLESH_LIGHT if not dead else Color("2c2238"))
	if dead:
		# The lid is shut.
		draw_rect(Rect2((c + Vector2(-RX + 6.0, 1)).round(), Vector2(RX * 2.0 - 12.0, 2)), Pix.EDGE)
		for i in 5:
			draw_rect(Rect2((c + Vector2(-16.0 + i * 8.0, 3)).round(), Vector2(1, 3)), Pix.EDGE)
	else:
		var squint: float = 1.0 - 0.7 * flinch
		_Pix.ellipse(self, c, RX - 5.0, (RY - 5.0) * squint, Pix.SCLERA if flash <= 0.0 else Color.WHITE)
		var ic: Vector2 = c + (look - c).limit_length(80.0) / 80.0 * Vector2(5, 6)
		var charging: bool = gaze_t >= 0.0
		_Pix.ellipse(self, ic, 10, 10 * squint, Pix.IRIS_DEEP if not charging else Pix.WARN)
		_Pix.ellipse(self, ic, 8, 8 * squint, Pix.IRIS if not charging or fposmod(time * 10.0, 1.0) < 0.5 else Color.WHITE)
		draw_rect(Rect2((ic + Vector2(-1, -8 * squint)).round(), Vector2(3, 16 * squint)), Pix.PUPIL)
		draw_rect(Rect2((ic + Vector2(-5, -6 * squint)).round(), Vector2(2, 2)), Color.WHITE)
		# The pound's warning.
		if slam_t >= 0.0 and slam_t < SLAM_TELE:
			var f: float = slam_t / SLAM_TELE
			var blink: float = 0.4 + 0.6 * absf(sin(slam_t * (10.0 + 16.0 * f)))
			draw_arc(c, RX + 5.0 + 5.0 * (1.0 - f), 0.0, TAU, 28, Color(Pix.WARN, blink), 2.0)
			draw_line(c + Vector2(0, RY), look, Color(Pix.WARN, 0.25 * blink), 1.0)
		if gaze_t >= 0.0:
			_draw_gaze(c, look)
	for d: Dictionary in debris:
		var a: float = clampf(d["life"] * 1.5, 0.0, 1.0) * d["col"].a
		draw_rect(Rect2((d["p"] - Vector2(d["s"], d["s"]) * 0.5).round(), Vector2(d["s"], d["s"])), Color(d["col"], a))
	if _land_flash > 0.0:
		var run: float = (1.0 - _land_flash) * 90.0
		_Pix.ellipse(self, Vector2(0, RY - 2.0), 40.0 + run * 0.5, 8.0, Color(Pix.VIOLET_LIGHT, _land_flash * 0.6), -1.0, 0.2)
		draw_rect(Rect2(Vector2(-run - 12.0, RY - 3.0).round(), Vector2(12, 2)), Color(Pix.SCLERA, _land_flash))
		draw_rect(Rect2(Vector2(run, RY - 3.0).round(), Vector2(12, 2)), Color(Pix.SCLERA, _land_flash))


func _draw_gaze(c: Vector2, target: Vector2) -> void:
	if gaze_t < Boss.FINALE_GAZE_CHARGE:
		var f: float = gaze_t / Boss.FINALE_GAZE_CHARGE
		# Light gathers into the eye.
		for i in 3:
			var r: float = 46.0 - fposmod(time * 40.0 + i * 15.0, 46.0)
			draw_arc(c, RX + 2.0 + r, 0.0, TAU, 28, Color(Pix.IRIS, 0.5 * (1.0 - r / 46.0) + 0.1), 1.0)
		var blink: float = 0.4 + 0.6 * absf(sin(gaze_t * (6.0 + 22.0 * f)))
		draw_line(c, target, Color(Pix.WARN, 0.10 + 0.25 * f), 8.0 * f + 2.0)
		draw_line(c, target, Color(Pix.WARN, blink), 1.0)
		# How close the dome's fire is to breaking it: a ring that burns away.
		var left: float = 1.0 - gaze_broken_share()
		draw_arc(c, RX + 8.0, -PI * 0.5, -PI * 0.5 + TAU * left, 40, Color(Pix.SCLERA, 0.9), 3.0)
		draw_arc(c, RX + 8.0, -PI * 0.5 + TAU * left, -PI * 0.5 + TAU, 40, Color(Pix.EDGE, 0.6), 3.0)
	else:
		var f2: float = 1.0 - (gaze_t - Boss.FINALE_GAZE_CHARGE) / GAZE_FIRE
		draw_line(c, target, Color(Pix.IRIS_DEEP, 0.8), 20.0 * f2 + 4.0)
		draw_line(c, target, Color(Pix.IRIS, 1.0), 13.0 * f2 + 2.0)
		draw_line(c, target, Color.WHITE, 5.0 * f2 + 1.0)
		_Pix.disc(self, target, 14.0 * f2 + 4.0, Color(1, 1, 1, 0.8 * f2))
