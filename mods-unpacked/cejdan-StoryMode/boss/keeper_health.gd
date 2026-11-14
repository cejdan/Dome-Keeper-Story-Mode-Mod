extends Node2D

# Keeper health for the boss sequence (#160): hearts drawn above the keeper,
# apart from the heat bar. A hit costs a heart, throws the keeper back, shakes
# and flashes the screen, and leaves the keeper safe for a moment. At zero the
# `died` signal fires once. Hearts live in Data, so a save keeps them.

const Boss = preload("res://mods-unpacked/cejdan-StoryMode/data/boss.gd")
const Pix = preload("res://mods-unpacked/cejdan-StoryMode/boss/pix.gd")

const KEY := "team1.story.hearts"

signal hurt_taken(hearts_left: int, cause: String)
signal died(cause: String)

var invulnerable: float = 0.0
var dead: bool = false
var hits: int = 0
var _time: float = 0.0
var _lost_flash: float = 0.0
var _push: Vector2 = Vector2.ZERO
var _push_t: float = 0.0
var _flash: ColorRect = null
var _layer: CanvasLayer = null


func _ready() -> void:
	z_index = 9
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not Data.has(KEY):
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


func hearts() -> int:
	return int(Data.ofOr(KEY, Boss.HEARTS))


func refill() -> void:
	Data.apply(KEY, Boss.HEARTS)
	dead = false


# One heart of damage from something at `from` (this node's space). False when
# the keeper is still safe from the last hit, or already dead.
func hurt(from: Vector2, cause: String = "") -> bool:
	var keeper = Keepers.first()
	if dead or invulnerable > 0.0 or keeper == null or not is_instance_valid(keeper):
		return false
	var left: int = maxi(0, hearts() - 1)
	Data.apply(KEY, left)
	hits += 1
	invulnerable = Boss.HURT_INVULNERABLE
	_lost_flash = 0.6
	var kp: Vector2 = to_local(keeper.global_position)
	var dir: Vector2 = (kp - from).normalized() if kp.distance_to(from) > 0.5 else Vector2.UP
	_push = dir * Boss.HURT_KNOCKBACK
	_push_t = 0.16
	if "move" in keeper:
		keeper.move = Vector2.ZERO
	InputSystem.shake(14.0, 0.35, 22.0)
	_flash.color.a = 0.34
	Audio.sound("gui_err")
	ModLoaderLog.info("Keeper hit (%s): %d hearts left" % [cause, left], "cejdan-StoryMode")
	hurt_taken.emit(left, cause)
	if left <= 0:
		dead = true
		died.emit(cause)
	return true


func _physics_process(delta: float) -> void:
	if GameWorld.paused:
		return
	_time += delta
	invulnerable = maxf(0.0, invulnerable - delta)
	_lost_flash = maxf(0.0, _lost_flash - delta)
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 0.9)
	var keeper = Keepers.first()
	if keeper == null or not is_instance_valid(keeper):
		return
	if _push_t > 0.0:
		# The throw: a short shove through the keeper's own collision.
		var step: Vector2 = _push * (delta / 0.16)
		_push_t -= delta
		if keeper.has_method("move_and_collide"):
			keeper.move_and_collide(step)
	# The keeper blinks while safe.
	var sprite = keeper.get("keeper_sprite")
	if sprite != null and is_instance_valid(sprite) and not keeper.disabled:
		sprite.modulate.a = 0.35 if (invulnerable > 0.0 and fposmod(_time * 12.0, 1.0) < 0.5) else 1.0
	queue_redraw()


func _draw() -> void:
	var keeper = Keepers.first()
	if keeper == null or not is_instance_valid(keeper) or not keeper.visible:
		return
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
		Pix.heart(self, p + Vector2(i * 8.0, bob), full, Color("ff3b4f"), just_lost and fposmod(_time * 14.0, 1.0) < 0.5)
