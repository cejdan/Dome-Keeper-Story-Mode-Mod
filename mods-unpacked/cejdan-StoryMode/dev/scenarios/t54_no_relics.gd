extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 54: no relic on Story Mode maps, over 50 seeds. Split out of
# t54_retire_rich (#120), whose doom ending left room for only 25 seeds inside
# the harness's 300 s timeout. Maps only, no run played.

const MapConfig = preload("res://mods-unpacked/cejdan-StoryMode/data/map_config.gd")
const T21 = preload("res://mods-unpacked/cejdan-StoryMode/dev/scenarios/t21_gate.gd")
const SEEDS := 50
# About 5 s a map: the sweep alone takes ~255 s (playtest.ps1 reads this).
const TIMEOUT := 480


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	var relics: int = 0
	var failed: int = 0
	var t0: float = h.now()
	for s in SEEDS:
		var td = h.generate_map(MapConfig.make_archetype(), 3000 + s)
		if td == null:
			failed += 1
		else:
			relics += td.get_resource_cells_by_id(Data.TILE_RELIC).size() + td.get_resource_cells_by_id(Data.TILE_RELIC_SWITCH).size()
			if s < 3:
				var c: Dictionary = T21.new()._colors()
				c[Data.TILE_RELIC] = Color("#ff00ff")
				c[Data.TILE_RELIC_SWITCH] = Color("#ff00ff")
				h.map_png("no_relic_seed%d" % (3000 + s), c, 4, td)
			td.queue_free()
		await h.frames(1)
	h.note("sweep time", {"seconds": snappedf(h.now() - t0, 0.1)})
	h.check("all %d seeds generated" % SEEDS, failed == 0, failed)
	h.check("%d seeds: zero relic or relic switch tiles" % SEEDS, relics == 0, relics)
	h.check("this run's map: no relic", Level.map.tileData.get_resource_cells_by_id(Data.TILE_RELIC).is_empty())
