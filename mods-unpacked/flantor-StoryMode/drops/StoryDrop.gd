extends "res://content/drop/Drop.gd"

# A Story Mode mineral piece. One scene per mineral (drops/<mineral>_drop.tscn)
# sets `type`; the sprite comes from the mineral art by that type.

const Assets = preload("res://mods-unpacked/flantor-StoryMode/util/assets.gd")


func _ready():
	var tex: Texture2D = Assets.tex("res://mods-unpacked/flantor-StoryMode/art/minerals/drop_%s.png" % type)
	if tex != null:
		$Sprite2D.texture = tex
	var trigger: Node = get_node_or_null("DropEnterTrigger")
	if trigger != null:
		trigger.set_script(load("res://mods-unpacked/flantor-StoryMode/drops/StoryDropTrigger.gd"))
	super._ready()
