extends Node

# The boss sequence (#160-#163), run by the Story Mode game mode node:
#
#   ""       nothing yet. Starts when the horror is awake (the keeper broke
#            into the boss chamber), its awakening beat has been read, and the
#            keeper is in the chamber.
#   fight    Velle in the chamber (boss/velle.gd). The chamber is sealed.
#   chase    Velle's body is dead; its tentacles hunt the keeper back to the
#            dome (boss/chase.gd).
#   finale   the keeper is home; the tentacles burst through the ground and
#            the dome fights them (boss/finale.gd).
#   won      the horror is defeated; the saved ending plays.
#   lost     the keeper ran out of hearts; the run ends in failure.
#
# Through all of it the keeper has hearts (boss/keeper_health.gd), the suit's
# overheat recall is jammed (overheating costs a heart instead) and the
# monster waves stop: the monsters are watching. Nobody talks either (#174):
# story beats wait and the monsters' pleas are off (_Story.boss_active()), so
# no text breaks the flow. The monsters' thanks after the finale still show.
#
# With a team (#230, online): the host runs the sequence and keeps the state
# and the hearts. The fight starts when any keeper is in the chamber; every
# instance holds its own keeper in (once it is in), and a client builds the
# boss layer with a puppet Velle that draws what the host sends (_net_velle,
# _net_events) and reports its own keeper's overheat (_net_overheated). The
# host also repeats the state and the hearts to clients every 2 s (_net_boss):
# cheap insurance on top of StoryNet's resend (#242) for the two keys a client
# can't play without. In the chase the tentacles hunt one keeper out in the
# mine at a time and a touch on any keeper costs a heart; a client draws a
# puppet chase from the host's trail and tips (_net_chase). The chase
# is over when every keeper is home (in the dome, at the dome) and at least
# one of them has been out in it. In the finale any keeper taking the dome's
# weapon starts the bells (_net_battle); a client draws a puppet finale with
# copies of the host's monsters (_net_finale, boss/finale.gd), and a won
# finale plays the saved ending on every instance.
#
# Other code reaches it through the static helpers, which do nothing outside
# the boss sequence:
#   Director.explosion_at(global_pos, kind, radius_px)   kind: bomb, mine, blast
#   Director.jams_recall()                               lava_field asks before a recall
#   Director.overheated()

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const Boss = preload("res://mods-unpacked/flantor-StoryMode/data/boss.gd")
static var _Boss = Boss  # calls go through this: lazy_preload makes const-preload calls slow
const Awakening = preload("res://mods-unpacked/flantor-StoryMode/beats/awakening.gd")
static var _Awakening = Awakening  # calls go through this: lazy_preload makes const-preload calls slow
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
static var _StoryBeats = StoryBeats  # calls go through this: lazy_preload makes const-preload calls slow
const Sfx = preload("res://mods-unpacked/flantor-StoryMode/boss/sfx.gd")
static var _Sfx = Sfx  # calls go through this: lazy_preload makes const-preload calls slow
const StoryNet = preload("res://mods-unpacked/flantor-StoryMode/net/story_net.gd")
static var _StoryNet = StoryNet  # calls go through this: lazy_preload makes const-preload calls slow
const KeeperHealth = preload("res://mods-unpacked/flantor-StoryMode/boss/keeper_health.gd")
const Chase = preload("res://mods-unpacked/flantor-StoryMode/boss/chase.gd")
static var _Chase = Chase  # calls go through this: lazy_preload makes const-preload calls slow

const GROUP := "story-boss"
const STATE := Story.BOSS_STATE
const TILE := 24.0
const NET_HZ := 15.0          # Velle's state to clients, times a second
const NET_REPEAT := 2.0       # seconds between repeats of the state and hearts

signal state_changed(state: String)

# Playtests of older tickets switch the whole sequence off.
static var enabled: bool = true

var layer: Node2D = null
var health: Node = null
var velle: Node2D = null
var chase: Node2D = null
var finale: Node2D = null
var music: Node = null
var arena: Rect2 = Rect2()
var _booted: bool = false
var _seal_flash: float = 0.0
var _cam_blends: Dictionary = {}   # playerId -> 0..1, each local keeper's camera hold (#231)
var _chase_left_dome: bool = false
var dev_path: Array = []      # the shaft `--boss=chase` drilled (tile cells, bottom to top)
var _held: Dictionary = {}    # this instance's keepers the chamber has sealed in (playerId -> true)
var _net_t: float = 0.0
var _net_repeat: float = 0.0
var _client_state: String = ""
var _chase_asked: float = -10.0
var _battle_told: float = -10.0


static func instance():
	var tree = Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return null
	return tree.get_first_node_in_group(GROUP)


static func current() -> String:
	return str(Data.ofOr(STATE, ""))


static func jams_recall() -> bool:
	return instance() != null and _Story.boss_active()


# A keeper of this instance overheated during the boss sequence: a heart, not a
# recall. The hearts are the host's: a client asks it. `keeper` defaults to the
# first local one (splitscreen passes the one that overheated, #231).
static func overheated(keeper = null) -> void:
	var n = instance()
	var k = keeper if keeper != null and is_instance_valid(keeper) else _Story.local_keeper()
	if n == null or k == null:
		return
	if Network.is_client():
		n.rpc_id(1, "_net_overheated", k.playerId)
	else:
		n._overheat(k)


static func explosion_at(global_pos: Vector2, kind: String, radius_px: float = 0.0) -> void:
	var n = instance()
	if n != null:
		n._explosion(global_pos, kind, radius_px)


func _ready() -> void:
	name = "StoryBoss"
	add_to_group(GROUP)
	music = load(Story.MOD_DIR + "boss/boss_music.gd").new()
	add_child(music)


func state() -> String:
	return current()


func _set_state(s: String) -> void:
	Data.apply(STATE, s)
	_net_repeat = 0.0
	ModLoaderLog.info("Boss: " + (s if s != "" else "(reset)"), Story.LOG)
	state_changed.emit(s)


func _ready_to_run() -> bool:
	if not enabled or not multiplayer.is_server() or not _Story.is_story():
		return false
	# A playtest scenario's boot() can switch the sequence off: `boss: false`.
	if _Story.scenario_boot().get("boss", true) == false:
		return false
	var stage = Level.stage
	if stage == null or not (stage is LevelStage) or not stage.keeperInputStarted:
		return false
	if Level.map == null or not is_instance_valid(Level.map) or not Level.map.isMapReady():
		return false
	if SaveGame.currentLoadingSavegame or _Story.local_keeper() == null:
		return false
	return true


func _chamber() -> Rect2i:
	var ch = Level.map.tileData.get_meta("story_boss_chamber") if Level.map.tileData.has_meta("story_boss_chamber") else null
	return ch if ch is Rect2i else Rect2i()


func _ensure_layer() -> bool:
	if layer != null and is_instance_valid(layer):
		return true
	var ch: Rect2i = _chamber()
	if ch.size == Vector2i.ZERO:
		return false
	layer = Node2D.new()
	layer.name = "StoryBossLayer"
	Level.map.add_child(layer)
	var tl: Vector2 = layer.to_local(Level.map.getTilePos(Vector2(ch.position))) - Vector2(TILE, TILE) * 0.5
	arena = Rect2(tl, Vector2(ch.size) * TILE)
	health = load(Story.MOD_DIR + "boss/keeper_health.gd").new()
	health.name = "KeeperHealth"
	layer.add_child(health)
	health.died.connect(_keeper_died)
	health.hit.connect(_keeper_hit)
	return true


func _physics_process(delta: float) -> void:
	if Network.is_client():
		_client_process(delta)
		return
	if not _ready_to_run() or GameWorld.paused:
		return
	if GameWorld.won or GameWorld.lost:
		return
	if not _booted:
		_booted = true
		_resume()
		if OS.has_feature("editor") and _Story.user_arg("scenario") == "" and _Story.has_user_arg("boss"):
			_dev_boss(_Story.user_arg("boss"))
	_net_host(delta)
	match current():
		"":
			_held.clear()
			if not _Awakening.is_awake() or _StoryBeats.is_open() or not _StoryBeats.has_played("boss_chamber"):
				return
			if not _ensure_layer():
				return
			# Any keeper of the team in the chamber starts it.
			for k in Keepers.getAll():
				if k != null and is_instance_valid(k) and not k.disabled and arena.grow(-4.0).has_point(layer.to_local(k.global_position)):
					_start_fight()
					break
		"fight":
			_seal(delta)
			for k in Keepers.getAll():
				if k != null and is_instance_valid(k) and arena.grow(30.0).has_point(layer.to_local(k.global_position)):
					_recharge_blaster(k, delta)
			if velle != null and is_instance_valid(velle):
				music.fight(velle.phase)
		"chase":
			if chase != null and is_instance_valid(chase):
				music.chase(1.0 - chase.my_gap() / 260.0)
			if _all_home():
				_chase_done()
		"finale":
			# Silence while the finale draws its breath; the bells after.
			if finale != null and is_instance_valid(finale) and finale.step == "breath":
				music.hush()
			else:
				music.finale()


func _process(delta: float) -> void:
	# The camera holds the whole chamber during the fight, for a keeper in it
	# (each local keeper's own camera, #231).
	if Level.viewports == null or layer == null or not is_instance_valid(layer):
		return
	for keeper in _Story.local_keepers():
		var cam = Level.viewports.getPlayerCam(keeper.playerId)
		if cam == null or not ("targetOffset" in cam):
			continue
		var want: float = 1.0 if current() == "fight" and _held.has(keeper.playerId) else 0.0
		var blend: float = _cam_blends.get(keeper.playerId, 0.0)
		if blend == want and want == 0.0:
			continue
		blend = move_toward(blend, want, delta * 1.5)
		_cam_blends[keeper.playerId] = blend
		var centre: Vector2 = layer.to_global(arena.get_center() + Vector2(0, -10))
		cam.targetOffset = (centre - keeper.global_position) * blend


# A save made mid-fight starts the fight over; the keeper's hearts refill.
func _resume() -> void:
	match current():
		"fight":
			_set_state("")
			if _ensure_layer():
				health.refill()
		"chase":
			# A save made during the chase: the tentacles come up from below again.
			if _ensure_layer():
				_stop_waves()
				var k = _Story.local_keeper()
				_start_chase(layer.to_local(k.global_position) + Vector2(0, 220))
				_chase_left_dome = true
		"finale":
			if _ensure_layer():
				_stop_waves()
				_start_finale()
		"lost", "won":
			pass


# ---------------------------------------------------------------- the fight

func _start_fight() -> void:
	_set_state("fight")
	health.refill()
	_stop_waves()
	velle = load(Story.MOD_DIR + "boss/velle.gd").new()
	velle.name = "Velle"
	layer.add_child(velle)
	layer.move_child(velle, 0)
	velle.setup(arena, health, _chamber())
	velle.defeated.connect(_velle_defeated)
	_fight_opens()


# The chamber seals and Velle roars, for a keeper who is there.
func _fight_opens() -> void:
	_seal_flash = 1.0
	if not _Story.local_keepers().any(func(k): return arena.grow(220.0).has_point(layer.to_local(k.global_position))):
		return
	_Sfx.play("seal", -4.0, 0.7)
	_Sfx.play("roar", -3.0, 0.7)
	InputSystem.shake(20.0, 1.2, 14.0)


func _stop_waves() -> void:
	for mm in get_tree().get_nodes_in_group("monster-manager"):
		mm.disabled = true
		if mm.has_method("instantlyKillWave"):
			mm.instantlyKillWave()


# Nobody leaves: a keeper who is in the chamber during the fight is held
# inside it. Each instance holds its own keepers (a keeper moves on its
# owner's instance); a teammate still outside can come in, and then stays.
func _seal(delta: float) -> void:
	_seal_flash = maxf(0.0, _seal_flash - delta)
	var inner: Rect2 = arena.grow(-6.0)
	for keeper in Keepers.local.keepers:
		if keeper == null or not is_instance_valid(keeper):
			continue
		var kp: Vector2 = layer.to_local(keeper.global_position)
		if not _held.has(keeper.playerId):
			if not arena.grow(4.0).has_point(kp):
				continue
			_held[keeper.playerId] = true
		if inner.has_point(kp):
			continue
		var held := Vector2(clampf(kp.x, inner.position.x, inner.end.x), clampf(kp.y, inner.position.y, inner.end.y))
		keeper.global_position = layer.to_global(held)
		if "move" in keeper:
			keeper.move = Vector2.ZERO
		if _seal_flash <= 0.0:
			_seal_flash = 0.5
			_Sfx.play("clang", -10.0, 0.8)


func _recharge_blaster(keeper, delta: float) -> void:
	var key: String = keeper.playerId + ".suitblaster.charge"
	var max_key: String = keeper.teamId + ".suitblaster.maxcharge"
	if not Data.has(key) or not Data.has(max_key):
		return
	var cur: float = float(Data.of(key))
	var cap: float = float(Data.of(max_key))
	if cur < cap:
		Data.apply(key, minf(cap, cur + delta / Boss.BLASTER_RECHARGE))


func _explosion(global_pos: Vector2, kind: String, radius_px: float) -> void:
	if velle != null and is_instance_valid(velle) and current() == "fight":
		velle.explosion(velle.to_local(global_pos), kind, radius_px)


func _velle_defeated() -> void:
	if current() != "fight":
		return
	# Hearts for the run home, by difficulty (#174).
	var got: int = health.give(_Boss.hearts_after_velle())
	if got > 0:
		_Sfx.play("heart", -2.0, 1.0)
	ModLoaderLog.info("Boss: Velle is dead; %d hearts back (%s)" % [got, Boss.TIER_NAMES[_Boss.tier()]], Story.LOG)
	_net_velle_now()
	_set_state("chase")
	_start_chase(velle.eye_pos())


# ---------------------------------------------------------------- the chase

func _start_chase(origin: Vector2) -> void:
	chase = load(Story.MOD_DIR + "boss/chase.gd").new()
	chase.name = "Chase"
	layer.add_child(chase)
	chase.setup(health, origin)
	_chase_left_dome = false
	_Sfx.play("roar", -2.0, 1.2)
	InputSystem.shake(18.0, 1.0, 18.0)


# Is the team home? Home counts only once a keeper has been out of the dome:
# the dev command starts the chase the moment the keeper is teleported away,
# while the dome still counts the keeper as inside (#176). The flag alone is
# not enough either: it can flip on a moment after a teleport out, so each
# keeper must also be at the dome. With a team (#230) every keeper must be
# home; one who never left the dome is home already.
func _all_home() -> bool:
	var dome = Level.getDome("team1")
	if dome == null:
		return false
	var home: bool = true
	for k in Keepers.getAll():
		if k == null or not is_instance_valid(k):
			continue
		if not _Chase.in_dome(k):
			_chase_left_dome = true
			home = false
		elif k.global_position.distance_to(dome.global_position) >= 240.0:
			home = false
	return home and _chase_left_dome


# The keeper made it into the dome.
func _chase_done() -> void:
	if chase != null and is_instance_valid(chase):
		chase.running = false
		# Where the tentacles stopped, for the clients' copies.
		if not Network.is_offline_mode():
			_to_clients(_net_chase.bind(chase.net_state()))
	_set_state("finale")
	_start_finale()


# ---------------------------------------------------------------- the finale

func _start_finale() -> void:
	finale = load(Story.MOD_DIR + "boss/finale.gd").new()
	finale.name = "Finale"
	layer.add_child(finale)
	finale.setup()
	# The keeper is home: the hearts were for the mine.
	health.visible = false
	finale.finished.connect(_finale_done)


func _finale_done() -> void:
	if current() != "finale":
		return
	_set_state("won")
	_finish_won()


# The dome fell in the finale (the game mode's own loss): the lost ending.
func dome_lost() -> void:
	if _Story.boss_active():
		_set_state("lost")
		music.stop()


# A client: the host won the finale. The saved ending comes from the host's
# game mode node (Storymode.horror_defeated, sent to every client, #229).
func _client_won() -> void:
	music.stop()


func _finish_won() -> void:
	music.stop()
	await get_tree().create_timer(1.0, false).timeout
	if Level.mode != null and Level.mode.has_method("horror_defeated"):
		Level.mode.horror_defeated()


func _keeper_died(cause: String) -> void:
	if not _Story.boss_active():
		return
	_set_state("lost")
	music.stop()
	ModLoaderLog.info("Boss: the keeper is dead (%s)" % cause, Story.LOG)
	_team_down()
	if velle != null and is_instance_valid(velle):
		velle.attack_enabled = false
		velle.spawn_bombs = false
		velle.orbs.clear()
		velle.attacks.clear()
		_net_velle_now()
	if Level.mode != null and Level.mode.has_method("keeper_lost"):
		Level.mode.keeper_lost()


# The hearts are the team's: at zero every keeper is gone, and the chase with them.
func _team_down() -> void:
	_Sfx.play("keeper_down", 0.0, 0.7)
	if chase != null and is_instance_valid(chase):
		chase.running = false
	for k in Keepers.getAll():
		if k != null and is_instance_valid(k):
			k.visible = false


func _overheat(keeper) -> void:
	if health == null or not is_instance_valid(health) or not _Story.boss_active():
		return
	health.set_safe(keeper, 0.0)
	health.hurt(health.to_local(keeper.global_position) + Vector2(0, 10), "overheat", keeper)


# ---------------------------------------------------------------- online (#230)

func _to_clients(call: Callable) -> void:
	Network.rpc_if_state(call, Network.ConnectionState.LEVEL_STAGE_SYNC)


# The host's side, every physics frame of a run.
func _net_host(delta: float) -> void:
	var has_velle: bool = velle != null and is_instance_valid(velle)
	if Network.is_offline_mode() or Network.clients.is_empty():
		if has_velle:
			velle.collect_events = false
		return
	var st: String = current()
	_net_repeat -= delta
	if _net_repeat <= 0.0 and (st != "" or _client_state != ""):
		_net_repeat = NET_REPEAT
		_client_state = st     # on the host: the state last sent
		_to_clients(_net_boss.bind(st, int(Data.ofOr(KeeperHealth.KEY, _Boss.max_hearts()))))
	_net_t -= delta
	var tick: bool = _net_t <= 0.0
	if tick:
		_net_t = 1.0 / NET_HZ
	if st == "chase" and tick and chase != null and is_instance_valid(chase):
		_to_clients(_net_chase.bind(chase.net_state()))
	if st == "finale" and tick and finale != null and is_instance_valid(finale):
		_to_clients(_net_finale.bind(finale.net_state(), finale.net_monsters()))
	if not has_velle:
		return
	velle.collect_events = true
	var ev: Array = velle.take_events()
	if not ev.is_empty():
		_to_clients(_net_events.bind(ev))
	if st == "fight" and tick:
		_to_clients(_net_velle.bind(velle.net_state()))


# Velle's state for certain (its death, the team's): the stream may drop one.
func _net_velle_now() -> void:
	if not Network.is_offline_mode() and velle != null and is_instance_valid(velle):
		_to_clients(_net_velle_sure.bind(velle.net_state()))


func _keeper_hit(keeper, push: Vector2) -> void:
	if not Network.is_offline_mode():
		_to_clients(_net_hurt.bind(keeper.playerId, push))


func _puppet():
	return velle if velle != null and is_instance_valid(velle) and velle.puppet else null


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_velle(data: PackedFloat32Array) -> void:
	if _puppet() != null:
		velle.net_apply(data)


@rpc("authority", "call_remote", "reliable")
func _net_velle_sure(data: PackedFloat32Array) -> void:
	if _puppet() != null:
		velle.net_apply(data)


@rpc("authority", "call_remote", "reliable")
func _net_events(ev: Array) -> void:
	if _puppet() != null:
		velle.play_events(ev)


# The state and the hearts, repeated: see the note at the top.
@rpc("authority", "call_remote", "reliable")
func _net_boss(st: String, hearts: int) -> void:
	if not Network.is_client():
		return
	if current() != st:
		Data.server_apply(STATE, st)
	if int(Data.ofOr(KeeperHealth.KEY, -1)) != hearts:
		Data.server_apply(KeeperHealth.KEY, hearts)


@rpc("authority", "call_remote", "reliable")
func _net_hurt(player_id: String, push: Vector2) -> void:
	if health != null and is_instance_valid(health):
		health.net_hit(player_id, push)


# The host's chase (boss/chase.gd net_state()); reliable, as the trail comes in parts.
@rpc("authority", "call_remote", "reliable")
func _net_chase(data: Array) -> void:
	if chase == null or not is_instance_valid(chase) or not chase.puppet:
		return
	if not chase.net_apply(data):
		_ask_chase()


# A client: the whole trail again, please (a new copy, or it missed a part).
func _ask_chase() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _chase_asked < 1.0:
		return
	_chase_asked = now
	rpc_id(1, "_net_chase_resend")


@rpc("any_peer", "call_remote", "reliable")
func _net_chase_resend() -> void:
	if multiplayer.is_server() and chase != null and is_instance_valid(chase):
		chase.resend()


# The host's finale: its step and its monsters (boss/finale.gd). Unreliable:
# every message carries all of it.
@rpc("authority", "call_remote", "unreliable_ordered")
func _net_finale(state: Array, monsters: Array) -> void:
	if finale == null or not is_instance_valid(finale) or not finale.puppet:
		return
	finale.net_apply(state)
	finale.apply_monsters(monsters)


# Client -> host: my keeper took the dome's weapon; the breath is over.
@rpc("any_peer", "call_remote", "reliable")
func _net_battle() -> void:
	if multiplayer.is_server() and current() == "finale" and finale != null and is_instance_valid(finale) and finale.step == "breath":
		finale._start_bells("battle")


# Client -> host: my keeper overheated in the boss sequence.
@rpc("any_peer", "call_remote", "reliable")
func _net_overheated(player_id: String) -> void:
	if not multiplayer.is_server():
		return
	var k = Keepers.getKeeper(player_id) if Keepers.hasKeeper(player_id) else null
	if k != null and is_instance_valid(k) and k.peerId == multiplayer.get_remote_sender_id():
		_overheat(k)


# A client's side: follow the host's state, draw its Velle, hold our own
# keeper in the chamber.
func _client_process(delta: float) -> void:
	if not enabled or not _Story.is_story() or GameWorld.paused:
		return
	var stage = Level.stage
	if stage == null or not (stage is LevelStage) or not stage.keeperInputStarted:
		return
	if Level.map == null or not is_instance_valid(Level.map) or not Level.map.isMapReady() or not _StoryNet.map_meta_ready(Level.map):
		return
	if _Story.local_keeper() == null:
		return
	var st: String = current()
	if st != _client_state:
		var was: String = _client_state
		_client_state = st
		ModLoaderLog.info("Boss (client): " + (st if st != "" else "(reset)"), Story.LOG)
		state_changed.emit(st)
		if st == "" or st == "won" or st == "lost":
			music.stop()
		if st == "lost" and was in ["fight", "chase"]:
			# The host ran out of hearts; the lost ending comes from the host's
			# game mode node (Storymode.keeper_lost, sent to every client, #229).
			_team_down()
		if st == "won":
			_client_won()
		if st == "" and _puppet() != null:
			# The fight starts over (the host loaded a save).
			velle.queue_free()
			velle = null
		if st == "" and chase != null and is_instance_valid(chase):
			chase.queue_free()
			chase = null
	match st:
		"fight":
			if not _ensure_layer():
				return
			if velle == null or not is_instance_valid(velle):
				velle = load(Story.MOD_DIR + "boss/velle.gd").new()
				velle.name = "Velle"
				velle.puppet = true
				layer.add_child(velle)
				layer.move_child(velle, 0)
				velle.setup(arena, health, _chamber())
				_reveal_chamber()
				_fight_opens()
			_seal(delta)
			music.fight(velle.phase)
		"chase":
			_held.clear()
			if not _ensure_layer():
				return
			if chase == null or not is_instance_valid(chase):
				chase = load(Story.MOD_DIR + "boss/chase.gd").new()
				chase.name = "Chase"
				chase.puppet = true
				layer.add_child(chase)
				chase.setup(health, arena.get_center())
				_reveal_chamber()
				_chase_asked = -10.0
				_ask_chase()
				_Sfx.play("roar", -2.0, 1.2)
				InputSystem.shake(18.0, 1.0, 18.0)
			music.chase(1.0 - chase.my_gap() / 260.0)
		"finale":
			if chase != null and is_instance_valid(chase):
				chase.running = false
			if not _ensure_layer():
				return
			if finale == null or not is_instance_valid(finale):
				finale = load(Story.MOD_DIR + "boss/finale.gd").new()
				finale.name = "Finale"
				finale.puppet = true
				layer.add_child(finale)
				finale.setup()
				health.visible = false
			if finale.step == "breath":
				music.hush()
				# This keeper took the dome's weapon: tell the host.
				var now: float = Time.get_ticks_msec() / 1000.0
				if finale.activity() == "battle" and now - _battle_told > 0.5:
					_battle_told = now
					rpc_id(1, "_net_battle")
			else:
				music.finale()
		_:
			_held.clear()


# A client's view of the chamber. Rock broken in real play is revealed on
# every peer, but a chamber the host opened alone (the dev command, a
# playtest) is still dark here.
func _reveal_chamber() -> void:
	var ch: Rect2i = _chamber()
	var cells: Array = []
	for y in range(ch.position.y - 1, ch.end.y + 1):
		for x in range(ch.position.x - 1, ch.end.x + 1):
			cells.append(Vector2(x, y))
	Level.map.tileCoordsToReveal.append_array(cells)
	Level.map.floodRevealTiles()


# Dev command (editor only): `-- --story --boss` drops the keeper into Velle's
# chamber; `--boss=chase` starts at the chase (Velle already dead),
# `--boss=finale` at the surface battle. The first two drill a winding shaft
# from the chamber up to the dome, the keeper's way home in the chase. All three start with the gear a keeper has by then
# (dev/boss_dev.gd): Heat Shielding IV, the Suit Blaster, all of the drill and
# the jetpack, Laser IV.
func _dev_boss(what: String) -> void:
	ModLoaderLog.info("Dev command: boss (%s)" % what, Story.LOG)
	if not _ensure_layer():
		return
	var dev = load(Story.MOD_DIR + "dev/boss_dev.gd")
	var keeper = _Story.local_keeper()
	# Every keeper's gear, Heat Shielding IV included (#265: per keeper).
	var gear: Array = dev.give_gear()
	ModLoaderLog.info("Dev command: gear " + ", ".join(PackedStringArray(gear)), Story.LOG)
	if what == "finale":
		_stop_waves()
		health.refill()
		_set_state("finale")
		_start_finale()
		return
	var ch: Rect2i = _chamber()
	var cells: Array = []
	for y in range(ch.position.y - 3, ch.end.y + 2):
		for x in range(ch.position.x - 2, ch.end.x + 2):
			cells.append(Vector2i(x, y))
	Level.map.tileCoordsToReveal.append_array(cells)
	Level.map.floodRevealTiles()
	var played: Array = Array(str(Data.ofOr("team1.story.beatsplayed", "")).split(",", false))
	if not played.has("boss_chamber"):
		played.append("boss_chamber")
		Data.apply("team1.story.beatsplayed", ",".join(PackedStringArray(played)))
	Data.apply(Awakening.AWAKE, true)
	var start: Vector2i = ch.position + Vector2i(3, 2)
	# The way home: an open shaft, as the keeper would have drilled it. Dug for
	# the fight too (#176), or the chase after it could not be finished.
	dev_path = dev.path_cells(ch, int(Level.levelSeed), dev.pool_cells())
	dev.carve(dev_path)
	if what == "chase":
		start = Vector2i(dev_path[0].x, ch.position.y + 2)
	keeper.teleport(Level.map.getTilePos(Vector2(start)))
	var cam = Level.viewports.getPlayerCam(keeper.playerId) if Level.viewports != null else null
	if cam != null:
		cam.position = keeper.position
	if what == "chase":
		_stop_waves()
		health.refill()
		_set_state("chase")
		_start_chase(arena.get_center() + Vector2(0, 80))
	# Tiles far from the keeper are made late, and some come back (a tile
	# that was mid-reveal when it was cleared): keep the shaft swept until
	# the keeper is home.
	while current() in ["", "fight", "chase"] and is_inside_tree():
		for f in 12:
			await get_tree().physics_frame
		dev.carve_leftovers(dev_path)
