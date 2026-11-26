extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 375: the early economy against vanilla's. Early shop prices are $1 per
# vanilla iron, so a Story Mode map's early mineral dollars (bronze $1, iron $5,
# gold $10 a piece) are set beside a vanilla Relic Hunt map's iron pieces at the
# same size, averaged over a few seeds: by depth (rows 0-10, 0-20, ... across
# the whole width), near the dome (|column| <= NEAR_COLS, rows <= NEAR_ROWS), by
# biome (first three), and the tiles in each first biome. 2 pieces a tile on
# both sides (richness 2). The report goes into the log.

const MapConfig = preload("res://mods-unpacked/flantor-StoryMode/data/map_config.gd")
static var _MapConfig = MapConfig  # calls go through this: lazy_preload makes const-preload calls slow
const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
static var _Minerals = Minerals  # calls go through this: lazy_preload makes const-preload calls slow

const SEEDS := 8
const TIMEOUT := 900
const SIZES: Array = ["regular-medium", "regular-huge"]
const DEPTHS: Array = [10, 20, 30, 40]
const NEAR_COLS := 15
const NEAR_ROWS := 12


func boot() -> Dictionary:
	return {"seed": 12345}


func _measure(h, archetype_of: Callable, size: String, story: bool) -> Dictionary:
	var by_depth: Array = []
	for d in DEPTHS:
		by_depth.append(0.0)
	var near: float = 0.0
	var by_biome: Array = [0.0, 0.0, 0.0]
	var tiles_b: Array = [0.0, 0.0, 0.0]
	var top_row: int = 1 << 30
	for s in SEEDS:
		var td = h.generate_map(archetype_of.call(size), 7000 + s)
		if td == null:
			continue
		for c: Vector2i in td.get_used_biome_cells():
			var b: int = td.get_biomev(c)
			if b >= 0 and b < 3:
				tiles_b[b] += 1
			top_row = mini(top_row, c.y)
			var r: int = td.get_resourcev(c)
			var v: float = 0.0
			if story:
				if r >= 40 or r == Data.TILE_IRON:
					var m: String = _Minerals.by_tile_id(r)
					if m == "bronze" or m == "iron" or m == "gold":
						v = 2.0 * _Minerals.value_of(m)
			elif r == Data.TILE_IRON:
				v = 2.0
			if v == 0.0:
				continue
			for i in DEPTHS.size():
				if c.y <= int(DEPTHS[i]):
					by_depth[i] += v
			if absi(c.x) <= NEAR_COLS and c.y <= NEAR_ROWS:
				near += v
			if b >= 0 and b < 3:
				by_biome[b] += v
		td.queue_free()
		await h.frames(1)
	var out := {"top row": top_row, "near dome $": int(near / SEEDS)}
	for i in DEPTHS.size():
		out["rows 0-%d $" % DEPTHS[i]] = int(by_depth[i] / SEEDS)
	for b in 3:
		out["B%d $" % (b + 1)] = int(by_biome[b] / SEEDS)
		out["B%d tiles" % (b + 1)] = int(tiles_b[b] / SEEDS)
	return out


func run(h) -> void:
	h.disable_waves()
	h.mute_beats()
	var report: Dictionary = {}
	for size: String in SIZES:
		var vanilla := await _measure(h, func(sz): return load("res://content/map/generation/archetypes/%s.tres" % sz), size, false)
		var story := await _measure(h, func(sz): return _MapConfig.make_archetype(sz), size, true)
		report[size] = {"vanilla iron": vanilla, "story $": story}
		h.note("size " + size, report[size])
	h.note("report", report)
	h.check("report written", report.size() == SIZES.size(), report)
