extends RefCounted

# The Story Mode map: its size and biomes, and which minerals sit where.
# All numbers are starting values for the user to tune.

# The one gate: a metal wall this many tiles thick under biome index
# GATE_BELOW_BIOME (2 = B3), i.e. along the B3/B4 boundary.
const GATE_BELOW_BIOME: int = 2
const GATE_THICKNESS: int = 2

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

# Deposits per 1,000 tiles of a biome. Level with depth for now ("how much more
# common deeper" is still open on the map). 11 gives about vanilla's ore density.
const DEPOSITS_PER_1000: float = 11.0

# Fewest tiles between two deposit centres.
const DEPOSIT_SPACING: float = 4.0

# Mineral mix: each mineral's share of a biome's deposits, in percent. Index 0 is B1.
const MIX: Array = [
	{"bronze": 100},
	{"bronze": 80, "iron": 20},
	{"bronze": 35, "iron": 50, "gold": 15},
	{"bronze": 5, "iron": 35, "gold": 40, "sapphire": 20},
	{"iron": 10, "gold": 42, "sapphire": 32, "emerald": 15, "ruby": 0.5, "diamond": 0.5},
	{"gold": 30, "sapphire": 26, "emerald": 28, "ruby": 15, "diamond": 1},
	{"gold": 12, "sapphire": 13, "emerald": 25, "ruby": 32, "mythril": 15, "diamond": 3},
	{"sapphire": 3, "emerald": 12, "ruby": 25, "mythril": 52, "diamond": 8},
]

# Rare extras given as a number of deposits across the whole biome, [min, max],
# placed on top of the biome's mix. B4 (index 3): a few early gems.
const RARE_COUNTS: Dictionary = {
	3: {"emerald": [1, 3], "ruby": [1, 2], "diamond": [0, 1]},
}

# Deposit size in tiles, [min, max].
const SIZES: Dictionary = {
	"bronze": [3, 6],
	"iron": [3, 6],
	"gold": [5, 9],
	"sapphire": [3, 4],
	"emerald": [2, 4],
	"ruby": [2, 3],
	"mythril": [3, 5],
	"diamond": [1, 1],
}

# Diamond deposits are a single tile down to B6, and 1-2 tiles in B7 and B8.
const DIAMOND_DEEP_FROM_BIOME: int = 6
const DIAMOND_DEEP_SIZE: Array = [1, 2]


static func size_range(mineral: String, biome: int) -> Array:
	if mineral == "diamond" and biome >= DIAMOND_DEEP_FROM_BIOME:
		return DIAMOND_DEEP_SIZE
	return SIZES[mineral]


# The archetype a Story Mode map is generated from.
static func make_archetype() -> MapArchetype:
	var a: MapArchetype = load("res://content/map/generation/archetypes/prestige-10k.tres").duplicate()
	for key: String in ARCHETYPE:
		a.set(key, ARCHETYPE[key])
	a.set_meta("story_map", true)
	return a
