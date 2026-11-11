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
# Gate tiles: metal that sits in a gate wall. Same look and rules, plus one:
# when a Suit Blaster blast breaks a gate tile, the gate tile right behind it
# (farther from the blast) breaks too, so one base 3x3 blast gets through a
# 2-thick wall. A keeper standing on the wall only reaches its first layer.
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


# Gate tiles behind a broken one, let through once each: coord -> expiry ms.
static var _pass: Dictionary = {}


# Is the tile at `coord` inside a Suit Blaster blast that is still going off,
# or a gate tile let through behind one?
static func suit_blast_covers(coord: Vector2) -> bool:
	if _pass.has(coord):
		if int(_pass[coord]) > Time.get_ticks_msec():
			return true
		_pass.erase(coord)
	return not blast_covering(coord).is_empty()


# The recorded blast covering `coord`, or {}.
static func blast_covering(coord: Vector2) -> Dictionary:
	_prune()
	for b: Dictionary in _blasts:
		var c: Vector2 = b["centre"]
		if b["dir"] == Vector2.ZERO:
			if (coord - c).length() <= float(b["radius"]) + 0.01:
				return b
		else:
			var d: Vector2 = b["dir"]
			for i in int(b["distance"]):
				if coord == c + d * (i + 1):
					return b
	return {}


static func _prune() -> void:
	var now: int = Time.get_ticks_msec()
	_blasts = _blasts.filter(func(b): return int(b["until"]) > now)


# A gate tile at `coord` was just broken by `blast`: break the gate tiles next
# to it that lie farther from the blast (straight on along a line blast). They
# are revealed first, since only revealed tiles exist as nodes.
static func break_behind(coord: Vector2, blast: Dictionary, teamId: String) -> void:
	var map = Level.map
	if map == null:
		return
	var c: Vector2 = blast["centre"]
	var behind: Array = []
	if blast["dir"] != Vector2.ZERO:
		behind.append(coord + Vector2(blast["dir"]))
	else:
		var d: float = (coord - c).length()
		for off: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var n: Vector2 = coord + off
			if (n - c).length() > d + 0.01:
				behind.append(n)
	var targets: Array = []
	for n: Vector2 in behind:
		if map.tileData.get_resourcev(Vector2i(n)) == GATE_ID:
			targets.append(n)
			_pass[n] = Time.get_ticks_msec() + BLAST_TTL_MS
	if targets.is_empty():
		return
	await map.get_tree().create_timer(0.1).timeout
	if not is_instance_valid(map):
		return
	map.tileCoordsToReveal.append_array(targets)
	map.floodRevealTiles()
	for n: Vector2 in targets:
		var t = map.getTile(n)
		if t != null and t.health > 0:
			t.exploded = true
			t.hit(n - coord, t.max_health + 1, teamId)
