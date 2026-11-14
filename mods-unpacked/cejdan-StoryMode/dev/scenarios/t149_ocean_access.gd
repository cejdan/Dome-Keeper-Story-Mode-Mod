extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 149: from where the keeper is, does digging straight down reach the
# lava ocean? For every diggable map cell of generated maps: it does when every
# cell below it, down to the ocean ceiling, is diggable map (no border, no
# indestructible rock, no void). Reported for B7/B8 cells (where the dive
# starts) and for all cells, plus pictures of three seeds.

const MapConfig = preload("res://mods-unpacked/cejdan-StoryMode/data/map_config.gd")
const T21 = preload("res://mods-unpacked/cejdan-StoryMode/dev/scenarios/t21_gate.gd")

const SEEDS := 20
const TIMEOUT := 600


func boot() -> Dictionary:
	return {"seed": 12345}


static func diggable(td, c: Vector2i) -> bool:
	return td.get_biomev(c) >= 0 and td.get_resourcev(c) != Data.TILE_BORDER and td.get_hardnessv(c) < Data.HARDNESS_INDESTRUCTIBLE


func run(h) -> void:
	h.disable_waves()
	var deep_ok: int = 0
	var deep_n: int = 0
	var all_ok: int = 0
	var all_n: int = 0
	var per_seed: Array = []
	for s in SEEDS:
		var td = h.generate_map(MapConfig.make_archetype(), 6000 + s)
		if td == null:
			continue
		var o: Dictionary = td.get_meta("story_ocean", {})
		var ceiling: int = int(o["ceiling"])
		# Per column, the top of the unbroken diggable run that ends on the ceiling.
		var run_top: Dictionary = {}
		for x in range(int(o["x0"]), int(o["x1"]) + 1):
			var y: int = ceiling - 1
			while y >= 0 and diggable(td, Vector2i(x, y)):
				y -= 1
			run_top[x] = y + 1 if y < ceiling - 1 else ceiling
		var d_ok: int = 0
		var d_n: int = 0
		var a_ok: int = 0
		var a_n: int = 0
		for c: Vector2i in td.get_used_biome_cells():
			if c.y >= ceiling or c.y < 1 or not diggable(td, c):
				continue
			var reach: bool = c.y >= int(run_top.get(c.x, ceiling))
			a_n += 1
			a_ok += int(reach)
			if td.get_biomev(c) >= 6:
				d_n += 1
				d_ok += int(reach)
		deep_ok += d_ok
		deep_n += d_n
		all_ok += a_ok
		all_n += a_n
		per_seed.append({"seed": 6000 + s, "B7/B8 cells reaching %": snappedf(100.0 * d_ok / maxf(1, d_n), 0.1), "all cells %": snappedf(100.0 * a_ok / maxf(1, a_n), 0.1), "bottom fill tiles": td.get_meta("story_bottom_fill", 0)})
		if s < 3:
			var overlay: Dictionary = {}
			for y in range(int(o["top"]), int(o["bottom"]) + 1):
				for x in range(int(o["x0"]), int(o["x1"]) + 1):
					if td.get_resourcev(Vector2i(x, y)) == Data.TILE_EMPTY:
						overlay[Vector2i(x, y)] = Color("#ff5a00")
			h.map_png("bottom_seed%d" % (6000 + s), T21.new()._colors(), 4, td, overlay)
		td.queue_free()
		await h.frames(1)
	for r in per_seed:
		h.note("seed", r)
	var deep: float = 100.0 * deep_ok / maxf(1.0, deep_n)
	var all: float = 100.0 * all_ok / maxf(1.0, all_n)
	h.note("straight down reaches the ocean", {"from B7/B8 cells %": snappedf(deep, 0.1), "from any cell %": snappedf(all, 0.1)})
	h.check("from B7/B8, straight down reaches the ocean from at least 85%% of cells (%.1f%%)" % deep, deep >= 85.0)
	h.check("from anywhere, at least 70%% (%.1f%%)" % all, all >= 70.0)
