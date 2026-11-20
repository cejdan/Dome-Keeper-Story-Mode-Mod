extends "res://content/gadgets/minedriller/TileToucher.gd"

# Metal Bit (#147): while this drill head (the Mine Driller's main drill and
# its side drills) runs its physics step, its tile hits name the upgrade that
# lets them through metal (data/metal.gd gadget_hit). Vanilla modes never own
# the upgrade, so their drills behave as before.

const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")


func _physics_process(delta):
	Metal.gadget_hit = teamId + "." + Metal.DRILL_UPGRADE
	super(delta)
	Metal.gadget_hit = ""
