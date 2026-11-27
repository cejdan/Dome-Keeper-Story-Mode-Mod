extends "res://content/monster/Monster.gd"

# An eye torn free of a dead tentacle, in the final battle (#171). It rises,
# trailing its nerve, takes a place in the sky over the dome and spits bolts at
# it. A real Monster like the tentacles, so the dome's weapon aims at it and
# kills it the vanilla way. Built in code by make().
#
# Online (#230) a client draws a `puppet` copy (make_copy()) that follows the
# host's flyer and spits when it does (net_apply()); see surface_tentacle.gd.

const Pix = preload("res://mods-unpacked/flantor-StoryMode/boss/pix.gd")
static var _Pix = Pix  # calls go through this: lazy_preload makes const-preload calls slow
const Sfx = preload("res://mods-unpacked/flantor-StoryMode/boss/sfx.gd")
static var _Sfx = Sfx  # calls go through this: lazy_preload makes const-preload calls slow
const Boss = preload("res://mods-unpacked/flantor-StoryMode/data/boss.gd")
const BossMonster = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_monster.gd")
static var _BossMonster = BossMonster  # calls go through this: lazy_preload makes const-preload calls slow

const TECH := "storyeyeflyer"
const CHARGE := 0.7
const BOLT_SPEED := 150.0

static var _uid: int = 950000

var time: float = 0.0
var seed_f: float = 0.0
var perch: float = 1.0           # its place over the dome: an angle, 0 = right, PI = left
var radius: float = 160.0
var fury: float = 1.0
var fire_t: float = 3.0
var charge: float = -1.0
var bolts: Array = []
var flash: float = 0.0
var fall: float = 0.0
var shots: int = 0
var hits: int = 0
var vel: Vector2 = Vector2.ZERO
var puppet: bool = false
var _net_pos: Vector2 = Vector2.ZERO
var _net_seen: bool = false


static func register(hp: float) -> void:
	_BossMonster.register(TECH, hp, 2, CONST.MONSTER_SMALL)


# A new flyer at `pos` (global), not yet in the tree; `p_perch` is where over
# the dome it will hover (radians; 0 right, PI/2 straight above, PI left).
static func make(pos: Vector2, p_perch: float):
	var shape := CircleShape2D.new()
	shape.radius = 11.0
	_uid += 1
	var m = _BossMonster.make("res://mods-unpacked/flantor-StoryMode/boss/eye_flyer.gd", "StoryEyeFlyer", TECH, _uid, shape)
	m.perch = p_perch
	m.radius = randf_range(Boss.FINALE_FLYER_RADIUS[0], Boss.FINALE_FLYER_RADIUS[1])
	m.global_position = pos
	return m


func init():
	fire_t = randf_range(2.2, 3.4)
	vel = Vector2(randf_range(-30, 30), -120.0)
	_Sfx.play("pop", -6.0, 1.4)


func _hover_point() -> Vector2:
	var dome = Level.getDome(teamId)
	var c: Vector2 = dome.global_position + Vector2(0, -20) if dome != null else global_position
	var a: float = perch + sin(time * 0.45 + seed_f) * 0.28
	return c + Vector2(cos(a), -sin(a)) * (radius + sin(time * 0.9 + seed_f * 2.0) * 12.0)


func subProcess(delta: float) -> void:
	time += delta
	flash = maxf(0.0, flash - delta)
	if puppet:
		# Glides on at the host's speed, pulled onto the host's place.
		if _net_seen:
			_net_pos += vel * delta
			global_position = global_position.lerp(_net_pos, minf(1.0, delta * 8.0)) + vel * delta
		if charge >= 0.0:
			charge += delta
			if charge >= CHARGE:
				charge = -1.0
		_update_bolts(delta)
		queue_redraw()
		return
	# A soft spring to its place in the sky.
	var want: Vector2 = _hover_point()
	vel += (want - global_position) * 3.2 * delta
	vel *= 1.0 - delta * 1.8
	global_position += vel * delta
	if charge >= 0.0:
		charge += delta
		if charge >= CHARGE:
			charge = -1.0
			_spit()
	else:
		fire_t -= delta
		if fire_t <= 0.0 and global_position.distance_to(want) < 60.0:
			charge = 0.0
			fire_t = Boss.FINALE_FLYER_EVERY * randf_range(0.85, 1.2) * fury
	_update_bolts(delta)
	queue_redraw()


func _spit() -> void:
	var dome = Level.getDome(teamId)
	if dome == null:
		return
	var target: Vector2 = dome.getCupolaClosestPos(global_position, teamId)
	bolts.append({"p": global_position, "to": target})
	shots += 1
	_Sfx.play("spit", -10.0, randf_range(1.1, 1.4))


func _update_bolts(delta: float) -> void:
	for i in range(bolts.size() - 1, -1, -1):
		var b: Dictionary = bolts[i]
		b["p"] = b["p"].move_toward(b["to"], BOLT_SPEED * delta)
		if b["p"].distance_to(b["to"]) < 1.0:
			bolts.remove_at(i)
			var dome = Level.getDome(teamId)
			if dome != null and multiplayer.is_server():
				hits += 1
				dome.requestProjectileDamage(int(Boss.FINALE_FLYER_DAMAGE), b["to"], self)


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
	return ["flyer", UID, dead, global_position, perch, radius, seed_f,
		PackedFloat32Array([global_position.x, global_position.y, vel.x, vel.y, charge, shots, time])]


static func make_copy(r: Array):
	var m = make(r[3], float(r[4]))
	m.puppet = true
	m.UID = int(r[1])
	m.radius = float(r[5])
	m.seed_f = float(r[6])
	return m


func net_apply(d: PackedFloat32Array) -> void:
	if d.size() < 7 or dead:
		return
	_net_pos = Vector2(d[0], d[1])
	if not _net_seen:
		_net_seen = true
		global_position = _net_pos
	vel = Vector2(d[2], d[3])
	if d[4] >= 0.0 and charge < 0.0:
		charge = d[4]
	while shots < int(d[5]):
		_spit()
		charge = -1.0
	if absf(time - d[6]) > 0.5:
		time = d[6]


func animateDeath():
	_Sfx.play("pop", -3.0, randf_range(1.2, 1.5))
	bolts.clear()
	charge = -1.0
	var tw := create_tween()
	tw.tween_property(self, "fall", 1.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): remainingFreeBlockers = 0)


func _process(delta: float) -> void:
	if dead:
		time += delta
		queue_redraw()


func leave(_delta: float):
	queue_redraw()


func _draw() -> void:
	var o: Vector2 = Vector2(0, fall * fall * 90.0)
	var a: float = 1.0 - fall
	if a <= 0.02:
		return
	# The nerve it tore out with, trailing below.
	var tail: Vector2 = o + Vector2(-vel.x * 0.08, 20.0) + Vector2(sin(time * 3.0 + seed_f) * 4.0, 0)
	var pts: PackedVector2Array = _Pix.tentacle_points(o + Vector2(0, 6), tail, time * 2.0, 3.0, seed_f)
	_Pix.tentacle(self, pts, 3.0, 1.0, Pix.FLESH_MID, a)
	if charge >= 0.0:
		var c: float = charge / CHARGE
		_Pix.disc(self, o, 11.0 + c * 5.0, Color(Pix.VIOLET, 0.3 + 0.4 * c))
	var dome = Level.getDome(teamId)
	var look: Vector2 = to_local(dome.global_position) if dome != null else Vector2.DOWN * 50.0
	var mod: Color = Color(3, 3, 3, a) if flash > 0.0 else Color(1, 1, 1, a)
	if dead:
		mod = Color(0.45, 0.4, 0.5, a)
	_Pix.great_mini(self, o, look, time, seed_f, 1.1, mod)
	for b: Dictionary in bolts:
		var p: Vector2 = to_local(b["p"])
		var back: Vector2 = (b["p"] - b["to"]).normalized()
		for i in 3:
			_Pix.disc(self, p + back * (3.0 + i * 3.0), 2.0 - i * 0.5, Color(Pix.VIOLET, 0.5 - i * 0.14))
		_Pix.disc(self, p, 4.0, Pix.EDGE)
		_Pix.disc(self, p, 3.0, Pix.VIOLET if fposmod(time * 8.0, 1.0) < 0.5 else Pix.VIOLET_LIGHT)
