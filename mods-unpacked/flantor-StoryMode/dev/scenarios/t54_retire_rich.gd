extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 54: Retire Rich, shown as Fill Quota, in the shop's Leave the Planet
# section. Since #368 it is impossible: $25,000,000, more than any map is
# worth (t368_quota sums the maps), and buying it (a dev cheat's money) wins
# nothing. No relic on this run's map; the many-seed check is t54_no_relics.


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	h.check("this run's map: no relic", Level.map.tileData.get_resource_cells_by_id(Data.TILE_RELIC).is_empty())
	var entry: Dictionary = GameWorld.upgrades.get("team1.storyretirerich", {})
	h.check("Fill Quota is in the shop at $25,000,000", entry.get("cost", {}) == {"money": 25000000}, entry.get("cost", {}))
	h.set_inv("money", 1000000)
	var refused: bool = not (await h.buy("storyretirerich"))
	h.check("with $1,000,000 (the old quota) it can't be bought", refused and not GameWorld.won, h.inv("money"))
	# A dev cheat's money: bought, and nothing happens.
	h.set_inv("money", 25000000)
	var ok: bool = await h.buy("storyretirerich")
	h.check("with a cheat's $25,000,000 it is bought", ok and h.inv("money") == 0, h.inv("money"))
	await h.wait(6.0)
	h.check("and wins nothing: no ending, the run goes on", not GameWorld.won and not Level.mode.is_ending(), {"won": GameWorld.won, "ending": Level.mode.is_ending()})
