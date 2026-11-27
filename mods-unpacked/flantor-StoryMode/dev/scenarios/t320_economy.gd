extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 320: what each map size is worth against the shop. For each size,
# over a few seeds: dollars of minerals per biome above the lava ocean (tiles x
# 2 pieces x value; diamond 1 piece), the miner bones' value, and the
# chain anchors in the ocean (#365: Unobtainium is gone). The shop
# side is read from this run's real prices by buying, in order, what a run
# needs to reach the ocean: the Suit Blaster, Heat Shielding I-IV, the drill
# ladder and a basic laser dome kit. The report goes into the log.

const MapConfig = preload("res://mods-unpacked/flantor-StoryMode/data/map_config.gd")
static var _MapConfig = MapConfig  # calls go through this: lazy_preload makes const-preload calls slow
const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
static var _Minerals = Minerals  # calls go through this: lazy_preload makes const-preload calls slow
const Bones = preload("res://mods-unpacked/flantor-StoryMode/data/bones.gd")

const SEEDS := 5
const TIMEOUT := 900
const SIZES: Array = ["regular-small", "regular-medium", "regular-large", "regular-huge"]
const SHOP: Array = [
	["suit blaster", ["storysuitblaster"]],
	["heat shielding I", ["storyheatshield1"]],
	["heat shielding II", ["storyheatshield2"]],
	["heat shielding III", ["storyheatshield3"]],
	["heat shielding IV", ["storyheatshield4"]],
	["drill I-IV", ["drill1", "drill2", "drill3", "drill4"]],
	["drill V-VI", ["drill4", "drill4"]],
	["laser kit (strength I-IV, move I-II, dome health I-II)", ["laserstrength1", "laserstrength2", "laserstrength3", "laserstrength4", "lasermove1", "lasermove2", "dome1health1", "dome1health2"]],
]


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	h.mute_beats()
	# The shop at this run's prices.
	h.set_inv("money", 10000000)
	var shop: Dictionary = {}
	for row: Array in SHOP:
		var paid: int = 0
		for id: String in row[1]:
			var m0: int = h.inv("money")
			await h.buy(id)
			paid += m0 - h.inv("money")
		shop[row[0]] = paid
	h.note("shop", shop)
	var B: int = MapConfig.BIOMES
	var report: Dictionary = {}
	for size: String in SIZES:
		var per_biome: Array = []
		var pieces_b: Array = []
		var by_min: Array = []
		for b in B:
			per_biome.append(0.0)
			pieces_b.append(0.0)
			by_min.append({})
		var anchors: float = 0.0
		for s in SEEDS:
			var td = h.generate_map(_MapConfig.make_archetype(size), 7000 + s)
			if td == null:
				continue
			var o: Dictionary = td.get_meta("story_ocean", {})
			anchors += td.get_meta("story_anchors", []).size()
			for c: Vector2i in td.get_used_biome_cells():
				var r: int = td.get_resourcev(c)
				var m: String = _Minerals.by_tile_id(r) if (r >= 40 or r == Data.TILE_IRON) else ""
				if not o.is_empty() and c.y >= int(o["ceiling"]):
					continue
				var b: int = td.get_biomev(c)
				if b < 0 or b >= B or m == "":
					continue
				var pieces: int = int(Minerals.TABLE[m].get("drops", 2))
				per_biome[b] += pieces * _Minerals.value_of(m)
				pieces_b[b] += pieces
				by_min[b][m] = by_min[b].get(m, 0) + pieces * _Minerals.value_of(m)
			for bone: Array in td.get_meta("story_bones", []):
				per_biome[int(bone[2])] += Bones.value_for(int(bone[2]))
			td.queue_free()
			await h.frames(1)
		var running: int = 0
		var rows: Array = []
		for b in B:
			var v: int = int(per_biome[b] / SEEDS)
			running += v
			var mix: Dictionary = {}
			for m: String in by_min[b]:
				mix[m] = int(by_min[b][m] / SEEDS)
			rows.append({"biome": "B%d" % (b + 1), "$": v, "running $": running, "pieces": int(pieces_b[b] / SEEDS),
				"$ per piece": snappedf(per_biome[b] / maxf(1.0, pieces_b[b]), 0.1), "$ by mineral": mix})
		report[size] = {"biomes": rows, "minerals and bones $": running, "chain anchors": snappedf(anchors / SEEDS, 0.1)}
		h.note("size " + size, report[size])
	h.note("report", report)
	h.check("report written", report.size() == SIZES.size(), report)
