extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 320: Story Mode map sizes. For each of the four sizes, a few seeds are
# generated without starting a run, and every map must still have all eight
# biomes, the gate, three translators, eight bones, the lava ocean with the
# boss chamber, the gate gold and its power cores. Notes each size's tiles,
# width and rows (to the gate, to the ocean, to the chamber), so the sizes can
# be compared; writes a map picture of each size's first seed.

const MapConfig = preload("res://mods-unpacked/flantor-StoryMode/data/map_config.gd")
static var _MapConfig = MapConfig  # calls go through this: lazy_preload makes const-preload calls slow
const Metal = preload("res://mods-unpacked/flantor-StoryMode/data/metal.gd")
const TIMEOUT := 900
const SEEDS := 5
const SIZES: Array = ["regular-small", "regular-medium", "regular-large", "regular-huge"]


func boot() -> Dictionary:
	return {"seed": 12345}


func _count_chambers(td) -> int:
	var left: Dictionary = {}
	for c: Vector2i in td.get_resource_cells_by_id(Data.TILE_SUPPLEMENT):
		left[c] = true
	var n: int = 0
	while left.size() > 0:
		var open: Array = [left.keys()[0]]
		left.erase(open[0])
		while open.size() > 0:
			var c: Vector2i = open.pop_back()
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if left.has(c + d):
					left.erase(c + d)
					open.append(c + d)
		n += 1
	return n


func run(h) -> void:
	h.disable_waves()
	var summary: Dictionary = {}
	for size: String in SIZES:
		var rows: Array = []
		for s in SEEDS:
			var td = h.generate_map(_MapConfig.make_archetype(size), 32000 + s)
			if td == null:
				h.check("%s seed %d generates" % [size, s], false)
				continue
			var biomes: Dictionary = {}
			var tiles: int = 0
			var x0: int = 1 << 20
			var x1: int = -(1 << 20)
			for c: Vector2i in td.get_used_biome_cells():
				var b: int = td.get_biomev(c)
				if b < 0:
					continue
				biomes[b] = true
				tiles += 1
				x0 = mini(x0, c.x)
				x1 = maxi(x1, c.x)
			var gate_y: int = 1 << 20
			for c: Vector2i in td.get_resource_cells_by_id(Metal.GATE_ID):
				gate_y = mini(gate_y, c.y)
			var ocean: Dictionary = td.get_meta("story_ocean", {})
			var chamber: Rect2i = td.get_meta("story_boss_chamber", Rect2i())
			var row: Dictionary = {
				"seed": s, "tiles": tiles, "biomes": biomes.size(), "width": x1 - x0 + 1,
				"gate_row": gate_y, "ocean_top": int(ocean.get("top", -1)), "chamber_row": chamber.position.y,
				"translators": td.get_meta("story_translators", []).size(), "bones": td.get_meta("story_bones", []).size(),
				"gate_gold": td.get_meta("story_gate_gold", []).size(), "power_cores": _count_chambers(td),
				"size_meta": td.get_meta("story_map_size", ""),
			}
			rows.append(row)
			var ok: bool = row.biomes == MapConfig.BIOMES and gate_y < (1 << 20) and row.translators == 3 and row.bones == MapConfig.BIOMES \
				and not ocean.is_empty() and chamber.size.x > 0 and row.gate_gold == MapConfig.GATE_GOLD_DEPOSITS and row.power_cores >= 1 \
				and row.size_meta == size
			h.check("%s seed %d complete" % [size, s], ok, row)
			if s == 0:
				h.map_png("map_" + size.replace("regular-", ""), {}, 4, td)
			td.queue_free()
			await h.frames(1)
		var avg: Dictionary = {}
		for key: String in ["tiles", "width", "gate_row", "ocean_top", "chamber_row", "power_cores"]:
			var t: float = 0.0
			for r: Dictionary in rows:
				t += float(r[key])
			avg[key] = snappedf(t / maxf(1.0, rows.size()), 0.1)
		summary[size] = avg
		h.note("size " + size, {"average": avg, "maps": rows})
	h.note("summary", summary)
	var shrinks: bool = true
	for i in range(1, SIZES.size()):
		if float(summary[SIZES[i - 1]]["chamber_row"]) >= float(summary[SIZES[i]]["chamber_row"]):
			shrinks = false
	h.check("each size is shallower than the next", shrinks, summary)
