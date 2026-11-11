extends "res://content/map/tile/Tile.gd"

# Story Mode mineral tiles: drillable, drawn from the mineral's own ore sheet,
# with the mineral's extra health. Vanilla tile types run vanilla code only.

const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")
const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")


func setType(type: String):
	var fresh: bool = health == 0
	super(type)
	if type == Metal.TYPE:
		_set_metal(fresh)
		return
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


# Metal: a full steel plate over the rock. It counts as destructable so blasts
# reach it, but only a Suit Blaster blast is let through (see hit()).
func _set_metal(fresh: bool) -> void:
	set_meta("destructable", true)
	if res_sprite:
		var rng: = RandomNumberGenerator.new()
		rng.seed = Level.levelSeed + hash(coord)
		res_sprite.texture = Metal.sheet()
		res_sprite.show()
		initResourceSprite(Vector2(rng.randi_range(0, 4), 5))
	var baseHealth: float = Data.of("map.tileBaseHealth") + Metal.EXTRA_HEALTH
	var mult: float = hardnessMultiplier * pow(Data.of("map.tileHealthMultiplierPerLayer"), layer)
	max_health = max(1, round(mult * baseHealth))
	if fresh:
		health = max_health
	else:
		health = min(health, max_health)


func _metal_refuses() -> bool:
	if type != Metal.TYPE:
		return false
	if exploded and Metal.suit_blast_covers(coord):
		return false
	exploded = false
	return true


func hit(dir: Vector2, dmg: float, teamId: String = "", keeperTechId: String = ""):
	if _metal_refuses():
		_clank()
		return
	super(dir, dmg, teamId, keeperTechId)


func remote_hit(dir: Vector2, dmg: float, teamId: String, keeperTechId: String = ""):
	if _metal_refuses():
		return
	super(dir, dmg, teamId, keeperTechId)


# A drill on metal: a brief flash on the plate, no damage.
func _clank() -> void:
	if res_sprite == null:
		return
	if hitTween:
		hitTween.kill()
	hitTween = create_tween()
	hitTween.tween_property(res_sprite, "modulate", Color.WHITE, 0.15).from(Color(1.6, 1.6, 1.6, 1.0))
