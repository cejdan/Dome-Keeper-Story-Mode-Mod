extends "res://content/map/chamber/gadget/GadgetChamber.gd"

# A translator chamber (#93): vanilla's gadget chamber holding a translator
# instead of a gadget. Placed by map/story_gen.gd (place_translators) as a 2x2
# of the gadget tile id in B2, B4 and B6; the Map extension hands this scene
# out for that id in Story Mode. Using it gives the keeper the translator,
# already carried.

const Assets = preload("res://mods-unpacked/cejdan-StoryMode/util/assets.gd")


func _ready():
	super._ready()
	var tex: Texture2D = Assets.tex("res://mods-unpacked/cejdan-StoryMode/art/items/translator.png")
	if tex != null:
		$SocketedGizmo.texture = tex
	# A faint red pulse inside the open chamber: the rune-eye, waiting.
	$SocketedGizmo.modulate = Color(1.0, 0.92, 0.92)
