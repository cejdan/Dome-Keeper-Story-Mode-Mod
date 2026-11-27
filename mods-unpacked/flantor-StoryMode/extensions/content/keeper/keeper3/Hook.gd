extends "res://content/keeper/keeper3/Hook.gd"

# The Infiltrator's hook holds its spot on a moving body (#364, from the #359
# test room). Vanilla freezes the hook where it hit (connectHook) and only
# remembers the body to let go when it is destroyed, so a hook in a moving
# tentacle segment (map/tentacle_rig.gd, which carries GRIP_META) stayed in
# the air with the rope hanging from it. Here the hook keeps its place and
# turn in the body's space and moves with it every physics frame, before the
# keeper (its rope pulls toward the hook) moves. Hooks in tiles are untouched.

const GRIP_META := "story_moving_grip"

var _story_body = null
var _story_local := Transform2D.IDENTITY


func connectHook(impact_normal: Vector2 = Vector2.ZERO, impact_collider: Object = null) -> void:
	var was_hit: bool = has_hit
	super(impact_normal, impact_collider)
	if was_hit or not has_hit:
		return
	if impact_collider is Node2D and is_instance_valid(impact_collider) and impact_collider.has_meta(GRIP_META):
		_story_body = impact_collider
		_story_local = impact_collider.global_transform.affine_inverse() * global_transform
		# After the moving bodies (-10), before the keepers (0).
		process_physics_priority = -5


func story_follow() -> void:
	if _story_body == null:
		return
	if not is_instance_valid(_story_body) or not has_hit or attached_target != _story_body:
		_story_body = null
		return
	global_transform = _story_body.global_transform * _story_local


func _physics_process(delta: float) -> void:
	story_follow()
	super(delta)
