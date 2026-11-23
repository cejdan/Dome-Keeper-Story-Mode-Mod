extends RefCounted

# The Story Mode map: its size and biomes, and which minerals sit where.
# All numbers are starting values for the user to tune.

# The one gate: a metal wall this many tiles thick (1, per the user: a base
# Suit Blaster blast opens it with no special rule) under biome index
# GATE_BELOW_BIOME (2 = B3), i.e. along the B3/B4 boundary.
const GATE_BELOW_BIOME: int = 2
const GATE_THICKNESS: int = 1

# Gold at the gate (#133): GATE_GOLD_DEPOSITS gold deposits of GATE_GOLD_SIZE
# tiles sit in B3 just above the gate (1 to GATE_GOLD_ROWS rows over it), in
# the middle half of the map where players dig down, so the Blast Suit's money
# waits right where it is needed.
const GATE_GOLD_DEPOSITS: int = 2
const GATE_GOLD_SIZE: Array = [6, 9]
const GATE_GOLD_ROWS: int = 5
const GATE_GOLD_SPACING: int = 10

# Flat bottom (#149): columns whose lowest map cell is at most this many rows
# above the map's deepest row are filled with B8 rock down to it, so digging
# straight down reaches the lava ocean. Side arms ending higher stay open map
# edge.
const BOTTOM_FILL_ROWS: int = 45

# Scattered metal: share of a biome's plain rock that becomes metal, by biome
# index (5 = B6), placed in clumps of METAL_CLUMP tiles. None anywhere else.
const METAL_SHARE: Dictionary = {5: 0.03, 6: 0.08, 7: 0.15}
const METAL_CLUMP: Array = [2, 5]

# Overrides on vanilla's prestige-10k archetype (about 80 wide, 10,000 tiles).
# Sizes 600, 800, ... capped at 1,800 give eight biomes, B1 to B8.
const ARCHETYPE: Dictionary = {
	"width": 80,
	"tileCount": 10000,
	"first_biome_size": 600,
	"biome_size_addition": 200,
	"biome_size_multiplier": 1,
	"biome_max_size": 1800,
}
const BIOMES: int = 8

# Tile health grows by this factor per biome in Story Mode (#148; vanilla
# uses 2.1). Lower than vanilla because Story Mode has eight biomes where a
# vanilla map has about five: at 2.1 a B8 tile had 180 times B1's health and
# each drill level bought about one biome. Applied in mod_main.gd
# prepareGameMode, after vanilla sets its own.
const TILE_HEALTH_PER_BIOME: float = 1.9

# Deposits per 1,000 tiles of a biome. Level with depth for now ("how much more
# common deeper" is still open on the map). 11 gives about vanilla's ore density.
const DEPOSITS_PER_1000: float = 11.0

# Fewest tiles between two deposit centres.
const DEPOSIT_SPACING: float = 4.0

# Mineral mix: each mineral's share of a biome's deposits, in percent. Index 0 is B1.
# Past the gate (B4 on) there is no bronze or iron, gold fades out by B6, and
# the gems come in one per biome (#186): B4 sapphire, B5 emerald, B6 ruby,
# B7 mythril, B8 diamond.
const MIX: Array = [
	{"bronze": 100},
	{"bronze": 80, "iron": 20},
	{"bronze": 35, "iron": 50, "gold": 15},
	{"gold": 55, "sapphire": 45},
	{"gold": 20, "sapphire": 40, "emerald": 40},
	{"sapphire": 20, "emerald": 40, "ruby": 40},
	{"emerald": 15, "ruby": 35, "mythril": 50},
	{"ruby": 15, "mythril": 45, "diamond": 40},
]

# Rare extras given as a number of deposits across the whole biome, [min, max],
# placed on top of the biome's mix. None for now (#186 took out B4's early
# emeralds, rubies and diamonds).
const RARE_COUNTS: Dictionary = {}

# Bronze by the dome (#186): START_BRONZE_DEPOSITS small bronze deposits in
# rows START_BRONZE_ROWS, START_BRONZE_REACH columns or less from the dome
# (column 0), at least START_BRONZE_SPACING columns apart, so the first defence
# money is a short dig away, like vanilla's early iron.
const START_BRONZE_DEPOSITS: int = 3
const START_BRONZE_SIZE: Array = [2, 3]
const START_BRONZE_ROWS: Array = [2, 4]
const START_BRONZE_REACH: int = 14
const START_BRONZE_SPACING: int = 5

# Deposit size in tiles, [min, max].
const SIZES: Dictionary = {
	"bronze": [3, 6],
	"iron": [3, 6],
	"gold": [5, 9],
	"sapphire": [3, 4],
	"emerald": [2, 4],
	"ruby": [2, 3],
	"mythril": [3, 5],
	"diamond": [1, 1],   # always a lone tile (#186); see Minerals "drops"
}


static func size_range(mineral: String, _biome: int) -> Array:
	return SIZES[mineral]


# Map sizes (#320), picked in the loadout with vanilla's Relic Hunt size
# choices (same ids). Each is a share of the full map's tiles (ARCHETYPE,
# "Huge"): every biome is that share of its full size, so all eight biomes are
# still there, and the width, depth, rows filled at the bottom and power core
# depths shrink by the square root of it. Caves per biome shrink with the tile
# share, so a smaller map is not more cave. Mineral deposits are packed closer
# by 1 / that square root (DEPOSITS_PER_1000 / root: Small x1.8, Medium x1.4,
# Large x1.2), so a biome is worth about root x the full map's (Small ~55%)
# and the one shop price list fits every size. The per-biome story items
# (translators, bones) keep their counts, so they turn up more often (#326).
const MAP_SIZE_SHARE: Dictionary = {
	"regular-small": 0.3,
	"regular-medium": 0.5,
	"regular-large": 0.7,
	"regular-huge": 1.0,
}
# Picked for a player who has never chosen a Story Mode size.
const DEFAULT_MAP_SIZE: String = "regular-medium"
# The size the playtest scenarios and dev boots generate when none is given:
# the full map, which every regression scenario was written against.
const FULL_MAP_SIZE: String = "regular-huge"
const SCALED_BY_SHARE: Array = ["tileCount", "first_biome_size", "biome_size_addition", "biome_max_size"]
const SCALED_BY_ROOT: Array = ["width", "depth", "powercore_first_depth", "powercore_depth_step", "gadget_first_depth", "gadget_depth_step"]


static func map_share(size_id: String) -> float:
	return float(MAP_SIZE_SHARE.get(size_id, 1.0))


# The archetype a Story Mode map is generated from, for a size id
# (MAP_SIZE_SHARE; anything else is the full map).
static func make_archetype(size_id: String = FULL_MAP_SIZE) -> MapArchetype:
	var a: MapArchetype = load("res://content/map/generation/archetypes/prestige-10k.tres").duplicate()
	for key: String in ARCHETYPE:
		a.set(key, ARCHETYPE[key])
	var share: float = map_share(size_id)
	var root: float = sqrt(share)
	if share != 1.0:
		for key: String in SCALED_BY_SHARE:
			a.set(key, roundi(float(a.get(key)) * share))
		for key: String in SCALED_BY_ROOT:
			a.set(key, roundi(float(a.get(key)) * root))
		a.holes_per_biome = maxi(2, roundi(a.holes_per_biome * share))
	a.set_meta("story_map", true)
	a.set_meta("story_map_size", size_id if MAP_SIZE_SHARE.has(size_id) else FULL_MAP_SIZE)
	a.set_meta("story_map_root", root)
	return a
