extends RefCounted

# Miner bones (#94): one set per biome, B1 to B8, in the rock. Drilling them
# out drops the bones, which the keeper carries home and sells; selling them at
# the dome opens that biome's data log (data/logs.gd).
#
# Value: about 3x the biome's best common mineral (data/map_config.gd MIX), in
# dollars, by biome index. Starting values for the user to tune.

const Assets = preload("res://mods-unpacked/flantor-StoryMode/util/assets.gd")
static var _Assets = Assets  # calls go through this: lazy_preload makes const-preload calls slow
const Delivery = preload("res://mods-unpacked/flantor-StoryMode/drops/delivery.gd")
static var _Delivery = Delivery  # calls go through this: lazy_preload makes const-preload calls slow

const TYPE := "minerbones"
const TILE_ID := 50
const VALUE_BY_BIOME: Array = [3, 15, 30, 150, 300, 900, 1500, 3000]
const EXTRA_HEALTH := 1
const SHEET := "res://mods-unpacked/flantor-StoryMode/art/items/sheet_minerbones.png"


static func value_for(biome: int) -> int:
	return int(VALUE_BY_BIOME[clampi(biome, 0, VALUE_BY_BIOME.size() - 1)])


static func sheet() -> Texture2D:
	return _Assets.tex(SHEET)


static func register() -> void:
	Data.TILE_ID_TO_STRING_MAP[TILE_ID] = TYPE
	# Sold at the shredder like iron (BonesDrop.shred pays their value).
	_Delivery.register(TYPE, load("res://mods-unpacked/flantor-StoryMode/drops/minerbones_drop.tscn"), "iron")
	Data.DROP_ICONS[TYPE] = _Assets.tex("res://mods-unpacked/flantor-StoryMode/art/items/minerbones.png")
