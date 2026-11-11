extends "res://content/map/tile/DirtParticle.gd"

# Tile-break debris in a Story Mode mineral's colours (and grey for Story Mode
# iron). Everything else is vanilla.

const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")
const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")


func _ready():
	var tex: Texture2D = Metal.particle() if Metal.is_metal(type) else Minerals.particle_for_type(type)
	if tex == null:
		super._ready()
		return
	# Vanilla tints about a third of the debris with the resource's colours.
	var tint: bool = randf() > 0.7
	type = "default"
	super._ready()
	if tint:
		var sprite = $Sprite2D
		sprite.texture = tex
		Style.init(sprite)
