extends RefCounted

# The mineral ladder: every mineral Story Mode knows, in rising dollar value.
# All numbers here are starting values for the user to tune.
#
#   value         dollars paid per piece delivered to the dome
#   tile_id       resource id stored in the map (0 is vanilla iron; new minerals use 40+)
#   extra_health  added to the tile base health (vanilla iron adds 2)
#   richness      drives how many pieces a tile drops (vanilla iron uses 2)
#   shape         art family: "square" metals, "star" gems, "shard" unobtainium

const ORDER: Array = ["bronze", "iron", "gold", "sapphire", "emerald", "ruby", "mythril", "diamond", "unobtainium"]

const TABLE: Dictionary = {
	"bronze": {"value": 1, "tile_id": 40, "extra_health": 2, "richness": 2.0, "shape": "square"},
	"iron": {"value": 5, "tile_id": 0, "extra_health": 2, "richness": 2.0, "shape": "square"},
	"gold": {"value": 10, "tile_id": 41, "extra_health": 2, "richness": 2.0, "shape": "square"},
	"sapphire": {"value": 50, "tile_id": 42, "extra_health": 2, "richness": 2.0, "shape": "star"},
	"emerald": {"value": 100, "tile_id": 43, "extra_health": 2, "richness": 2.0, "shape": "star"},
	"ruby": {"value": 300, "tile_id": 44, "extra_health": 2, "richness": 2.0, "shape": "star"},
	"mythril": {"value": 500, "tile_id": 45, "extra_health": 2, "richness": 2.0, "shape": "square"},
	"diamond": {"value": 1000, "tile_id": 46, "extra_health": 2, "richness": 2.0, "shape": "star"},
	"unobtainium": {"value": 100000, "tile_id": 47, "extra_health": 2, "richness": 1.0, "shape": "shard"},
}


static func is_mineral(type: String) -> bool:
	return TABLE.has(type)


static func value_of(type: String) -> int:
	return int(TABLE[type]["value"]) if TABLE.has(type) else 0


static func by_tile_id(id: int) -> String:
	for m: String in ORDER:
		if int(TABLE[m]["tile_id"]) == id:
			return m
	return ""


# "$1,234,567"
static func dollars(amount: int) -> String:
	var s: String = str(absi(amount))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if amount < 0 else "") + "$" + s + out
