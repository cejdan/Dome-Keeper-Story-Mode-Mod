extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 17: 50-seed report of the Story Mode map: biome count, mineral mix and
# deposit size per biome against data/map_config.gd, and B4's rare gems.
# Also writes revealed-map pictures of three seeds.

const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")
const MapConfig = preload("res://mods-unpacked/cejdan-StoryMode/data/map_config.gd")
const Palette = preload("res://mods-unpacked/cejdan-StoryMode/util/palette.gd")

const SEEDS: int = 50
const SHARE_TOLERANCE: float = 6.0  # percentage points
const PICTURE_SEEDS: Array = [1, 2, 3]


func boot() -> Dictionary:
	return {"seed": 12345}


static func colors() -> Dictionary:
	var out: Dictionary = {}
	for m: String in Minerals.ORDER:
		out[int(Minerals.TABLE[m]["tile_id"])] = Color(Palette.CELLS[m][3])
	return out


func run(h) -> void:
	h.disable_waves()
	var B: int = MapConfig.BIOMES
	var count: Array = []   # per biome: mineral -> deposits
	var tiles: Dictionary = {}   # mineral -> [deposits, tiles]
	var biome_tiles: Array = []
	for b in B:
		count.append({})
		biome_tiles.append(0)
	var rare: Dictionary = {"emerald": 0, "ruby": 0, "diamond": 0}
	var biome_counts: Dictionary = {}
	var total_tiles: int = 0
	var widths: int = 0
	var depths: int = 0
	var unob: int = 0
	var vanilla_iron_left: int = 0
	var failed: int = 0
	var fill_tiles: int = 0
	var size_out_of_range: int = 0

	for s in SEEDS:
		var td = h.generate_map(MapConfig.make_archetype(), 1000 + s)
		if td == null:
			failed += 1
			continue
		var rect: Rect2i = td.get_used_rect()
		widths += rect.size.x
		depths += rect.size.y
		var max_biome: int = 0
		for c: Vector2i in td.get_used_biome_cells():
			var b: int = td.get_biomev(c)
			max_biome = maxi(max_biome, b)
			if b >= 0 and b < B and td.get_resourcev(c) != Data.TILE_BORDER:
				biome_tiles[b] += 1
				total_tiles += 1
		biome_counts[max_biome + 1] = biome_counts.get(max_biome + 1, 0) + 1
		# The flat bottom (#149) adds B8 rock on top of the archetype's size.
		total_tiles -= int(td.get_meta("story_bottom_fill", 0))
		fill_tiles += int(td.get_meta("story_bottom_fill", 0))
		for m: String in Minerals.ORDER:
			var id: int = int(Minerals.TABLE[m]["tile_id"])
			if m == "unobtainium":
				unob += td.get_resource_cells_by_id(id).size()
				continue
			for group: Array in h.deposits_of(td, id):
				var votes: Dictionary = {}
				for c: Vector2i in group:
					var b: int = clampi(td.get_biomev(c), 0, B - 1)
					votes[b] = votes.get(b, 0) + 1
				var biome: int = 0
				for b: int in votes:
					if votes[b] > votes.get(biome, 0):
						biome = b
				count[biome][m] = count[biome].get(m, 0) + 1
				if not tiles.has(m):
					tiles[m] = [0, 0]
				tiles[m][0] += 1
				tiles[m][1] += group.size()
				if biome == 3 and rare.has(m):
					rare[m] += 1
		if s + 1 in PICTURE_SEEDS:
			h.map_png("story_map_seed%d" % (1000 + s), colors(), 6, td)
		td.queue_free()
		await h.frames(1)

	var n: int = SEEDS - failed
	h.check("all %d seeds generated" % SEEDS, failed == 0, failed)
	h.check("every map has 8 biomes", biome_counts.size() == 1 and biome_counts.has(8), biome_counts)
	h.note("map size", {"avg_tiles": total_tiles / float(n), "avg_width": widths / float(n), "avg_depth_rows": depths / float(n)})
	h.check("about 10,000 tiles before the flat bottom", absf(total_tiles / float(n) - 10000.0) < 600.0, {"before fill": total_tiles / float(n), "bottom fill": fill_tiles / float(n)})
	h.check("no unobtainium in any biome", unob == 0, unob)

	for b in B:
		var mix: Dictionary = MapConfig.MIX[b]
		var rare_here: Dictionary = MapConfig.RARE_COUNTS.get(b, {})
		var in_mix: int = 0
		var all: int = 0
		for m: String in count[b]:
			all += count[b][m]
			if mix.has(m):
				in_mix += count[b][m]
		var wsum: float = 0.0
		for m: String in mix:
			wsum += float(mix[m])
		var row: Dictionary = {}
		var worst: float = 0.0
		for m: String in Minerals.ORDER:
			var got: int = count[b].get(m, 0)
			if got == 0 and not mix.has(m):
				continue
			if mix.has(m):
				var share: float = 100.0 * got / maxf(1.0, float(in_mix))
				var want: float = 100.0 * float(mix[m]) / wsum
				row[m] = "%.1f%% (table %.1f%%)" % [share, want]
				worst = maxf(worst, absf(share - want))
			else:
				row[m] = "%.2f per map (%s)" % [got / float(n), "rare extra" if rare_here.has(m) else "NOT IN TABLE"]
				if not rare_here.has(m):
					worst = 999.0
		row["deposits per map"] = snappedf(all / float(n), 0.1)
		row["tiles per map"] = snappedf(biome_tiles[b] / float(n), 1.0)
		h.check("B%d mix within %.0f points" % [b + 1, SHARE_TOLERANCE], worst <= SHARE_TOLERANCE, row)

	for m: String in tiles:
		var avg: float = tiles[m][1] / float(tiles[m][0])
		var r: Array = MapConfig.SIZES[m]
		var hi: float = float(MapConfig.DIAMOND_DEEP_SIZE[1]) if m == "diamond" else float(r[1])
		# Two deposits of one mineral that touch count as one here, so allow a little over.
		h.check("%s average deposit size in range" % m, avg >= float(r[0]) - 0.01 and avg <= hi + 0.6, {"avg": snappedf(avg, 0.01), "range": r, "deposits": tiles[m][0]})

	var e: float = rare["emerald"] / float(n)
	var r2: float = rare["ruby"] / float(n)
	var d: float = rare["diamond"] / float(n)
	h.check("B4 emerald deposits average about 2 (1-3)", absf(e - 2.0) <= 0.5, e)
	h.check("B4 ruby deposits average about 1.5 (1-2)", absf(r2 - 1.5) <= 0.4, r2)
	h.check("B4 diamond deposits average about 0.5 (0-1)", absf(d - 0.5) <= 0.25, d)

	# The running game's own map, for an in-game look.
	h.map_png("this_run_map", colors())
	var td2 = Level.map.tileData
	h.check("the run's map has minerals from the story mix", td2.get_resource_cells_by_id(40).size() > 0 and td2.get_resource_cells_by_id(Data.TILE_IRON).size() > 0)
