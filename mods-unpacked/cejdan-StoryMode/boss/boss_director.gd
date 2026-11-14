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
# monster waves stop: the monsters are watching.
#
# Other code reaches it through the static helpers, which do nothing outside
# the boss sequence:
#   Director.explosion_at(global_pos, kind, radius_px)   kind: bomb, mine, blast
#   Director.jams_recall()                               lava_field asks before a recall
#   Director.overheated()

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const Boss = preload("res://mods-unpacked/cejdan-StoryMode/data/boss.gd")
const Awakening = preload("res://mods-unpacked/cejdan-StoryMode/beats/awakening.gd")
const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const Sfx = preload("res://mods-unpacked/cejdan-StoryMode/boss/sfx.gd")

const GROUP := "story-boss"
const STATE := "team1.story.boss"
const TILE := 24.0

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
var _cam_blend: float = 0.0


static func instance():
	var tree = Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return null
	return tree.get_first_node_in_group(GROUP)


static func current() -> String:
	return str(Data.ofOr(STATE, ""))


static func active() -> bool:
	return current() in ["fight", "chase", "finale"]


static func jams_recall() -> bool:
	return instance() != null and active()


# The suit overheated during the boss sequence: a heart, not a recall.
static func overheated() -> void:
	var n = instance()
	if n == null or n.health == null:
		return
	var k = Keepers.first()
	if k != null:
		n.health.invulnerable = 0.0
		n.health.hurt(n.health.to_local(k.global_position) + Vector2(0, 10), "overheat")


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
	ModLoaderLog.info("Boss: " + (s if s != "" else "(reset)"), Story.LOG)
	state_changed.emit(s)


func _ready_to_run() -> bool:
	if not enabled or not multiplayer.is_server() or not Story.is_story():
		return false
	var stage = Level.stage
	if stage == null or not (stage is LevelStage) or not stage.keeperInputStarted:
		return false
	if Level.map == null or not is_instance_valid(Level.map) or not Level.map.isMapReady():
		return false
	if SaveGame.currentLoadingSavegame or Keepers.first() == null:
		return false
	return true


func _chamber() -> Rect2i:
	var ch = Level.map.tileData.get_meta("story_boss_chamber", null)
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
	return true


func _physics_process(delta: float) -> void:
	if not _ready_to_run() or GameWorld.paused:
		return
	if GameWorld.won or GameWorld.lost:
		return
	if not _booted:
		_booted = true
		_resume()
	var keeper = Keepers.first()
	match current():
		"":
			if not Awakening.is_awake() or StoryBeats.is_open() or not StoryBeats.has_played("boss_chamber"):
				return
			if not _ensure_layer():
				return
			var kp: Vector2 = layer.to_local(keeper.global_position)
			if arena.grow(-4.0).has_point(kp) and not keeper.disabled:
				_start_fight()
		"fight":
			_seal(keeper, delta)
			_recharge_blaster(keeper, delta)
			if velle != null and is_instance_valid(velle):
				music.fight(velle.phase)
		"chase":
			if chase != null and is_instance_valid(chase):
				music.chase(1.0 - chase.gap / 260.0)
			if keeper.isInsideDome:
				_chase_done()
		"finale":
			music.finale()


func _process(delta: float) -> void:
	# The camera holds the whole chamber during the fight.
	var keeper = Keepers.first()
	if keeper == null or Level.viewports == null or layer == null or not is_instance_valid(layer):
		return
	var cam = Level.viewports.getPlayerCam(keeper.playerId)
	if cam == null or not ("targetOffset" in cam):
		return
	var want: float = 1.0 if current() == "fight" else 0.0
	if _cam_blend == want and want == 0.0:
		return
	_cam_blend = move_toward(_cam_blend, want, delta * 1.5)
	var centre: Vector2 = layer.to_global(arena.get_center() + Vector2(0, -10))
	cam.targetOffset = (centre - keeper.global_position) * _cam_blend


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
				var k = Keepers.first()
				_start_chase(layer.to_local(k.global_position) + Vector2(0, 220))
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
	velle.setup(arena, health)
	velle.defeated.connect(_velle_defeated)
	_seal_flash = 1.0
	Sfx.play("seal", -4.0, 0.7)
	Sfx.play("roar", -3.0, 0.7)
	InputSystem.shake(20.0, 1.2, 14.0)


func _stop_waves() -> void:
	for mm in get_tree().get_nodes_in_group("monster-manager"):
		mm.disabled = true
		if mm.has_method("instantlyKillWave"):
			mm.instantlyKillWave()


# Nobody leaves: the keeper is held inside the chamber.
func _seal(keeper, delta: float) -> void:
	_seal_flash = maxf(0.0, _seal_flash - delta)
	var inner: Rect2 = arena.grow(-6.0)
	var kp: Vector2 = layer.to_local(keeper.global_position)
	if inner.has_point(kp):
		return
	var held := Vector2(clampf(kp.x, inner.position.x, inner.end.x), clampf(kp.y, inner.position.y, inner.end.y))
	keeper.global_position = layer.to_global(held)
	if "move" in keeper:
		keeper.move = Vector2.ZERO
	if _seal_flash <= 0.0:
		_seal_flash = 0.5
		Sfx.play("clang", -10.0, 0.8)


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
	_set_state("chase")
	_start_chase(velle.eye_pos())


# ---------------------------------------------------------------- the chase

func _start_chase(origin: Vector2) -> void:
	chase = load(Story.MOD_DIR + "boss/chase.gd").new()
	chase.name = "Chase"
	layer.add_child(chase)
	chase.setup(health, origin)
	Sfx.play("roar", -2.0, 1.2)
	InputSystem.shake(18.0, 1.0, 18.0)


# The keeper made it into the dome.
func _chase_done() -> void:
	if chase != null and is_instance_valid(chase):
		chase.running = false
	_set_state("finale")
	_start_finale()


# ---------------------------------------------------------------- the finale

func _start_finale() -> void:
	finale = load(Story.MOD_DIR + "boss/finale.gd").new()
	finale.name = "Finale"
	layer.add_child(finale)
	finale.setup()
	finale.finished.connect(_finale_done)


func _finale_done() -> void:
	if current() != "finale":
		return
	_set_state("won")
	_finish_won()


# The dome fell in the finale (the game mode's own loss): the lost ending.
func dome_lost() -> void:
	if active():
		_set_state("lost")
		music.stop()


func _finish_won() -> void:
	music.stop()
	await get_tree().create_timer(1.0, false).timeout
	if Level.mode != null and Level.mode.has_method("horror_defeated"):
		Level.mode.horror_defeated()


func _keeper_died(cause: String) -> void:
	if not active():
		return
	_set_state("lost")
	music.stop()
	ModLoaderLog.info("Boss: the keeper is dead (%s)" % cause, Story.LOG)
	var keeper = Keepers.first()
	if keeper != null and is_instance_valid(keeper):
		Sfx.play("keeper_down", 0.0, 0.7)
		keeper.visible = false
	if velle != null and is_instance_valid(velle):
		velle.attack_enabled = false
		velle.spawn_bombs = false
		velle.orbs.clear()
		velle.attacks.clear()
	if Level.mode != null and Level.mode.has_method("keeper_lost"):
		Level.mode.keeper_lost()
