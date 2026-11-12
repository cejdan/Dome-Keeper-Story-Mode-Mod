extends "res://content/drop/Drop.gd"

# A translator (#93): the monsters' carved horn, carried home like a relic. Its
# trigger answers the dome's relic socket, which floats it in and shrinks it
# into team1.inventory.translator; Storymode.gd installs it from there.

const Assets = preload("res://mods-unpacked/cejdan-StoryMode/util/assets.gd")


func _ready():
	var tex: Texture2D = Assets.tex("res://mods-unpacked/cejdan-StoryMode/art/items/translator.png")
	if tex != null:
		$Sprite2D.texture = tex
	var trigger: Node = get_node_or_null("DropEnterTrigger")
	if trigger != null:
		trigger.set_script(load("res://mods-unpacked/cejdan-StoryMode/drops/TranslatorDropTrigger.gd"))
	super._ready()
