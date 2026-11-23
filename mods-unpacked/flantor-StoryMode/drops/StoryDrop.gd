extends "res://content/drop/Drop.gd"

# A Story Mode mineral piece. One scene per mineral (drops/<mineral>_drop.tscn)
# sets `type`; the sprite comes from the mineral art by that type. The dome
# takes it as iron (drops/delivery.gd, StoryDropTrigger.gd). The scenes
# are vanilla IronDrop.tscn's twins on MineralDrop.tscn, so each also carries
# IronDrop's PhysicsMaterial (friction 0.2, bounce 0.15): MineralDrop's own is
# 0.6 / 0.25, which made every Story piece drag and slide like it was glued to
# the rock (#314, t314_drop_drag).

const Assets = preload("res://mods-unpacked/flantor-StoryMode/util/assets.gd")
static var _Assets = Assets  # calls go through this: lazy_preload makes const-preload calls slow
const Delivery = preload("res://mods-unpacked/flantor-StoryMode/drops/delivery.gd")
static var _Delivery = Delivery  # calls go through this: lazy_preload makes const-preload calls slow


func _ready():
	var tex: Texture2D = _Assets.tex("res://mods-unpacked/flantor-StoryMode/art/minerals/drop_%s.png" % type)
	if tex != null:
		$Sprite2D.texture = tex
	var trigger: Node = get_node_or_null("DropEnterTrigger")
	if trigger != null:
		trigger.set_script(load("res://mods-unpacked/flantor-StoryMode/drops/StoryDropTrigger.gd"))
	super._ready()


# Vanilla's stuck check misses a drop wedged against a frozen body (#327).
func processIndependantStuckResolver(delta):
	_Delivery.resolve_stuck(self, delta)
