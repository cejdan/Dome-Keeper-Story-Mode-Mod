extends "res://content/gadgets/drillbot/Drillbot.gd"

# Metal Bit (#147): while Drillbert runs its physics step, its tile hits name
# the upgrade that lets them through metal (data/metal.gd gadget_hit). Vanilla
# modes never own the upgrade, so Drillbert behaves as before.

const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")


func _physics_process(delta):
	Metal.gadget_hit = teamId + "." + Metal.DRILLBOT_UPGRADE
	super(delta)
	Metal.gadget_hit = ""
