extends RefCounted

# Story Mode saves from before End game 2.0 (#365) keep loading:
#   - Unobtainium (tile id 47) is gone from the game. Any left in a saved
#     ocean becomes open lava (the lava field fills it), and the tile id,
#     no longer registered, would read as plain rock anywhere else.
#   - A saved ocean from before #364 has no tentacles, and one from before
#     #365 no chain anchors: both are placed on load, the way a new map gets
#     them (map/story_gen.gd place_tentacles, place_anchors: no randomness, so
#     the same ocean always gets the same ones). The saved lava in the new
#     anchors' cells is cleared by map/chain_anchors.gd.
#   - The old seal's Data (the unobtainium count and cells, #95, #101) is
#     dropped; the chains start whole.
#   - A saved unobtainium drop (drops/unobtainium_drop.tscn, the path the
#     save names) loads as a diamond.
# Run by mod_main.prepareGameMode on the host's map data before the map is
# built, and drop_data() by the chain anchors once the run's Data is in.

const StoryGen = preload("res://mods-unpacked/flantor-StoryMode/map/story_gen.gd")
static var _StoryGen = StoryGen  # calls go through this: lazy_preload makes const-preload calls slow
const EndGame = preload("res://mods-unpacked/flantor-StoryMode/endgame/end_game.gd")

const UNOBTAINIUM_ID := 47

# What the last migration did, for logs and playtests.
static var last: Dictionary = {}


static func migrate_map(td) -> Dictionary:
	last = {}
	if td == null or not td.has_meta("story_ocean"):
		return last
	var unob: Array = td.get_resource_cells_by_id(UNOBTAINIUM_ID)
	for c in unob:
		td.set_resourcev(Vector2i(c), Data.TILE_EMPTY)
	last["unobtainium tiles cleared"] = unob.size()
	if not td.has_meta("story_tentacles"):
		last["tentacles placed"] = _StoryGen.place_tentacles(td).size()
	if not td.has_meta("story_anchors"):
		last["anchors placed"] = _StoryGen.place_anchors(td).size()
	if last.size() > 1 or unob.size() > 0:
		ModLoaderLog.info("Old Story Mode save brought up to End game 2.0: %s" % str(last), "flantor-StoryMode")
	return last


# The host, once the run's Data is in: the old seal's keys go.
static func drop_data() -> void:
	if Network.is_client():
		return
	for k: String in EndGame.LEGACY_KEYS:
		if Data.values.has(k):
			Data.values.erase(k)
			last["dropped " + k] = true
			ModLoaderLog.info("Old Story Mode save: dropped %s" % k, "flantor-StoryMode")
