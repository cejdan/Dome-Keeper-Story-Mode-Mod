extends Node2D

# Keeper health for the boss sequence (#160): hearts drawn above the keeper,
# apart from the heat bar. A hit costs a heart, throws the keeper back, shakes
# and flashes the screen, and leaves the keeper safe for a moment. At zero the
# `died` signal fires once. Hearts live in Data, so a save keeps them.
#
# With a team (#230) the hearts are one pool for all keepers (KEY; the user has
# yet to decide between this and hearts per keeper): a hit on any keeper costs
# one. Only the host takes hearts. What a hit does to the keeper itself (the
# throw, the shake, the red flash) happens on that keeper's own instance:
# `hit` tells the director, which sends it on, and a client plays it with
# net_hit(). Each keeper has its own safe moment after a hit.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const Boss = preload("res://mods-unpacked/flantor-StoryMode/data/boss.gd")
const Pix = preload("res://mods-unpacked/flantor-StoryMode/boss/pix.gd")
static var _Pix = Pix  # calls go through this: lazy_preload makes const-preload calls slow

const KEY := "team1.story.hearts"

signal hurt_taken(hearts_left: int, cause: String)
signal died(cause: String)
signal hit(keeper, push: Vector2)   # host: a keeper was hit, for its own instance to play

var _safe: Dictionary = {}      # playerId -> seconds that keeper is still safe
# This instance's first keeper's (playtests set it).
var invulnerable: float:
	get:
		return float(_safe.get(_Story.local_pid(), 0.0))
	set(v):
		_safe[_Story.local_pid()] = v
var _pushes: Dictionary = {}    # playerId -> [push, seconds left]
var dead: bool = false
var hits: int = 0
var _time: float = 0.0
var _lost_flash: float = 0.0
var _gain_flash: float = 0.0
var _flash: ColorRect = null
var _layer: CanvasLayer = null
# Splitscreen (#231): a red wash per local keeper, in that keeper's view.
var _flashes: Dictionary = {}   # playerId -> ColorRect


func _ready() -> void:
	z_index = 9
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not Data.has(KEY) and multiplayer.is_server():
		Data.apply(KEY, Boss.HEARTS)
	# A red wash over the whole screen on a hit.
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	_flash = ColorRect.new()
	_flash.color = Color(1.0, 0.1, 0.12, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_flash)


# The red wash for `keeper`'s view: the one above with one local keeper; with
# several, each keeper's own: a rect in the world over that keeper's camera,
# drawn in its split view only (a CanvasLayer can't be pointed at a split view
# safely: custom_viewport errors when the level is freed).
func _flash_for(keeper) -> ColorRect:
	if Keepers.local.getCount() <= 1 or Level.viewports == null:
		return _flash
	if _flashes.has(keeper.playerId) and is_instance_valid(_flashes[keeper.playerId]):
		return _flashes[keeper.playerId]
	var f := ColorRect.new()
	f.color = Color(1.0, 0.1, 0.12, 0.0)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.z_as_relative = false
	f.z_index = 200
	add_child(f)
	f.visibility_layer = 0
	Level.viewports.showForLocalKeeper(keeper, f)
	_flashes[keeper.playerId] = f
	return f


func _place_flashes() -> void:
	for pid in _flashes:
		var f = _flashes[pid]
		var r: Rect2 = _Story.view_rect(pid, 8.0)
		if is_instance_valid(f) and r.has_area():
			f.position = to_local(r.position)
			f.size = r.size


func hearts() -> int:
	return int(Data.ofOr(KEY, Boss.HEARTS))


func refill() -> void:
	Data.apply(KEY, Boss.HEARTS)
	dead = false


# Up to `n` hearts back at once. Returns how many were added.
func give(n: int) -> int:
	if dead:
		return 0
	var add: int = clampi(n, 0, Boss.HEARTS - hearts())
	if add > 0:
		Data.apply(KEY, hearts() + add)
		_gain_flash = 0.9
	return add


# One heart back. False when already full (or dead).
func heal() -> bool:
	if dead or hearts() >= Boss.HEARTS:
		return false
	Data.apply(KEY, hearts() + 1)
	_gain_flash = 0.6
	return true


func safe_left(keeper) -> float:
	return float(_safe.get(keeper.playerId, 0.0))


func set_safe(keeper, sec: float) -> void:
	_safe[keeper.playerId] = sec


# One heart of damage to `keeper` (this instance's own when left out) from
# something at `from` (this node's space). False when that keeper is still
# safe from its last hit, or the team is already dead. The host's to call.
func hurt(from: Vector2, cause: String = "", keeper = null) -> bool:
	if keeper == null:
		keeper = _Story.local_keeper()
	if dead or keeper == null or not is_instance_valid(keeper) or not multiplayer.is_server() or safe_left(keeper) > 0.0:
		return false
	var left: int = maxi(0, hearts() - 1)
	Data.apply(KEY, left)
	hits += 1
	var kp: Vector2 = to_local(keeper.global_position)
	var dir: Vector2 = (kp - from).normalized() if kp.distance_to(from) > 0.5 else Vector2.UP
	_play_hit(keeper, dir * Boss.HURT_KNOCKBACK)
	hit.emit(keeper, dir * Boss.HURT_KNOCKBACK)
	ModLoaderLog.info("Keeper hit (%s): %d hearts left" % [cause, left], "flantor-StoryMode")
	hurt_taken.emit(left, cause)
	if left <= 0:
		dead = true
		died.emit(cause)
	return true


# A client: the host says the keeper `player_id` was hit.
func net_hit(player_id: String, push: Vector2) -> void:
	var keeper = Keepers.getKeeper(player_id) if Keepers.hasKeeper(player_id) else null
	if keeper != null and is_instance_valid(keeper):
		_play_hit(keeper, push)


# The hit as this instance shows it: the keeper blinks; one of our own is
# thrown, with the shake and the red flash.
func _play_hit(keeper, push: Vector2) -> void:
	set_safe(keeper, Boss.HURT_INVULNERABLE)
	_lost_flash = 0.6
	if not Keepers.local.has(keeper):
		return
	_pushes[keeper.playerId] = [push, 0.16]
	if "move" in keeper:
		keeper.move = Vector2.ZERO
	InputSystem.shake(14.0, 0.35, 22.0)
	_flash_for(keeper).color.a = 0.34
	Audio.sound("gui_err")


func _physics_process(delta: float) -> void:
	if GameWorld.paused:
		return
	_time += delta
	for id: String in _safe:
		_safe[id] = maxf(0.0, float(_safe[id]) - delta)
	_lost_flash = maxf(0.0, _lost_flash - delta)
	_gain_flash = maxf(0.0, _gain_flash - delta)
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 0.9)
	for f in _flashes.values():
		if is_instance_valid(f):
			f.color.a = maxf(0.0, f.color.a - delta * 0.9)
	_place_flashes()
	for keeper in Keepers.getAll():
		if keeper == null or not is_instance_valid(keeper):
			continue
		var push: Array = _pushes.get(keeper.playerId, [])
		if not push.is_empty() and push[1] > 0.0:
			# The throw: a short shove through the keeper's own collision.
			push[1] -= delta
			if keeper.has_method("move_and_collide"):
				keeper.move_and_collide(push[0] * (delta / 0.16))
		# A keeper blinks while safe.
		var sprite = keeper.get("keeper_sprite")
		if sprite != null and is_instance_valid(sprite) and not keeper.disabled:
			sprite.modulate.a = 0.35 if (safe_left(keeper) > 0.0 and fposmod(_time * 12.0, 1.0) < 0.5) else 1.0
	queue_redraw()


func _draw() -> void:
	# The team's hearts over every local keeper (#231; one shared pool, #230).
	for keeper in Keepers.local.keepers:
		if keeper != null and is_instance_valid(keeper) and keeper.visible:
			_draw_hearts(keeper)


func _draw_hearts(keeper) -> void:
	var n: int = Boss.HEARTS
	var have: int = hearts()
	var w: float = n * 8.0 - 1.0
	var p: Vector2 = (to_local(keeper.global_position) + Vector2(-w * 0.5, -29)).round()
	for i in n:
		var full: bool = i < have
		var just_lost: bool = i == have and _lost_flash > 0.0
		var bob: float = 0.0
		if have == 1 and full:
			bob = round(sin(_time * 10.0))
		var just_won: bool = i == have - 1 and _gain_flash > 0.0
		_Pix.heart(self, p + Vector2(i * 8.0, bob), full, Color("ff3b4f"), (just_lost or just_won) and fposmod(_time * 14.0, 1.0) < 0.5)
