extends Node2D

# The final battle on the surface (#162, #171, third pass #173). The keeper
# made it home. A breath of silence (step "breath", #196) until the keeper
# takes the dome's weapon; then the bells toll, the ground splits beside the
# dome on each one, and the tentacles break out on the music's drop.
# Three rounds of tentacles (boss/surface_tentacle.gd, real targets for the
# dome's weapon). Each tentacle comes up with a row of eyes, and every few
# seconds one tears free as a flyer that shoots the dome (boss/eye_flyer.gd),
# so the dome fights the ground and the sky at once; a round ends when the
# flyers are dead too. The longer the battle runs the faster they all strike
# (fury).
#
# In the last round Velle's great eye (boss/great_eye.gd) rises behind the
# dome and hangs straight above it. Beaten, it closes, and stays up until
# everything else is dead. Then it sways and falls to one side of the dome
# (step "fall"). The surface monsters come in from that side only (the flyers
# among them from that side or from above), tear the remains apart and thank
# the keeper in their own language (runes unless translators are installed).
# Then `finished` fires and the boss director plays the saved ending.
#
# With a team (#230, online) the host runs the battle. Any keeper taking the
# dome's weapon ends the breath (a client tells the host). A client builds a
# `puppet` finale: it follows the host's steps (net_state() -> net_apply())
# and keeps a copy of each of the host's monsters (net_monsters() ->
# apply_monsters(); boss/surface_tentacle.gd), which its own dome weapon can
# hit. Every monster is put in vanilla's monster synchronizer under the same
# id on every peer, so a client's hits reach the host's monster, and its
# health and death come back. The cracks, the fall, the monsters' arrival and
# their thanks play on every instance.

const Boss = preload("res://mods-unpacked/flantor-StoryMode/data/boss.gd")
const BossText = preload("res://mods-unpacked/flantor-StoryMode/data/boss_text.gd")
const Pix = preload("res://mods-unpacked/flantor-StoryMode/boss/pix.gd")
static var _Pix = Pix  # calls go through this: lazy_preload makes const-preload calls slow
const Sfx = preload("res://mods-unpacked/flantor-StoryMode/boss/sfx.gd")
static var _Sfx = Sfx  # calls go through this: lazy_preload makes const-preload calls slow
const TENTACLE := "res://mods-unpacked/flantor-StoryMode/boss/surface_tentacle.gd"
const FLYER := "res://mods-unpacked/flantor-StoryMode/boss/eye_flyer.gd"
const GREAT := "res://mods-unpacked/flantor-StoryMode/boss/great_eye.gd"

signal finished
signal step_changed(step: String)

# Where round tentacles come up, in px left (-) or right (+) of the dome.
const SPOTS: Array = [[-150.0, 160.0], [-215.0, -125.0, 135.0], [-200.0, -110.0, 120.0]]
const FALL_REST := 1.1        # seconds the fallen eye lies there before the monsters come
const GROUND_Y := 2.0
const RUMBLE := 2.6           # seconds of cracking ground before rounds 2 and 3 break out
# The first cracking follows the finale music's bell intro (#172): see
# Boss.FINALE_TOLLS. It ends, and round 1 breaks out, on the music's drop.

var step: String = "breath"   # breath, rumble, round1, lull, round2, lull, round3, fall, allies, thanks, done
var bells_by: String = ""     # what ended the breath: battle, idle
var great = null              # Velle's great eye (last round)
var fall_side: float = 1.0    # the side of the dome it falls to: +1 right, -1 left
var fight_t: float = 0.0      # seconds of battle so far (the rounds, not the pauses)
var fury: float = 1.0
var flyers_made: int = 0
var _crack_seeds: Dictionary = {}
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
# The first cracking, in time with the bells (#172).
var _toll_k: int = -1         # the last toll that has rung
var _beat_k: int = -1         # the last heartbeat kick
var _toll_flash: float = 0.0  # the cracks' flash from the last toll, fading
var _toll_grow: float = 0.0   # how far the cracks are open, 0..1, eased
var _toll_roll: bool = false  # the snare roll: the cracks tear open
var _clock_fallback: bool = false
var _idle_ms: float = 0.0     # real ms of the breath spent walking about
static var _alarm_loud: AudioStream = null   # the game's own alarm, while ours stands in
var _idle_last: int = -1
# Online (#230).
var puppet: bool = false      # a client's copy: follows the host's battle
var _copies: Dictionary = {}  # a client's monsters, by the host's id
var _dropped: bool = false
var _net_time: float = -1.0


func setup() -> void:
	z_index = 7
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.randomize()
	unit_hp = Boss.FINALE_TENTACLE_HP
	fall_side = 1.0 if _rng.randf() < 0.5 else -1.0
	# The ship stands on the dome's left (#368): the eye falls, and the
	# monsters gather, on the other side.
	var Ship = load("res://mods-unpacked/flantor-StoryMode/endgame/ship.gd")
	if Ship.find() != null:
		fall_side = 1.0
	if not puppet:
		# (A client gets the monsters' data and the battle stations through Data.)
		load(TENTACLE).register(Boss.FINALE_TENTACLE_HP)
		load(GREAT).register(Boss.FINALE_EYE_HP)
		load(FLYER).register(Boss.FINALE_FLYER_HP)
		# The dome goes to battle stations, as for a wave.
		Data.apply("team1.monsters.wavepresent", true)
		Data.apply("team1.monsters.wavebattle", true)
	# The breath is silent: no wave-start gong riser (the game plays it when a
	# wave begins), and the blinking alarm is turned down for the bells.
	for p in Audio.soundPlayers:
		if p.playing and p.stream == Audio.wavestart:
			p.stop()
	quiet_alarm(true)
	ModLoaderLog.info("Finale: tentacle %.0f, great eye %.0f, flyer %.0f health" % [Boss.FINALE_TENTACLE_HP, Boss.FINALE_EYE_HP, Boss.FINALE_FLYER_HP], "flantor-StoryMode")
	# The chase music fades into the breath of silence.
	var m = _music()
	if m != null:
		m.hush()
	ModLoaderLog.info("Finale: breath", "flantor-StoryMode")


func _exit_tree() -> void:
	quiet_alarm(false)


# Swaps the game's alarm sound for a copy Boss.FINALE_ALARM_DB quieter (on),
# or puts the game's own back (off).
static func quiet_alarm(on: bool) -> void:
	if on and _alarm_loud == null:
		var q = quieter(Audio.alarm, Boss.FINALE_ALARM_DB)
		if q != null:
			_alarm_loud = Audio.alarm
			Audio.alarm = q
	elif not on and _alarm_loud != null:
		Audio.alarm = _alarm_loud
		_alarm_loud = null


# A copy of a 16-bit WAV stream, `db` louder (negative: quieter); null for
# any other kind of stream.
static func quieter(s, db: float) -> AudioStreamWAV:
	if not (s is AudioStreamWAV) or s.format != AudioStreamWAV.FORMAT_16_BITS:
		return null
	var q: AudioStreamWAV = s.duplicate()
	var data: PackedByteArray = s.data
	var g: float = db_to_linear(db)
	for i in range(0, data.size() - 1, 2):
		data.encode_s16(i, int(data.decode_s16(i) * g))
	q.data = data
	return q


func _music():
	var d = load("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd").instance()
	return d.music if d != null else null


# What the player is doing, by the deepest input processor: "battle" at the
# dome's weapon, "console" in the console's menu, "keeper" walking about, or
# "" for anything else (the shop, the pause menu).
static func activity() -> String:
	var leaf = InputSystem.getLastChild()
	if leaf == null:
		return ""
	if leaf is BattleInputProcessor:
		return "battle"
	if leaf is KeeperInputProcessor:
		return "keeper"
	var sc = leaf.get_script()
	if sc != null and sc.resource_path.ends_with("StationInputProcessor.gd"):
		return "console"
	return ""


# The breath before the bells. Runs on real time, as the console's menu and
# the shop pause the game. Battle starts the bells; walking about for
# Boss.FINALE_BREATH seconds does too; the menu and the shop hold them.
func _breath() -> void:
	var now: int = Time.get_ticks_msec()
	var dt: float = 0.0 if _idle_last < 0 else float(now - _idle_last)
	_idle_last = now
	var doing: String = activity()
	if doing == "battle":
		_start_bells("battle")
		return
	if doing != "keeper":
		_idle_ms = 0.0   # in a menu or the shop: the breath starts over after
		return
	_idle_ms += dt
	if _idle_ms >= Boss.FINALE_BREATH * 1000.0:
		_start_bells("idle")


func _start_bells(by: String) -> void:
	bells_by = by
	ModLoaderLog.info("Finale: the bells (%s)" % by, "flantor-StoryMode")
	var m = _music()
	if m != null:
		m.finale()
	_set_step("rumble")


func _set_step(s: String) -> void:
	step = s
	t = 0.0
	ModLoaderLog.info("Finale: " + s, "flantor-StoryMode")
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
		_spawn(_ground(off), d.global_position.x)
	if i == SPOTS.size() - 1:
		great = load(GREAT).make()
		great.fury = fury
		add_child(great)
		alive.append(great)
		_net_register(great)
		_Sfx.hitstop(0.3, 0.35)


# The spots of round `i`: px left (-) or right (+) of the dome.
func spots(i: int) -> Array:
	return SPOTS[i].duplicate()


func _crack_seed(off: float) -> int:
	if not _crack_seeds.has(off):
		_crack_seeds[off] = _rng.randi()
	return _crack_seeds[off]


func _spawn(pos: Vector2, dome_x: float) -> void:
	var m = load(TENTACLE).make(pos, dome_x, _crack_seed(pos.x - dome_x))
	m.fury = fury
	m.eye_freed.connect(_eye_freed)
	add_child(m)
	alive.append(m)
	_net_register(m)


# An eye tears free of a living tentacle and takes to the sky over the dome.
func _eye_freed(at: Vector2) -> void:
	if puppet or not step.begins_with("round") or GameWorld.lost:
		return
	var d = _dome()
	# Its place: on the side it came from, higher with each one already up there.
	var side_left: bool = at.x < d.global_position.x
	var angles: Array = Boss.FINALE_FLYER_ANGLES
	var up: float = float(angles[flyers_alive() % angles.size()]) + _rng.randf_range(-0.08, 0.08)
	var f = load(FLYER).make(at, (PI - up) if side_left else up)
	f.fury = fury
	add_child(f)
	alive.append(f)
	_net_register(f)
	flyers_made += 1


func flyers_alive() -> int:
	var n: int = 0
	for m in alive:
		if is_instance_valid(m) and not m.dead and m.techId == load(FLYER).TECH:
			n += 1
	return n


func living() -> int:
	var n: int = 0
	for m in alive:
		if is_instance_valid(m) and not m.dead:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	if step == "breath":
		if not GameWorld.lost and not puppet:
			_breath()
		return
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
	if step.begins_with("round"):
		fight_t += delta
		fury = maxf(Boss.FINALE_FURY_FLOOR, 1.0 - Boss.FINALE_FURY_PER_S * fight_t)
		for m in alive:
			if is_instance_valid(m) and not m.dead:
				m.fury = fury
	match step:
		"rumble", "lull":
			if step == "rumble" and round_i == -1:
				# The first cracking keeps time with the bells (#172).
				_toll_rumble(delta)
				queue_redraw()
				return
			# The ground works itself open where they will come up.
			if fposmod(t, 0.2) < delta:
				InputSystem.shake(5.0 + t * 5.0, 0.22, 24.0)
			if fposmod(t, 0.7) < delta:
				_Sfx.play("drop", -12.0 + t * 3.0, _rng.randf_range(0.6, 0.9))
			if fposmod(t, 0.09) < delta and t > 0.5:
				var offs: Array = spots(round_i + 1)
				var at: Vector2 = to_local(_ground(offs[_rng.randi() % offs.size()]))
				_dust.append({"p": at + Vector2(_rng.randf_range(-14, 14), 0), "v": Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-110, -40) * (0.5 + t / RUMBLE)),
					"life": _rng.randf_range(0.3, 0.7), "col": Color("3b2f44")})
			if t >= RUMBLE and not puppet:
				_spawn_round(round_i + 1)
				if round_i == SPOTS.size() - 1:
					_Sfx.play("roar", 0.0, 0.75)
				_set_step("round%d" % (round_i + 1))
		"round1", "round2", "round3":
			if t > 1.5 and living() == 0 and not puppet:
				if round_i < SPOTS.size() - 1:
					_set_step("lull")
				else:
					# Everything else is dead: the closed eye comes down.
					Data.apply("team1.monsters.wavepresent", false)
					Data.apply("team1.monsters.wavebattle", false)
					quiet_alarm(false)
					if is_instance_valid(great):
						great.fall(fall_side)
					_set_step("fall")
		"fall":
			if puppet:
				pass
			elif not is_instance_valid(great):
				_call_allies()
				_set_step("allies")
			elif great.fallen and great.fall_t >= great.FALL_SWAY + great.FALL_DROP + FALL_REST:
				eye_at = great.global_position
				_call_allies()
				_set_step("allies")
		"allies":
			_move_allies(delta)
			if t >= 7.5 and not puppet:
				_set_step("thanks")
		"thanks":
			_move_allies(delta)
			if puppet:
				pass
			elif _thanks_i < BossText.THANKS.size() and t >= 0.4 + _thanks_i * 3.6:
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
	var d = _dome()
	var n_walk: int = 0
	var n_fly: int = 0
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
		# They all come from the side the eye fell to, so nobody crosses the
		# dome. Walkers stop on the ground on either side of the eye (the
		# first ones walk past it); flyers hang over it, half of them coming
		# down from above.
		var flies: bool = float(k[3]) < 0.0
		var ground_y: float = d.global_position.y + GROUND_Y
		var stand: Vector2
		var from: Vector2
		if flies:
			stand = Vector2(eye_at.x + fall_side * (10.0 - 34.0 * n_fly), ground_y + float(k[3]))
			from = Vector2(stand.x + fall_side * 40.0, stand.y - 330.0) if n_fly % 2 == 0 else Vector2(eye_at.x + fall_side * 470.0, stand.y - 40.0)
			n_fly += 1
		else:
			var slot: float = [-36.0, 38.0, -54.0, 56.0][n_walk % 4]
			stand = Vector2(eye_at.x + fall_side * slot, ground_y)
			from = Vector2(eye_at.x + fall_side * (230.0 + 40.0 * n_walk), ground_y)
			n_walk += 1
		m.global_position = from
		add_child(m)
		var spr = m.get_node_or_null("Sprite2D")
		if spr != null:
			Style.init(spr)
			spr.flip_h = fall_side < 0.0
			if spr.sprite_frames != null and spr.sprite_frames.has_animation(k[1]):
				spr.play(k[1])
		allies.append({"node": m, "stand": stand, "from": from, "speed": float(k[4]) * (1.25 if not flies else 1.6), "walk": k[1], "attack": k[2], "there": false, "side": fall_side, "flies": flies})
	_Sfx.play("eerie", -4.0, 1.0)


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
				if spr != null:
					# Face the eye.
					spr.flip_h = m.global_position.x < eye_at.x
				if spr != null and spr.sprite_frames != null and spr.sprite_frames.has_animation(a["attack"]):
					spr.play(a["attack"])
		elif step == "allies" and fposmod(t + a["speed"] * 0.01, 0.5) < delta:
			# The final blows.
			for i in 5:
				_dust.append({"p": to_local(eye_at) + Vector2(_rng.randf_range(-16, 16), _rng.randf_range(-14, 0)),
					"v": Vector2(_rng.randf_range(-80, 80), _rng.randf_range(-150, -40)), "life": _rng.randf_range(0.4, 0.9), "col": Pix.IRIS})
			if _rng.randf() < 0.5:
				_Sfx.play("pop", -10.0, _rng.randf_range(0.9, 1.3))


func _say(i: int) -> void:
	var pd = load("res://mods-unpacked/flantor-StoryMode/pleas/plea_director.gd").instance()
	if pd == null:
		return
	var at = null
	if not allies.is_empty():
		var a: Dictionary = allies[i % allies.size()]
		if is_instance_valid(a["node"]):
			at = a["node"].global_position + Vector2(0, -44.0 - 14.0 * (i % 2))
	said.append(pd.say("arrive", at, BossText.THANKS[i], 3.8))


# Seconds into the bell intro: the music's own clock, so the ground moves with
# what the player hears; the step's clock if the music has no intro playing.
func _intro_clock() -> float:
	var Director = load("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
	var d = Director.instance()
	var at: float = -1.0
	if d != null and d.music != null and not _clock_fallback:
		at = d.music.intro_time()
	if at < 0.0 and t > 0.5:
		# No intro playing (missing file, or it ended): count on alone.
		_clock_fallback = true
	return t if _clock_fallback or at < 0.0 else at


func _toll_rumble(delta: float) -> void:
	var beat: float = _intro_clock() / Boss.FINALE_BEAT
	var tolls: Array = Boss.FINALE_TOLLS
	while _toll_k + 1 < tolls.size() and beat >= float(tolls[_toll_k + 1]):
		_toll_k += 1
		_on_toll(_toll_k)
	var beats: Array = Boss.FINALE_HEARTBEATS
	while _beat_k + 1 < beats.size() and beat >= float(beats[_beat_k + 1]):
		_beat_k += 1
		InputSystem.shake(4.0 + 1.5 * _beat_k, 0.18, 20.0)
		_burst(4 + _beat_k, 0.6)
	_toll_roll = beat >= Boss.FINALE_ROLL_BEAT
	# Each toll opens the cracks a step; the roll tears them right open.
	var goal: float = float(_toll_k + 1) / float(tolls.size() + 1)
	if _toll_roll:
		goal = lerpf(goal, 1.0, clampf((beat - Boss.FINALE_ROLL_BEAT) / (Boss.FINALE_INTRO_BEATS - Boss.FINALE_ROLL_BEAT), 0.0, 1.0))
		if fposmod(t, 0.06) < delta:
			InputSystem.shake(6.0 + 6.0 * goal, 0.12, 30.0)
			_burst(2, 1.0)
	_toll_grow += (goal - _toll_grow) * minf(1.0, delta * 10.0)
	_toll_flash = maxf(0.0, _toll_flash - delta * 1.6)
	if beat >= Boss.FINALE_INTRO_BEATS and not _dropped:
		# The drop: they break out with the music.
		InputSystem.shake(20.0, 0.7, 16.0)
		_burst(30, 1.6)
		if puppet:
			# (The host's tentacles arrive with its next word.)
			_dropped = true
			return
		_spawn_round(0)
		_set_step("round1")


func _on_toll(k: int) -> void:
	_toll_flash = 1.0
	# No sound of its own: the bell is the crack.
	InputSystem.shake(7.0 + 3.0 * k, 0.6, 14.0)
	_burst(10 + 5 * k, 0.8 + 0.15 * k)
	ModLoaderLog.info("Finale: toll %d (cracks %.2f)" % [k, float(k + 1) / float(Boss.FINALE_TOLLS.size() + 1)], "flantor-StoryMode")


# Rubble thrown up from the cracks of round 1's spots.
func _burst(n: int, force: float) -> void:
	var offs: Array = spots(0)
	for j in n:
		var at: Vector2 = to_local(_ground(offs[_rng.randi() % offs.size()]))
		_dust.append({"p": at + Vector2(_rng.randf_range(-14, 14), 0), "v": Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-130, -50) * force),
			"life": _rng.randf_range(0.3, 0.8), "col": Color("3b2f44") if j % 3 else Color(Pix.VIOLET_LIGHT, 0.9)})


func _draw() -> void:
	for f: Dictionary in _dust:
		draw_rect(Rect2(f["p"].round(), Vector2(2, 2)), Color(f.get("col", Color("5a4a66")), clampf(f["life"] * 2.0, 0.0, 1.0)))
	if step == "rumble" or step == "lull":
		# The ground splits where they are about to come up: cracks spread
		# and light up from below, and the soil heaves.
		var tolled: bool = round_i == -1
		var grow: float = _toll_grow if tolled else clampf(t / (RUMBLE * 0.85), 0.0, 1.0)
		var Tentacle = load(TENTACLE)
		var offs: Array = spots(round_i + 1)
		for i in offs.size():
			var off: float = offs[i]
			var p: Vector2 = to_local(_ground(off))
			var big: bool = false
			var glow: float = grow * (0.55 + 0.45 * sin(t * (10.0 + 14.0 * grow) + i))
			var pulse: float = 0.0
			if tolled:
				# Dim between tolls, flaring on each one; flickering in the roll.
				pulse = _toll_flash
				glow = clampf(0.25 + 0.75 * _toll_flash, 0.0, 1.0)
				if _toll_roll:
					glow = 0.6 + 0.4 * sin(t * 40.0 + i)
			Tentacle.draw_light(self, p, _crack_seed(off), grow, glow * grow, big)
			Tentacle.draw_cracks(self, p, Tentacle.crack_lines(_crack_seed(off), big), grow, glow)
			# A mound pushing up, shuddering.
			var heave: float = grow * grow * (9.0 if big else 6.0) + pulse * 3.0
			var jit: float = sin(t * 47.0 + i * 3.0) * grow
			_Pix.ellipse(self, p + Vector2(jit, 1), (16.0 if big else 11.0) * (0.5 + 0.5 * grow), heave, Color("2a2130"), -1.0, 0.0)
			draw_rect(Rect2((p + Vector2(-2, -heave)).round(), Vector2(4, 1)), Color(Pix.VIOLET_LIGHT, glow))


# ---------------------------------------------------------------- online (#230)

static func _synchronizer():
	var mm = Level.monstersByTeamId.get("team1") if Level.monstersByTeamId != null else null
	return mm.monsterSynchronizer if mm != null and is_instance_valid(mm) else null


# Puts monster `m` in vanilla's monster synchronizer, under the same id on
# every peer: a client's weapon hits it there, and the host's health and
# death reach the client's copy.
func _net_register(m) -> void:
	if Network.is_offline_mode():
		return
	var sync = _synchronizer()
	if sync == null:
		return
	sync.monsters[m.UID] = m
	m.died.connect(sync._on_monster_died.bind(m))


# The host's battle for clients: the step and its clock, and what the copies
# need to look the same.
func net_state() -> Array:
	return [Time.get_ticks_msec() / 1000.0, step, t, round_i, fury, fall_side, eye_at, bells_by, _crack_seeds, flyers_made]


# Every monster of the battle still here: net_record() of each.
func net_monsters() -> Array:
	var out: Array = []
	for m in alive:
		if is_instance_valid(m) and m.has_method("net_record"):
			out.append(m.net_record())
	return out


func net_apply(d: Array) -> void:
	if not puppet or d.size() < 10 or float(d[0]) < _net_time:
		return
	_net_time = float(d[0])
	var s: String = str(d[1])
	round_i = int(d[3])
	fury = float(d[4])
	fall_side = float(d[5])
	eye_at = d[6]
	bells_by = str(d[7])
	for k in d[8]:
		_crack_seeds[k] = d[8][k]
	flyers_made = int(d[9])
	if s != step:
		var was: String = step
		step = s
		t = float(d[2])
		_net_step(was)
	elif absf(t - float(d[2])) > 0.4:
		t = float(d[2])


# A client's copy enters the host's new step.
func _net_step(was: String) -> void:
	ModLoaderLog.info("Finale (client): " + step, "flantor-StoryMode")
	step_changed.emit(step)
	if was == "breath":
		var m = _music()
		if m != null:
			m.finale()
	match step:
		"round3":
			_Sfx.play("roar", 0.0, 0.75)
		"fall":
			quiet_alarm(false)
		"allies":
			_call_allies()


# A client: builds a copy of each monster of the host's it has not seen, and
# passes each its state.
func apply_monsters(list: Array) -> void:
	if not puppet:
		return
	var scripts: Dictionary = {"tentacle": TENTACLE, "flyer": FLYER, "great": GREAT}
	for r: Array in list:
		var uid: int = int(r[1])
		var m = _copies.get(uid)
		if m == null or not is_instance_valid(m):
			if bool(r[2]) or not scripts.has(r[0]) or _copies.has(uid):
				continue
			m = load(scripts[r[0]]).make_copy(r)
			m.fury = fury
			if r[0] == "tentacle":
				m.eye_freed.connect(_eye_freed)
			add_child(m)
			alive.append(m)
			_copies[uid] = m
			_net_register(m)
			if r[0] == "great":
				great = m
				_Sfx.hitstop(0.3, 0.35)
		if m.dead and r[0] != "great":
			continue
		# (The dead great eye still takes its fall from the host.)
		m.net_apply(r[r.size() - 1])
		if bool(r[2]) and not m.dead:
			# Dead on the host: its death may still be on its way.
			var sync = _synchronizer()
			if sync != null and sync.monsters.has(uid):
				sync._remote_kill_monster(uid)
			elif not m.dead:
				m.die()
				m.animateDeath()
