extends "res://content/monster/Monster.gd"

# A tentacle on the surface, in the final battle (#162). It is a real Monster
# (an Area2D in the "monster" group on the monster layer), so every dome weapon
# aims at it, hits it and kills it the vanilla way; only its looks and its
# behaviour are the mod's. It bursts out of the ground beside the dome, sways,
# and slams the dome after a telegraph. `great` makes it Velle's great eye on a
# thick stalk: three times the health, twice the slam.
#
# Built in code by make(); nothing here needs a scene file.

const Pix = preload("res://mods-unpacked/cejdan-StoryMode/boss/pix.gd")
const Sfx = preload("res://mods-unpacked/cejdan-StoryMode/boss/sfx.gd")
const Boss = preload("res://mods-unpacked/cejdan-StoryMode/data/boss.gd")

const TECH := "storytentacle"
const TECH_EYE := "storygreateye"

static var _uid: int = 900000

var great: bool = false
var height: float = 96.0
var dome_dir: float = 1.0        # +1 when the dome is to the right
var time: float = 0.0
var emerge: float = 0.0          # 0 underground .. 1 fully out
var slam_t: float = -1.0         # seconds into a slam, -1 when idle
var next_slam: float = 3.0
var flash: float = 0.0
var sink: float = 0.0
var slams: int = 0
var seed_f: float = 0.0
var _hitbox: CollisionShape2D = null
var _did_hit: bool = false

const SLAM_TELE := 1.0
const SLAM_STRIKE := 0.18
const SLAM_HOLD := 0.35
const SLAM_BACK := 0.6


# Registers the two kinds' monster data (health from `unit_hp`).
static func register(unit_hp: float) -> void:
	for pair: Array in [[TECH, unit_hp, CONST.MONSTER_MEDIUM], [TECH_EYE, unit_hp * 3.0, CONST.MONSTER_LARGE]]:
		var id: String = pair[0]
		Data.apply(id + ".health", pair[1])
		Data.apply(id + ".tier", 3)
		Data.apply(id + ".size", pair[2])
		Data.apply(id + ".fullstunthreshold", 100000.0)
		Data.apply(id + ".stunpriority", 0)
		Data.apply(id + ".minstunlevel", 0.85)


# A new tentacle at `pos` (global), not yet in the tree.
static func make(pos: Vector2, dome_x: float, is_great: bool):
	var m: Area2D = Area2D.new()
	m.set_script(load("res://mods-unpacked/cejdan-StoryMode/boss/surface_tentacle.gd"))
	m.name = "StoryGreatEye" if is_great else "StoryTentacle"
	m.great = is_great
	m.techId = TECH_EYE if is_great else TECH
	m.teamId = "team1"
	m.height = 120.0 if is_great else randf_range(84.0, 108.0)
	m.dome_dir = 1.0 if dome_x > pos.x else -1.0
	m.seed_f = randf() * TAU
	m.collision_layer = 128
	m.collision_mask = 0
	m.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	m.add_to_group("monster")
	_uid += 1
	m.UID = _uid
	# The vanilla Monster wants an animated sprite with the flash material; the
	# tentacle draws itself, so the sprite is one clear pixel.
	var spr := AnimatedSprite2D.new()
	spr.name = "Sprite2D"
	var frames := SpriteFrames.new()
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	frames.add_frame("default", ImageTexture.create_from_image(img))
	spr.sprite_frames = frames
	spr.material = load("res://content/monster/FlashMaterial.tres")
	m.add_child(spr)
	m.sprite = spr
	var box := CollisionShape2D.new()
	box.name = "HitboxDefault"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(34.0 if is_great else 22.0, m.height)
	box.shape = shape
	box.position = Vector2(0, -m.height * 0.5)
	m.add_child(box)
	m._hitbox = box
	m.global_position = pos
	return m


func init():
	next_slam = 2.5 + randf() * 2.5
	invulnerable = true
	Sfx.play("grow", -3.0, 0.7 if great else randf_range(0.9, 1.2))
	InputSystem.shake(18.0 if great else 10.0, 0.6, 20.0, global_position)


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
	return Vector2(x, y)


func _dome_gap() -> float:
	var dome = Level.getDome(teamId)
	return (dome.global_position.x - global_position.x) if dome != null else dome_dir * 150.0


func subProcess(delta: float) -> void:
	time += delta
	flash = maxf(0.0, flash - delta)
	if emerge < 1.0:
		emerge = minf(1.0, emerge + delta / 1.1)
		if emerge >= 1.0:
			invulnerable = false
	elif slam_t >= 0.0:
		slam_t += delta
		if slam_t >= SLAM_TELE + SLAM_STRIKE and not _did_hit:
			_did_hit = true
			_hit_dome()
		if slam_t >= SLAM_TELE + SLAM_STRIKE + SLAM_HOLD + SLAM_BACK:
			slam_t = -1.0
			next_slam = Boss.FINALE_SLAM_EVERY * randf_range(0.8, 1.25)
	else:
		next_slam -= delta
		if next_slam <= 0.0:
			slam_t = 0.0
			_did_hit = false
	if _hitbox != null:
		var t: Vector2 = tip()
		_hitbox.position = Vector2(t.x * 0.5, t.y * 0.5)
	queue_redraw()


func _hit_dome() -> void:
	var dome = Level.getDome(teamId)
	if dome == null or not multiplayer.is_server():
		return
	slams += 1
	var dmg: int = int(Boss.FINALE_SLAM_DAMAGE * (2.0 if great else 1.0))
	dome.requestMeleeDamage(dmg, to_global(tip()), self)
	InputSystem.shake(26.0 if great else 16.0, 0.4, 20.0, global_position)
	Sfx.play("whip", -2.0, 0.7 if great else 1.0)


func handleDamage():
	flash = 0.1


func animateDeath():
	Sfx.play("die" if great else "pop", -2.0, 0.8 if great else randf_range(0.8, 1.1))
	InputSystem.shake(24.0 if great else 12.0, 0.6, 18.0, global_position)
	slam_t = -1.0
	var tw := create_tween()
	if great:
		# The great eye slumps to the ground and lies there, for the surface
		# monsters to finish.
		tw.tween_property(self, "sink", 0.8, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		return
	tw.tween_property(self, "sink", 1.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): remainingFreeBlockers = 0)


func _process(_delta: float) -> void:
	if dead:
		time += _delta
		queue_redraw()


func leave(_delta: float):
	queue_redraw()


func _draw() -> void:
	if emerge <= 0.01 or sink >= 0.99:
		return
	var t: Vector2 = tip()
	var bend: float = _slam_bend()
	var col: Color = Pix.FLESH_MID
	if flash > 0.0:
		col = Color.WHITE
	elif dead:
		col = Color("231a30")
	# Rubble where it broke the ground.
	for i in 5:
		var rx: float = (i - 2) * 7.0 + sin(seed_f + i) * 2.0
		Pix.disc(self, Vector2(rx, -1.0 - absf(sin(seed_f * 3.0 + i)) * 2.0), 3.0, Color("2a2130"))
	var pts: PackedVector2Array = Pix.tentacle_points(Vector2.ZERO, t, time, 7.0 * (1.0 - absf(bend) * 0.6), seed_f, 1.0, -dome_dir * 16.0 * (1.0 - maxf(bend, 0.0)) + dome_dir * 34.0 * maxf(bend, 0.0))
	var w0: float = 13.0 if great else 9.0
	var tipp: Vector2 = Pix.tentacle(self, pts, w0, 6.0 if great else 3.5, col)
	var look: Vector2 = Vector2(_dome_gap(), -30.0)
	var n: int = pts.size()
	if not dead:
		for j in range(6, n - 6, 9):
			Pix.eye(self, pts[j], Pix.eye_frame_toward(pts[j], look, time, j * 0.3 + seed_f), 0.5)
	if great:
		_draw_great(tipp, look)
	else:
		Pix.disc(self, tipp, 9.0, Pix.EDGE)
		if dead:
			draw_rect(Rect2((tipp + Vector2(-4, 0)).round(), Vector2(8, 1)), Pix.FLESH_LIGHT)
		else:
			Pix.eye(self, tipp, Pix.eye_frame_toward(tipp, look, time, seed_f), 1.0, Color.WHITE if flash <= 0.0 else Color(3, 3, 3))
	# The slam's warning: the tip glows red while it rears back.
	if slam_t >= 0.0 and slam_t < SLAM_TELE:
		var f: float = slam_t / SLAM_TELE
		var blink: float = 0.4 + 0.6 * absf(sin(slam_t * (10.0 + 16.0 * f)))
		draw_arc(tipp, 13.0 + 4.0 * (1.0 - f), 0.0, TAU, 20, Color(Pix.WARN, blink), 2.0)


func _draw_great(c: Vector2, look: Vector2) -> void:
	Pix.ellipse(self, c, 22, 18, Pix.EDGE)
	Pix.ellipse(self, c, 20, 16, Pix.FLESH_LIGHT if not dead else Color("2c2238"))
	if dead:
		draw_rect(Rect2((c + Vector2(-15, 0)).round(), Vector2(30, 2)), Pix.EDGE)
		return
	Pix.ellipse(self, c, 17, 13, Pix.SCLERA if flash <= 0.0 else Color.WHITE)
	var ic: Vector2 = c + (look - c).limit_length(80.0) / 80.0 * Vector2(6, 3)
	Pix.ellipse(self, ic, 9, 9, Pix.IRIS_DEEP)
	Pix.ellipse(self, ic, 7, 7, Pix.IRIS)
	draw_rect(Rect2((ic + Vector2(-1, -7)).round(), Vector2(3, 14)), Pix.PUPIL)
	draw_rect(Rect2((ic + Vector2(-4, -5)).round(), Vector2(2, 2)), Color.WHITE)
