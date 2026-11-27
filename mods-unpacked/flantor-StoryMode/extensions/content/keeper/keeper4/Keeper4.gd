extends "res://content/keeper/keeper4/Keeper4.gd"

# The Beastmaster rides a moving body it holds (#364, from the #359 test room):
# before the keeper moves, each claw on a moving body (the ocean's tentacles)
# is moved with it (Tentacle.gd extension, story_follow), and the body moves by
# the claws' average shift, a claw on rock counting as a still one. Vanilla
# never pulls the body toward its claws (while a claw is planted it just
# hangs, with no gravity), so without this it floated where it was while the
# tentacle moved away. Nothing changes for claws on tiles.


func _physics_process(delta):
	_story_ride()
	super(delta)


func _story_ride() -> void:
	var tents = get_node_or_null("Tentacles")
	if tents == null or not ("tentacles" in tents):
		return
	var shift := Vector2.ZERO
	var planted: int = 0
	for t in tents.tentacles:
		if not is_instance_valid(t) or not t.has_method("story_follow"):
			continue
		var s: Vector2 = t.story_follow()
		if t.is_grounded():
			planted += 1
			shift += s
	if planted == 0 or shift == Vector2.ZERO:
		return
	if isInsideStation or disabled or externallyMoved or GameWorld.paused:
		return
	move_and_collide(shift / float(planted))
