extends "res://content/map/tile/DirtParticle.gd"

# Tile-break debris in a Story Mode mineral's colours (and grey for Story Mode
# iron). Everything else is vanilla.

const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
static var _Minerals = Minerals  # calls go through this: lazy_preload makes const-preload calls slow
const Metal = preload("res://mods-unpacked/flantor-StoryMode/data/metal.gd")
static var _Metal = Metal  # calls go through this: lazy_preload makes const-preload calls slow


func _ready():
	var tex: Texture2D = _Metal.particle() if _Metal.is_metal(type) else _Minerals.particle_for_type(type)
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
