extends RefCounted

# Miner bones (#94): one set per biome, B1 to B8, in the rock. Uncovering them
# (the tile is revealed) opens that biome's data log (data/logs.gd); drilling
# them out drops the bones, which the keeper carries home and sells.
#
# Value: about 3x the biome's best common mineral (data/map_config.gd MIX), in
# dollars, by biome index. Starting values for the user to tune.

const Assets = preload("res://mods-unpacked/cejdan-StoryMode/util/assets.gd")

const TYPE := "minerbones"
const TILE_ID := 50
const VALUE_BY_BIOME: Array = [3, 15, 30, 150, 300, 900, 1500, 3000]
const EXTRA_HEALTH := 1
const SHEET := "res://mods-unpacked/cejdan-StoryMode/art/items/sheet_minerbones.png"


static func value_for(biome: int) -> int:
	return int(VALUE_BY_BIOME[clampi(biome, 0, VALUE_BY_BIOME.size() - 1)])


static func sheet() -> Texture2D:
	return Assets.tex(SHEET)


static func register() -> void:
	Data.TILE_ID_TO_STRING_MAP[TILE_ID] = TYPE
	if not Data.DROP_TYPES.has(TYPE):
		Data.DROP_TYPES.append(TYPE)
	Data.DROP_SCENES[TYPE] = load("res://mods-unpacked/cejdan-StoryMode/drops/minerbones_drop.tscn")
	Data.DROP_ICONS[TYPE] = Assets.tex("res://mods-unpacked/cejdan-StoryMode/art/items/minerbones.png")
