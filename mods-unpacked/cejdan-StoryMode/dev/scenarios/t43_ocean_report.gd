extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 43: the lava ocean on generated maps. 50-seed report (unobtainium only
# in the ocean) and revealed-map pictures of 3 seeds.

const MapConfig = preload("res://mods-unpacked/cejdan-StoryMode/data/map_config.gd")
const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")
const T21 = preload("res://mods-unpacked/cejdan-StoryMode/dev/scenarios/t21_gate.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	var unob: int = int(Minerals.TABLE["unobtainium"]["tile_id"])
	var above_total: int = 0
	var seeds_without: Array = []
	var rows: Array = []
	for s in 50:
		var td = h.generate_map(MapConfig.make_archetype(), 4000 + s)
		if td == null:
			seeds_without.append(4000 + s)
			continue
		var o: Dictionary = td.get_meta("story_ocean", {})
		var inside: int = 0
		var above: int = 0
		for c: Vector2i in td.get_resource_cells_by_id(unob):
			if not o.is_empty() and c.y >= int(o["top"]) and c.y <= int(o["bottom"]):
				inside += 1
			else:
				above += 1
		above_total += above
		if inside == 0:
			seeds_without.append(4000 + s)
		var open: int = 0
		if not o.is_empty():
			for y in range(int(o["top"]), int(o["bottom"]) + 1):
				for x in range(int(o["x0"]), int(o["x1"]) + 1):
					if td.get_resourcev(Vector2i(x, y)) == Data.TILE_EMPTY:
						open += 1
		rows.append({"seed": 4000 + s, "ocean rows": int(o["bottom"]) - int(o["top"]) + 1 if not o.is_empty() else 0, "width": int(o["x1"]) - int(o["x0"]) + 1 if not o.is_empty() else 0,
			"open ocean cells": open, "unobtainium inside": inside, "chamber": td.get_meta("story_boss_chamber", null)})
		if s < 3:
			var col: Dictionary = T21.new()._colors()
			var overlay: Dictionary = {}
			if not o.is_empty():
				for y in range(int(o["top"]), int(o["bottom"]) + 1):
					for x in range(int(o["x0"]), int(o["x1"]) + 1):
						if td.get_resourcev(Vector2i(x, y)) == Data.TILE_EMPTY:
							overlay[Vector2i(x, y)] = Color("#ff5a00")
			var ch = td.get_meta("story_boss_chamber", null)
			if ch is Rect2i:
				for y in range(ch.position.y, ch.end.y):
					for x in range(ch.position.x, ch.end.x):
						overlay[Vector2i(x, y)] = Color("#3a3a50")
			h.map_png("ocean_seed%d" % (4000 + s), col, 4, td, overlay)
		td.queue_free()
		await h.frames(1)
	h.note("ocean per seed (first 5)", rows.slice(0, 5))
	h.check("every seed has an ocean of 50 rows", rows.size() == 50 and rows.all(func(r): return r["ocean rows"] == 50), rows.size())
	h.check("50 seeds: zero unobtainium above the ocean", above_total == 0, above_total)
	h.check("50 seeds: unobtainium inside the ocean on every seed", seeds_without.is_empty(), seeds_without)
	h.check("every seed has a 20 x 10 boss chamber", rows.all(func(r): return r["chamber"] is Rect2i and r["chamber"].size == Vector2i(20, 10)))
