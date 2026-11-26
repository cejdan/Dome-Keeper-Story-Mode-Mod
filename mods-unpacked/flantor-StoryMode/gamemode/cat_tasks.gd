extends "res://content/keeper/keeper4/GoblinTaskManager.gd"

# The Beastmaster's (keeper4) cats in Story Mode (#345). Vanilla's cats extract
# only from iron, sand and water tiles (the type test in GoblinHole's
# get_mineable_tiles and in find_mining_task / _try_pinned_mining_task), so
# they never touched Story Mode's minerals. This task manager, made by the
# Goblins extension in Story Mode runs, is vanilla's with that test widened to
# every Story Mode mineral. The cats' extraction itself (Goblin._process_mining)
# already spawns a piece of the tile's own type per point of richness; the Map
# extension sets each mineral's richness and counts a tile mined out this way.
#
# The three overrides copy vanilla's bodies (staging 2026-11-15) with only the
# type test changed. No extended class_name is named in a type here (Tile,
# Map, Dome are extended; see extensions/installer.gd), so this compiles
# whenever it is first loaded.

const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
static var _Minerals = Minerals  # calls go through this: lazy_preload makes const-preload calls slow

const Bones = preload("res://mods-unpacked/flantor-StoryMode/data/bones.gd")

const CACHE_META := &"story_cat_tiles"


# A tile a cat extracts from: vanilla's three resources, Story Mode's minerals
# and the miner bones (one drop; the Map extension gives it its biome's value).
static func is_cat_ore(tile) -> bool:
	var t: String = tile.type
	return t == CONST.IRON or t == CONST.SAND or t == CONST.WATER or _Minerals.is_mod_mineral(t) or t == Bones.TYPE


# GoblinHole.get_mineable_tiles with is_cat_ore, cached on the hole the same
# way (per path graph generation).
func _mineable_tiles(hole, navigator: GoblinNavigator) -> Array:
	var gen: int = navigator.get_graph_generation()
	if hole.has_meta(CACHE_META):
		var cached: Array = hole.get_meta(CACHE_META)
		if cached[0] == gen:
			return cached[1]
	var hole_tile: Vector2 = Level.map.getTileCoord(hole.global_position)
	var radius: int = CAT_RADIUS_TILES
	var radius_sq: int = CAT_RADIUS_TILES_SQ
	var seeded: Array = Data.ofOr(hole.teamId + "seededTiles", [])
	var candidates: Array = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if abs(dy * dx) > radius_sq:
				continue
			var tile_coord := Vector2(int(hole_tile.x) + dx, int(hole_tile.y) + dy)
			if not Level.map.tiles.has(tile_coord):
				continue
			var tile = Level.map.tiles[tile_coord]
			if not is_cat_ore(tile):
				continue
			if tile.hasTileOverlay():
				continue
			if seeded.has(tile.coord):
				continue
			var adjacent_info := navigator.find_surface_adjacent_to_tile(tile_coord)
			if adjacent_info.is_empty():
				continue
			var surface_pos: Vector2 = adjacent_info.position
			candidates.append({
				"tile": tile,
				"tile_coord": tile_coord,
				"surface_pos": surface_pos,
				"health": tile.health,
				"dist_sq": hole.global_position.distance_squared_to(surface_pos)
			})
	candidates.sort_custom(func(a, b): return a.dist_sq < b.dist_sq)
	hole.set_meta(CACHE_META, [gen, candidates])
	return candidates


func _build_mining_cache(holes: Array) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	var shuffled := holes.duplicate()
	shuffled.shuffle()
	for hole in shuffled:
		if not is_instance_valid(hole) or hole.is_entrance_hole:
			continue
		if hole.hole_state != hole.HoleState.DUG_OUT:
			continue
		var mineables: Array = _mineable_tiles(hole, _navigator)
		for c in mineables:
			var tile_coord: Vector2 = c.tile_coord
			if seen.has(tile_coord):
				continue
			seen[tile_coord] = true
			if _mining_claims.has(tile_coord):
				continue
			var tile = c.tile
			if not is_instance_valid(tile):
				continue
			var path := _navigator.get_surface_path(hole.global_position, c.surface_pos)
			if path.is_empty():
				continue
			result.append({"hole": hole, "tile": tile, "tile_coord": tile_coord})
	return result


func _try_pinned_mining_task(goblin: Node, from_pos: Vector2) -> bool:
	var pinned_coord: Vector2 = goblin._pinned_mining_tile_coord
	if pinned_coord == Vector2.ZERO:
		return false
	var pinned_tile = goblin._pinned_mining_tile
	var pinned_hole = goblin._assigned_hole_for_mining
	goblin._pinned_mining_tile = null
	goblin._pinned_mining_tile_coord = Vector2.ZERO
	if not is_instance_valid(pinned_tile) or not Level.map.tiles.has(pinned_coord):
		release_mining_tile(goblin, pinned_coord)
		return false
	if not is_cat_ore(pinned_tile):
		release_mining_tile(goblin, pinned_coord)
		return false
	var adjacent_info := _navigator.find_surface_adjacent_to_tile(pinned_coord)
	if adjacent_info.is_empty():
		release_mining_tile(goblin, pinned_coord)
		return false
	var path := _navigator.get_surface_path(from_pos, adjacent_info.position)
	if path.is_empty():
		release_mining_tile(goblin, pinned_coord)
		return false
	if not goblin.accept_mining_task(pinned_hole, pinned_tile, pinned_coord, path):
		release_mining_tile(goblin, pinned_coord)
		return false
	return true


func find_mining_task(goblin: Goblin, hole: GoblinHole, from_pos: Vector2) -> Dictionary:
	if not _navigator or not is_instance_valid(Level.map) or not _navigator.has_surface_pathfinding():
		return {}
	if not is_instance_valid(hole):
		return {}
	var base_candidates: Array = _mineable_tiles(hole, _navigator)
	if base_candidates.is_empty():
		return {}

	var candidates: Array = []
	for c in base_candidates:
		var tile = c.tile
		if not is_instance_valid(tile):
			continue
		if not is_cat_ore(tile):
			continue
		if tile.hasTileOverlay():
			continue
		var tile_coord: Vector2 = c.tile_coord
		if _mining_claims.has(tile_coord) and _mining_claims[tile_coord] != goblin:
			continue
		var surface_pos: Vector2 = c.surface_pos
		candidates.append({
			"tile": tile,
			"tile_coord": tile_coord,
			"surface_pos": surface_pos,
			"health": tile.health,
			"dist_sq": surface_pos.distance_squared_to(from_pos)
		})

	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a, b): return a.dist_sq < b.dist_sq)
	for candidate in candidates:
		var path := _navigator.get_surface_path(from_pos, candidate.surface_pos)
		if not path.is_empty():
			return {
				"tile": candidate.tile,
				"tile_coord": candidate.tile_coord,
				"path": path,
				"health": candidate.health
			}
	return {}
