extends RefCounted

# The metal tile: a riveted steel plate that drills cannot hurt and only a
# Suit Blaster blast breaks. Gates and the deep scattered clumps are made of it.
#
# Why a blast registry: every vanilla explosion (Suit Blaster, Blast Mining,
# bomb caves) breaks tiles through the same Map calls, with `tile.exploded`
# set and `max_health + 1` damage, and none of them says where it came from.
# So the Suit Blaster explosion records where and how far it reaches just
# before it goes off (extensions/.../SuitblasterExplosion.gd), and a metal tile
# accepts an exploded hit only when such a blast covers it.

const Assets = preload("res://mods-unpacked/cejdan-StoryMode/util/assets.gd")

const TYPE := "metal"
const TILE_ID := 48
# Gate tiles: metal that sits in a gate wall, with the same look and rules. Its
# own id only lets map reports tell the gate from scattered metal.
const GATE_TYPE := "metalgate"
const GATE_ID := 49
const SHEET := "res://mods-unpacked/cejdan-StoryMode/art/tiles/sheet_metal.png"
const PARTICLE := "res://mods-unpacked/cejdan-StoryMode/art/tiles/particle_metal.png"
# Extra tile health over the base (only matters for the damage shader; drills
# never get through and a blast always does).
const EXTRA_HEALTH := 20
# How long a recorded blast keeps counting, in ms. A directional blast walks
# one tile every 0.08 s, so even a long one is done well inside this.
const BLAST_TTL_MS := 6000

# Each: {"centre": Vector2, "radius": float, "dir": Vector2, "distance": int, "until": int}
static var _blasts: Array = []


static func register() -> void:
	Data.TILE_ID_TO_STRING_MAP[TILE_ID] = TYPE
	Data.TILE_ID_TO_STRING_MAP[GATE_ID] = GATE_TYPE


static func is_metal(type: String) -> bool:
	return type == TYPE or type == GATE_TYPE


static func is_metal_id(id: int) -> bool:
	return id == TILE_ID or id == GATE_ID


static func sheet() -> Texture2D:
	return Assets.tex(SHEET)


static func particle() -> Texture2D:
	return Assets.tex(PARTICLE)


# A circular blast around `centre` (tile coords), as Map.damageTileCircleArea.
static func record_circle(centre: Vector2, radius: float) -> void:
	_prune()
	_blasts.append({"centre": centre, "radius": radius, "dir": Vector2.ZERO, "distance": 0, "until": Time.get_ticks_msec() + BLAST_TTL_MS})


# A straight blast from the tile after `centre` along `dir`, as
# Map.damageTileDirection.
static func record_line(centre: Vector2, dir: Vector2, distance: int) -> void:
	_prune()
	_blasts.append({"centre": centre, "radius": 0.0, "dir": dir, "distance": distance, "until": Time.get_ticks_msec() + BLAST_TTL_MS})


# Is the tile at `coord` inside a Suit Blaster blast that is still going off?
static func suit_blast_covers(coord: Vector2) -> bool:
	_prune()
	for b: Dictionary in _blasts:
		var c: Vector2 = b["centre"]
		if b["dir"] == Vector2.ZERO:
			if (coord - c).length() <= float(b["radius"]) + 0.01:
				return true
		else:
			var d: Vector2 = b["dir"]
			for i in int(b["distance"]):
				if coord == c + d * (i + 1):
					return true
	return false


static func _prune() -> void:
	var now: int = Time.get_ticks_msec()
	_blasts = _blasts.filter(func(b): return int(b["until"]) > now)
