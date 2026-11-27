extends "res://content/map/tile/Tile.gd"

# Story Mode mineral tiles: drillable, drawn from the mineral's own ore sheet,
# with the mineral's extra health. Vanilla tile types run vanilla code only.

const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
static var _Minerals = Minerals  # calls go through this: lazy_preload makes const-preload calls slow
const Metal = preload("res://mods-unpacked/flantor-StoryMode/data/metal.gd")
static var _Metal = Metal  # calls go through this: lazy_preload makes const-preload calls slow
const Bones = preload("res://mods-unpacked/flantor-StoryMode/data/bones.gd")
static var _Bones = Bones  # calls go through this: lazy_preload makes const-preload calls slow
const AnchorData = preload("res://mods-unpacked/flantor-StoryMode/data/anchors.gd")
const ChainAnchors = preload("res://mods-unpacked/flantor-StoryMode/map/chain_anchors.gd")
static var _ChainAnchors = ChainAnchors  # calls go through this: lazy_preload makes const-preload calls slow


func setType(type: String):
	var fresh: bool = health == 0
	super(type)
	if type == "dirt" and _is_chamber_crust():
		# The ocean floor right over the boss chamber is a thin crust (#43): base
		# health, no depth multiplier, so diving in is a heat test, not a drill test.
		max_health = max(1, round(hardnessMultiplier * Data.of("map.tileBaseHealth")))
		health = max_health if fresh else min(health, max_health)
		return
	if _Metal.is_metal(type):
		_set_metal(fresh)
		return
	if type == Bones.TYPE:
		_set_bones(fresh)
		return
	if type == AnchorData.TYPE:
		_set_anchor(fresh)
		return
	var sheet: Texture2D = _Minerals.sheet_for_type(type)
	if sheet == null:
		return
	if res_sprite:
		var rng: = RandomNumberGenerator.new()
		rng.seed = Level.levelSeed + hash(coord)
		res_sprite.texture = sheet
		res_sprite.show()
		initResourceSprite(Vector2(rng.randi_range(0, 4), 5))
	if not _Minerals.is_mod_mineral(type):
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
		res_sprite.texture = _Metal.sheet()
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
	if not _Metal.is_metal(type):
		return false
	if exploded and _Metal.suit_blast_covers(coord):
		return false
	# A Mine Driller or Drillbert with its Metal Bit (#147).
	if not exploded and _Metal.gadget_may_break():
		return false
	exploded = false
	return true


func hit(dir: Vector2, dmg: float, teamId: String = "", keeperTechId: String = ""):
	if _metal_refuses():
		_clank()
		return
	var before: float = health
	super(dir, dmg, teamId, keeperTechId)
	if type == AnchorData.TYPE:
		_anchor_share(dir, before - health, teamId, keeperTechId)


func remote_hit(dir: Vector2, dmg: float, teamId: String, keeperTechId: String = ""):
	if _metal_refuses():
		return
	var before: float = health
	super(dir, dmg, teamId, keeperTechId)
	if type == AnchorData.TYPE:
		_anchor_share(dir, before - health, teamId, keeperTechId)


# A chain anchor (#365): its four tiles share every hit, so the stone breaks
# as one whichever tile is struck. Each peer applies the shared damage itself
# (vanilla sends every peer the struck tile's hit), so no extra message.
static var _sharing := false


func _anchor_share(dir: Vector2, done: float, teamId: String, keeperTechId: String) -> void:
	if _sharing or done <= 0.0:
		return
	_sharing = true
	_ChainAnchors.tile_hit(Vector2i(coord), done, relativeHealth())
	for c: Vector2i in _ChainAnchors.siblings(Vector2i(coord)):
		var t = Level.map.tiles.get(Vector2(c)) if Level.map != null else null
		# A blow that would finish a sibling leaves it to the anchor's break,
		# which clears the stone's other tiles (map/chain_anchors.gd).
		if t != null and is_instance_valid(t) and t.health > done:
			t.remote_hit(dir, done, teamId, keeperTechId)
	_sharing = false


# A chain anchor's tile (#365): drillable rock, tougher than plain rock at
# its depth; map/chain_anchors.gd draws the round stone over it.
func _set_anchor(fresh: bool) -> void:
	set_meta("destructable", true)
	if res_sprite:
		res_sprite.hide()
	var baseHealth: float = Data.of("map.tileBaseHealth") + AnchorData.EXTRA_HEALTH
	var mult: float = hardnessMultiplier * pow(Data.of("map.tileHealthMultiplierPerLayer"), layer)
	max_health = max(1, round(mult * baseHealth))
	health = max_health if fresh else min(health, max_health)


# A drill on metal: a brief flash on the plate, no damage.
func _clank() -> void:
	if res_sprite == null:
		return
	if hitTween:
		hitTween.kill()
	hitTween = create_tween()
	hitTween.tween_property(res_sprite, "modulate", Color.WHITE, 0.15).from(Color(1.6, 1.6, 1.6, 1.0))


# The chamber's rect, cached per map (tiles are made one at a time as they're revealed).
static var _crust_map_id := 0
static var _crust_rect := Rect2i()


func _is_chamber_crust() -> bool:
	if Level.map == null or not is_instance_valid(Level.map) or Level.map.tileData == null:
		return false
	var td = Level.map.tileData
	if td.get_instance_id() != _crust_map_id:
		var ch = td.get_meta("story_boss_chamber") if td.has_meta("story_boss_chamber") else null
		_crust_rect = ch if ch is Rect2i else Rect2i()
		# A client gets the chamber from the host a moment after its map (#225):
		# cache only a found chamber.
		if ch is Rect2i:
			_crust_map_id = td.get_instance_id()
	if _crust_rect.size == Vector2i.ZERO or int(coord.y) != _crust_rect.position.y - 1:
		return false
	return int(coord.x) >= _crust_rect.position.x and int(coord.x) < _crust_rect.end.x


# Miner bones (#94): a miner's remains half-buried in the rock, drilled out
# like an ore tile.
func _set_bones(fresh: bool) -> void:
	set_meta("destructable", true)
	if res_sprite:
		var rng: = RandomNumberGenerator.new()
		rng.seed = Level.levelSeed + hash(coord)
		res_sprite.texture = _Bones.sheet()
		res_sprite.show()
		initResourceSprite(Vector2(rng.randi_range(0, 4), 5))
	var baseHealth: float = Data.of("map.tileBaseHealth") + Bones.EXTRA_HEALTH
	var mult: float = hardnessMultiplier * pow(Data.of("map.tileHealthMultiplierPerLayer"), layer)
	max_health = max(1, round(mult * baseHealth))
	health = max_health if fresh else min(health, max_health)
