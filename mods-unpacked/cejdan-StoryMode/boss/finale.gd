extends Node2D

# The final battle on the surface (#162). The keeper made it home; the
# tentacles burst through the ground beside the dome. Two rounds of tentacles
# (boss/surface_tentacle.gd, real targets for the dome's weapon), the second
# with Velle's great eye. After the final blow the surface monsters come in
# from both sides, tear the remains apart and thank the keeper in their own
# language (runes unless translators are installed). Then `finished` fires and
# the boss director plays the saved ending.

const Boss = preload("res://mods-unpacked/cejdan-StoryMode/data/boss.gd")
const BossText = preload("res://mods-unpacked/cejdan-StoryMode/data/boss_text.gd")
const Pix = preload("res://mods-unpacked/cejdan-StoryMode/boss/pix.gd")
const Sfx = preload("res://mods-unpacked/cejdan-StoryMode/boss/sfx.gd")
const TENTACLE := "res://mods-unpacked/cejdan-StoryMode/boss/surface_tentacle.gd"

signal finished
signal step_changed(step: String)

# Where round tentacles come up, in px left (-) or right (+) of the dome.
const SPOTS: Array = [[-140.0, 150.0], [-205.0, -120.0, 125.0]]
const EYE_SPOT := 210.0
const GROUND_Y := 2.0

var step: String = "rumble"   # rumble, round1, lull, round2, allies, thanks, done
var t: float = 0.0
var round_i: int = -1
var alive: Array = []
var allies: Array = []
var eye_at: Vector2 = Vector2.ZERO
var unit_hp: float = 60.0
var said: Array = []
var _thanks_i: int = 0
var _rng := RandomNumberGenerator.new()
var _dust: Array = []


func setup() -> void:
	z_index = 7
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.randomize()
	# Health follows the run: about what this run's waves have been made of.
	var weight: float = 30.0
	if Level.mode != null and Level.mode.has_method("getRunWeight"):
		weight = float(Level.mode.getRunWeight("team1"))
	unit_hp = clampf(weight * Boss.FINALE_HP_PER_RUN_WEIGHT, Boss.FINALE_TENTACLE_HP_MIN, Boss.FINALE_TENTACLE_HP_MAX)
	load(TENTACLE).register(unit_hp)
	# The dome goes to battle stations, as for a wave.
	Data.apply("team1.monsters.wavepresent", true)
	Data.apply("team1.monsters.wavebattle", true)
	ModLoaderLog.info("Finale: tentacle health %.0f (run weight %.0f)" % [unit_hp, weight], "cejdan-StoryMode")
	InputSystem.shake(14.0, 2.0, 18.0)
	Sfx.play("burrow", 0.0, 0.6)


func _set_step(s: String) -> void:
	step = s
	t = 0.0
	ModLoaderLog.info("Finale: " + s, "cejdan-StoryMode")
	step_changed.emit(s)


func _dome():
	return Level.getDome("team1")


func _ground(offset_x: float) -> Vector2:
	var d = _dome()
	return d.global_position + Vector2(offset_x, GROUND_Y)


func _spawn_round(i: int) -> void:
	round_i = i
	var d = _dome()
	for off: float in SPOTS[i]:
		_spawn(_ground(off), d.global_position.x, false)
	if i == SPOTS.size() - 1:
		eye_at = _ground(EYE_SPOT)
		_spawn(eye_at, d.global_position.x, true)


func _spawn(pos: Vector2, dome_x: float, great: bool) -> void:
	var m = load(TENTACLE).make(pos, dome_x, great)
	add_child(m)
	alive.append(m)
	for i in 14:
		_dust.append({"p": to_local(pos) + Vector2(_rng.randf_range(-10, 10), 0), "v": Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-170, -60)), "life": _rng.randf_range(0.5, 1.1)})


func living() -> int:
	var n: int = 0
	for m in alive:
		if is_instance_valid(m) and not m.dead:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	if GameWorld.paused or GameWorld.lost:
		return
	t += delta
	for i in range(_dust.size() - 1, -1, -1):
		var f: Dictionary = _dust[i]
		f["v"].y += 320.0 * delta
		f["p"] += f["v"] * delta
		f["life"] -= delta
		if f["life"] <= 0.0:
			_dust.remove_at(i)
	match step:
		"rumble":
			if fposmod(t, 0.2) < delta:
				InputSystem.shake(8.0, 0.2, 24.0)
			if t >= 2.0:
				_spawn_round(0)
				_set_step("round1")
		"round1":
			if t > 1.5 and living() == 0:
				_set_step("lull")
		"lull":
			if fposmod(t, 0.25) < delta:
				InputSystem.shake(6.0 + t * 4.0, 0.25, 22.0)
			if t >= 2.5:
				_spawn_round(1)
				Sfx.play("roar", 0.0, 0.75)
				_set_step("round2")
		"round2":
			if t > 1.5 and living() == 0:
				Data.apply("team1.monsters.wavepresent", false)
				Data.apply("team1.monsters.wavebattle", false)
				_call_allies()
				_set_step("allies")
		"allies":
			_move_allies(delta)
			if t >= 6.5:
				_set_step("thanks")
		"thanks":
			_move_allies(delta)
			if _thanks_i < BossText.THANKS.size() and t >= 0.4 + _thanks_i * 3.6:
				_say(_thanks_i)
				_thanks_i += 1
			if t >= 0.4 + BossText.THANKS.size() * 3.6 + 0.6:
				_set_step("done")
				finished.emit()
	queue_redraw()


# ---------------------------------------------------------------- the monsters come

const ALLY_KINDS: Array = [
	["res://content/monster/walker/Walker.tscn", "walk", "attack", 0.0, 60.0],
	["res://content/monster/walker/Walker.tscn", "walk", "attack", 0.0, 52.0],
	["res://content/monster/flyer/Flyer.tscn", "fly", "shoot", -70.0, 70.0],
	["res://content/monster/walker/Walker.tscn", "walk", "attack", 0.0, 56.0],
	["res://content/monster/flyer/Flyer.tscn", "fly", "shoot", -95.0, 64.0],
	["res://content/monster/walker/Walker.tscn", "walk", "attack", 0.0, 48.0],
]


func _call_allies() -> void:
	for i in ALLY_KINDS.size():
		var k: Array = ALLY_KINDS[i]
		if not ResourceLoader.exists(k[0]):
			continue
		# The game's own monster, with its brain taken out: only its looks walk.
		var m: Node2D = load(k[0]).instantiate()
		for c in m.get_children():
			for sig: Dictionary in c.get_signal_list():
				for con: Dictionary in c.get_signal_connection_list(sig["name"]):
					if con["callable"].get_object() == m:
						c.disconnect(sig["name"], con["callable"])
		m.set_script(null)
		m.remove_from_group("monster")
		if m is Area2D:
			m.collision_layer = 0
			m.monitorable = false
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var stand: Vector2 = eye_at + Vector2(side * (26.0 + 16.0 * (i / 2)), float(k[3]))
		m.global_position = Vector2(eye_at.x + side * (420.0 + 40.0 * i), stand.y)
		add_child(m)
		var spr = m.get_node_or_null("Sprite2D")
		if spr != null:
			Style.init(spr)
			spr.flip_h = side < 0.0
			if spr.sprite_frames != null and spr.sprite_frames.has_animation(k[1]):
				spr.play(k[1])
		allies.append({"node": m, "stand": stand, "speed": float(k[4]), "walk": k[1], "attack": k[2], "there": false, "side": side})
	Sfx.play("eerie", -4.0, 1.0)


func _move_allies(delta: float) -> void:
	for a: Dictionary in allies:
		var m: Node2D = a["node"]
		if not is_instance_valid(m):
			continue
		if not a["there"]:
			m.global_position = m.global_position.move_toward(a["stand"], a["speed"] * delta)
			if m.global_position.distance_to(a["stand"]) < 1.0:
				a["there"] = true
				var spr = m.get_node_or_null("Sprite2D")
				if spr != null and spr.sprite_frames != null and spr.sprite_frames.has_animation(a["attack"]):
					spr.play(a["attack"])
		elif step == "allies" and fposmod(t + a["speed"] * 0.01, 0.5) < delta:
			# The final blows.
			for i in 5:
				_dust.append({"p": to_local(eye_at) + Vector2(_rng.randf_range(-16, 16), _rng.randf_range(-14, 0)),
					"v": Vector2(_rng.randf_range(-80, 80), _rng.randf_range(-150, -40)), "life": _rng.randf_range(0.4, 0.9), "col": Pix.IRIS})
			if _rng.randf() < 0.5:
				Sfx.play("pop", -10.0, _rng.randf_range(0.9, 1.3))


func _say(i: int) -> void:
	var pd = load("res://mods-unpacked/cejdan-StoryMode/pleas/plea_director.gd").instance()
	if pd == null:
		return
	var at = null
	if not allies.is_empty():
		var a: Dictionary = allies[i % allies.size()]
		if is_instance_valid(a["node"]):
			at = a["node"].global_position + Vector2(0, -44.0 - 14.0 * (i % 2))
	said.append(pd.say("arrive", at, BossText.THANKS[i], 3.8))


func _draw() -> void:
	for f: Dictionary in _dust:
		draw_rect(Rect2(f["p"].round(), Vector2(2, 2)), Color(f.get("col", Color("5a4a66")), clampf(f["life"] * 2.0, 0.0, 1.0)))
	if step == "rumble" or step == "lull":
		# Cracks of violet light where they are about to come up.
		var next: int = 0 if step == "rumble" else 1
		var offs: Array = SPOTS[next].duplicate()
		if next == SPOTS.size() - 1:
			offs.append(EYE_SPOT)
		for off: float in offs:
			var p: Vector2 = to_local(_ground(off))
			var a: float = clampf(t / 2.0, 0.0, 1.0) * (0.5 + 0.5 * sin(t * 18.0))
			draw_rect(Rect2((p + Vector2(-8, -1)).round(), Vector2(16, 2)), Color(Pix.VIOLET_LIGHT, a))
			draw_rect(Rect2((p + Vector2(-3, -4)).round(), Vector2(2, 4)), Color(Pix.VIOLET, a))
			draw_rect(Rect2((p + Vector2(4, -3)).round(), Vector2(2, 3)), Color(Pix.VIOLET, a))
