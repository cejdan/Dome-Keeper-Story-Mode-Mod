extends "res://content/keeper/keeper4/Tentacle.gd"

# The grip fix for moving bodies (#364, from the #359 test room): one of the
# Beastmaster's claws on a body that moves (the ocean's tentacles,
# map/tentacle_rig.gd, which carry GRIP_META) holds its spot on that body.
# Vanilla stores a fixed world point (attachmentPoint, and arc_end while the
# claw is still reaching), so a claw on a moving segment hung in the air where
# the segment had been; a claw still reaching for one landed in mid-air.
# Here the point is kept in the body's own space from attach_to on and moved
# with the body every physics frame, reaching or planted. A fast swing then
# overstretches the arm and vanilla tears it loose, as it would on rock.
# The Beastmaster's body rides along with its claws (Keeper4.gd extension).
# Claws on tiles are untouched.

const GRIP_META := "story_moving_grip"

var _story_body = null             # the moving body this claw holds or reaches for
var _story_local := Vector2.ZERO   # the grip point in its space
var _story_normal := Vector2.ZERO  # the surface normal in its space


func attach_to(tile, point: Vector2, start_pos: Vector2, normal: Vector2 = Vector2.ZERO):
	super(tile, point, start_pos, normal)
	_story_body = null
	if tile is Node2D and is_instance_valid(tile) and tile.has_meta(GRIP_META):
		var inv: Transform2D = tile.global_transform.affine_inverse()
		_story_body = tile
		_story_local = inv * point
		_story_normal = inv.basis_xform(normal)


# Moves the grip with its body. Returns how far a planted claw moved this
# frame (zero for one still reaching, one on rock, or none). Called first
# thing in the keeper's physics frame (Keeper4.gd extension) and again here;
# the second call finds nothing left to move.
func story_follow() -> Vector2:
	if _story_body == null:
		return Vector2.ZERO
	if not is_instance_valid(_story_body) or attachedTile != _story_body or is_mining:
		_story_body = null
		return Vector2.ZERO
	var xf: Transform2D = _story_body.global_transform
	var p: Vector2 = xf * _story_local
	var shift: Vector2 = p - attachmentPoint
	if shift == Vector2.ZERO:
		return Vector2.ZERO
	attachmentPoint = p
	arc_end = p
	if _story_normal != Vector2.ZERO:
		attachedNormal = xf.basis_xform(_story_normal).normalized()
	return shift if is_grounded() else Vector2.ZERO


func _physics_process(delta):
	story_follow()
	super(delta)
