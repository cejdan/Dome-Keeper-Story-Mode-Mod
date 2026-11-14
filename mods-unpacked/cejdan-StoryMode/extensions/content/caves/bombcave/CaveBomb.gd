extends "res://content/caves/bombcave/CaveBomb.gd"

# A cave bomb going off tells the boss (#160): old mining charges are how the
# keeper hurts Velle. The explosion itself is vanilla.
#
# Vanilla bombs go off the instant they move without being carried. The
# charges Velle's chamber shakes loose fall from the roof, so they carry the
# "story_calm" meta: they lie still until the keeper first picks them up, and
# behave like any cave bomb from then on.

const CALM := "story_calm"


func server_process(delta: float) -> void:
	if has_meta(CALM) and not activated and not isCarried():
		return
	super(delta)


func onCarried(keeper: Keeper):
	if has_meta(CALM):
		remove_meta(CALM)
	if freeze:
		freeze = false
	super(keeper)


# In Velle's chamber a dropped charge clamps on where the keeper lets go of
# it, in mid-air, so it can be set beside an eye stalk instead of falling to
# the floor while its fuse burns.
func onDropped(keeper_or_kunaicarrier):
	super(keeper_or_kunaicarrier)
	if str(Data.ofOr("team1.story.boss", "")) == "fight":
		freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		set_deferred("freeze", true)


func explode():
	if not exploded:
		load("res://mods-unpacked/cejdan-StoryMode/boss/boss_director.gd").explosion_at(global_position, "bomb")
	super()
