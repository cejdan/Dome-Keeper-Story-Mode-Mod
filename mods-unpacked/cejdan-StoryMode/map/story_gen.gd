extends RefCounted

# Story Mode's own steps in map generation, run after vanilla has placed its
# resources (see extensions/content/map/generation/TileDataGenerator.gd).
# Everything is driven by the generator's seeded RandomNumberGenerator, so a
# seed always gives the same map.

const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")
const MapConfig = preload("res://mods-unpacked/cejdan-StoryMode/data/map_config.gd")
const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")

# Special tiles a gate never swallows: gadget, relic, relic switch, power core.
const KEEP_IDS: Array = [3, 4, 6, 7]  # Data.TILE_GADGET, TILE_RELIC, TILE_RELIC_SWITCH, TILE_SUPPLEMENT

const DIRS: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func after_resources(_gen, map_data, rand: RandomNumberGenerator) -> void:
	place_minerals(map_data, rand)
	place_gate(map_data, MapConfig.GATE_BELOW_BIOME, MapConfig.GATE_THICKNESS)


# Lays a metal gate along the boundary under biome index `above` (B3 is 2):
# layer 1 is every cell of a deeper biome that touches (4-neighbour) a cell of
# `above` or shallower, so any path down has to step onto it; each further
# layer is the deeper cells touching the layer before. Whatever was in those
# cells (rock, ore, water, cobalt, holes) becomes gate metal; holes get rock
# hardness so they draw as solid. Returns the gate cells.
static func place_gate(map_data, above: int, thickness: int) -> Array:
	var cells: Array = map_data.get_used_biome_cells()
	var deep: Dictionary = {}
	for cell: Vector2i in cells:
		if map_data.get_biomev(cell) > above and map_data.get_resourcev(cell) != Data.TILE_BORDER:
			deep[cell] = true
	var gate: Dictionary = {}
	var layer: Array = []
	for cell: Vector2i in deep:
		for d: Vector2i in DIRS:
			var n: Vector2i = cell + d
			var nb: int = map_data.get_biomev(n)
			if nb >= 0 and nb <= above:
				layer.append(cell)
				break
	for i in thickness:
		for cell: Vector2i in layer:
			gate[cell] = true
		var next: Array = []
		if i + 1 < thickness:
			for cell: Vector2i in layer:
				for d: Vector2i in DIRS:
					var n: Vector2i = cell + d
					if deep.has(n) and not gate.has(n) and not next.has(n):
						next.append(n)
		layer = next
	var out: Array = gate.keys()
	out.sort()
	var replaced: Dictionary = {}
	var moved: Array = []
	for cell: Vector2i in out:
		var was: int = map_data.get_resourcev(cell)
		replaced[was] = replaced.get(was, 0) + 1
		if KEEP_IDS.has(was):
			moved.append([cell, was])
		map_data.set_resourcev(cell, Metal.GATE_ID)
		if map_data.get_hardnessv(cell) < 0:
			map_data.set_hardnessv(cell, Data.HARDNESS_HARD)
	# Relics, power cores and chamber tiles the wall landed on move to the
	# nearest plain rock below it, so the map keeps them.
	var lost: int = 0
	for m: Array in moved:
		var to = _nearest_plain(map_data, m[0], deep, gate)
		if to == null:
			lost += 1
			continue
		map_data.set_resourcev(to, m[1])
	map_data.set_meta("gate_moved", moved.size() - lost)
	map_data.set_meta("gate_lost", lost)
	# For the map report: what the gate covered, by resource id.
	map_data.set_meta("gate_replaced", replaced)
	return out


# Replaces vanilla's iron with the per-biome mineral mix. Water, cobalt, caves
# and chambers are left exactly where vanilla put them.
static func place_minerals(map_data, rand: RandomNumberGenerator) -> Array:
	for cell: Vector2i in map_data.get_resource_cells_by_id(Data.TILE_IRON):
		map_data.set_resourcev(cell, Data.TILE_DIRT_START)

	# Plain rock cells per biome, in a stable order.
	var rock: Array = []
	var total: Array = []
	for b in MapConfig.BIOMES:
		rock.append([])
		total.append(0)
	var cells: Array = map_data.get_used_biome_cells()
	cells.sort()
	for cell: Vector2i in cells:
		var b: int = clampi(map_data.get_biomev(cell), 0, MapConfig.BIOMES - 1)
		total[b] += 1
		if cell.y >= 2 and map_data.get_resourcev(cell) == Data.TILE_DIRT_START:
			rock[b].append(cell)

	var deposits: Array = []
	var centres: Array = []
	for b in MapConfig.BIOMES:
		var wanted: Array = _deposit_list(b, int(round(MapConfig.DEPOSITS_PER_1000 * total[b] / 1000.0)), rand)
		var candidates: Array = rock[b]
		_shuffle(candidates, rand)
		var next: int = 0
		for mineral: String in wanted:
			var centre = null
			while next < candidates.size():
				var c: Vector2i = candidates[next]
				next += 1
				if map_data.get_resourcev(c) != Data.TILE_DIRT_START:
					continue
				if _too_close(c, centres):
					continue
				centre = c
				break
			if centre == null:
				break
			centres.append(centre)
			var range_: Array = MapConfig.size_range(mineral, b)
			var size: int = rand.randi_range(int(range_[0]), int(range_[1]))
			var tiles: Array = _grow(map_data, centre, int(Minerals.TABLE[mineral]["tile_id"]), size, rand)
			deposits.append({"mineral": mineral, "biome": b, "centre": centre, "tiles": tiles.size()})
	return deposits


# The minerals of a biome's deposits: the rare extras first, then the mix
# shares turned into whole numbers of deposits (largest remainders, with ties
# and leftovers settled by the seeded dice), in a shuffled order.
static func _deposit_list(biome: int, count: int, rand: RandomNumberGenerator) -> Array:
	var out: Array = []
	var rare: Dictionary = MapConfig.RARE_COUNTS.get(biome, {})
	for mineral: String in rare:
		for i in rand.randi_range(int(rare[mineral][0]), int(rare[mineral][1])):
			out.append(mineral)
	var mix: Dictionary = MapConfig.MIX[biome]
	var weight_sum: float = 0.0
	for mineral: String in mix:
		weight_sum += float(mix[mineral])
	var remainders: Array = []
	var placed: int = 0
	for mineral: String in mix:
		var exact: float = count * float(mix[mineral]) / weight_sum
		var whole: int = int(floor(exact))
		for i in whole:
			out.append(mineral)
		placed += whole
		remainders.append([exact - whole, mineral])
	# Hand out what is left one deposit at a time, each mineral's chance being
	# its remainder, so shares come out right on average across seeds.
	var left: int = count - placed
	while left > 0 and remainders.size() > 0:
		var rsum: float = 0.0
		for r: Array in remainders:
			rsum += float(r[0])
		if rsum <= 0.0:
			break
		var roll: float = rand.randf() * rsum
		for i in remainders.size():
			roll -= float(remainders[i][0])
			if roll <= 0.0:
				out.append(remainders[i][1])
				remainders.remove_at(i)
				break
		left -= 1
	_shuffle(out, rand)
	return out


static func _too_close(c: Vector2i, centres: Array) -> bool:
	for o: Vector2i in centres:
		if Vector2(c - o).length() < MapConfig.DEPOSIT_SPACING:
			return true
	return false


# Grows a deposit from `centre` through plain rock, one neighbouring tile at a
# time, like vanilla's iron clusters. It stays inside the centre's biome, so a
# mineral never spills into a biome whose mix does not have it.
static func _grow(map_data, centre: Vector2i, tile_id: int, size: int, rand: RandomNumberGenerator) -> Array:
	map_data.set_resourcev(centre, tile_id)
	var biome: int = map_data.get_biomev(centre)
	var tiles: Array = [centre]
	for attempt in 60:
		if tiles.size() >= size:
			break
		var from: Vector2i = tiles[rand.randi() % tiles.size()]
		var dirs: Array = DIRS.duplicate()
		_shuffle(dirs, rand)
		for d: Vector2i in dirs:
			var n: Vector2i = from + d
			if map_data.get_resourcev(n) == Data.TILE_DIRT_START and map_data.get_biomev(n) == biome:
				map_data.set_resourcev(n, tile_id)
				tiles.append(n)
				break
	return tiles


static func _shuffle(arr: Array, rand: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rand.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


# The closest plain rock cell to `from` among `deep` cells outside `gate`
# (breadth-first through deep cells, so it is on the far side of the wall).
static func _nearest_plain(map_data, from: Vector2i, deep: Dictionary, gate: Dictionary):
	var seen: Dictionary = {from: true}
	var open: Array = [from]
	while open.size() > 0:
		var next: Array = []
		for c: Vector2i in open:
			for d: Vector2i in DIRS:
				var n: Vector2i = c + d
				if seen.has(n) or not deep.has(n):
					continue
				seen[n] = true
				if not gate.has(n) and map_data.get_resourcev(n) == Data.TILE_DIRT_START:
					return n
				next.append(n)
		open = next
	return null
