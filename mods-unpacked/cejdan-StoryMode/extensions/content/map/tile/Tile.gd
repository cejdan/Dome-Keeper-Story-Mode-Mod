extends "res://content/map/tile/Tile.gd"

# Story Mode mineral tiles: drillable, drawn from the mineral's own ore sheet,
# with the mineral's extra health. Vanilla tile types run vanilla code only.

const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")


func setType(type: String):
	var fresh: bool = health == 0
	super(type)
	var sheet: Texture2D = Minerals.sheet_for_type(type)
	if sheet == null:
		return
	if res_sprite:
		var rng: = RandomNumberGenerator.new()
		rng.seed = Level.levelSeed + hash(coord)
		res_sprite.texture = sheet
		res_sprite.show()
		initResourceSprite(Vector2(rng.randi_range(0, 4), 5))
	if not Minerals.is_mod_mineral(type):
		return
	# Vanilla has no branch for this type: make it drillable and give it the
	# mineral's health bonus on top of the base, as vanilla does for iron.
	set_meta("destructable", true)
	var baseHealth: float = Data.of("map.tileBaseHealth") + float(Minerals.TABLE[type]["extra_health"])
	var mult: float = hardnessMultiplier * pow(Data.of("map.tileHealthMultiplierPerLayer"), layer)
	max_health = max(1, round(mult * baseHealth))
	if fresh:
		health = max_health
	else:
		health = min(health, max_health)
