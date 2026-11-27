extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #365: where the generator puts the ten chain anchors, over many seeds and
# every map size, without starting runs. For each map: ten anchors (five per
# tentacle), each a full 2 x 2 block of anchor tiles in the ocean, none inside
# either tentacle's swing reach, none by a chamber entry, apart from each
# other, rock or the tentacle within reach (the Beastmaster), and no
# Unobtainium anywhere. A picture of a few oceans: rock, open ocean, the
# tentacles' reach (pink), the tentacle columns (purple), anchors (blue), and
# each anchor's chain to its attach point (light blue).

const MapConfig = preload("res://mods-unpacked/flantor-StoryMode/data/map_config.gd")
static var _MapConfig = MapConfig  # calls go through this: lazy_preload makes const-preload calls slow
const AnchorData = preload("res://mods-unpacked/flantor-StoryMode/data/anchors.gd")
const TentData = preload("res://mods-unpacked/flantor-StoryMode/data/tentacles.gd")
const StoryGen = preload("res://mods-unpacked/flantor-StoryMode/map/story_gen.gd")
static var _StoryGen = StoryGen  # calls go through this: lazy_preload makes const-preload calls slow
const LavaData = preload("res://mods-unpacked/flantor-StoryMode/data/lava.gd")

const TIMEOUT := 900
const SIZES: Array = ["regular-small", "regular-medium", "regular-large", "regular-huge"]
const SEEDS := 6
const PICTURES := 4


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	var bad: Array = []
	var maps: int = 0
	var unob: int = 0
	var fallback: int = 0
	var pictures: int = 0
	var by_slot: Dictionary = {}
	for size: String in SIZES:
		for s in SEEDS:
			var td = h.generate_map(_MapConfig.make_archetype(size), 3650 + s)
			if td == null:
				continue
			maps += 1
			unob += td.get_resource_cells_by_id(47).size()
			var res: Dictionary = _check_map(td)
			res["size"] = size
			res["seed"] = 3650 + s
			if not res["problems"].is_empty():
				bad.append(res)
			fallback += int(res["unsupported"])
			for a in res["anchors"]:
				var k: String = "slot %d" % int(a["slot"])
				by_slot[k] = int(by_slot.get(k, 0)) + 1
			if s == 0 or (pictures < PICTURES and not res["problems"].is_empty()):
				_picture(h, td, "%s_%d" % [size, 3650 + s])
				pictures += 1
			if maps <= 2:
				h.note("anchors %s seed %d" % [size, 3650 + s], res["anchors"])
			td.queue_free()
	h.note("anchors per slot over %d maps" % maps, by_slot)
	h.check("maps generated (%d)" % maps, maps >= SIZES.size() * SEEDS - 2, maps)
	h.check("no unobtainium on any map", unob == 0, unob)
	h.check("every map has 10 anchors, 5 per tentacle, each a full block outside the swing, off the entries, apart, reachable", bad.is_empty(), bad.slice(0, 4))
	h.check("every anchor has rock or the tentacle in a climber's reach", fallback == 0, fallback)


func _check_map(td) -> Dictionary:
	var anchors: Array = td.get_meta("story_anchors", [])
	var tents: Array = td.get_meta("story_tentacles", [])
	var ocean: Dictionary = td.get_meta("story_ocean", {})
	var ch: Rect2i = td.get_meta("story_boss_chamber", Rect2i())
	var problems: Array = []
	var unsupported: int = 0
	if anchors.size() != AnchorData.PER_TENTACLE * tents.size() or tents.size() != 2:
		problems.append("count %d (tentacles %d)" % [anchors.size(), tents.size()])
	var reach: Dictionary = _reach(td)
	var per: Dictionary = {}
	var out: Array = []
	for a: Dictionary in anchors:
		var cells: Array = StoryGen.anchor_cells(a["cell"])
		per[int(a["tentacle"])] = int(per.get(int(a["tentacle"]), 0)) + 1
		for c: Vector2i in cells:
			if td.get_resourcev(c) != AnchorData.TILE_ID:
				problems.append("anchor %d cell %s is not an anchor tile" % [a["id"], c])
			if reach.has(c):
				problems.append("anchor %d cell %s in a swing" % [a["id"], c])
			for col in LavaData.BOSS_CHAMBER_ENTRY:
				if c.y >= int(ocean["bottom"]) - 6 and absi(c.x - (ch.position.x + int(col))) <= TentData.ENTRY_GAP:
					problems.append("anchor %d by an entry" % a["id"])
		for b: Dictionary in anchors:
			if int(b["id"]) > int(a["id"]):
				var o: Vector2i = b["cell"]
				var p: Vector2i = a["cell"]
				if absi(o.x - p.x) < AnchorData.SIZE + 1 and absi(o.y - p.y) < AnchorData.SIZE + 1:
					problems.append("anchors %d and %d touch" % [a["id"], b["id"]])
		# Reachable: rock within the support distance, or near the tentacle.
		var near_rock: bool = false
		for dy in range(-AnchorData.SUPPORT_TILES, AnchorData.SIZE + AnchorData.SUPPORT_TILES):
			for dx in range(-AnchorData.SUPPORT_TILES, AnchorData.SIZE + AnchorData.SUPPORT_TILES):
				var rc: Vector2i = a["cell"] + Vector2i(dx, dy)
				var id: int = td.get_resourcev(rc)
				if (id != Data.TILE_EMPTY and id != AnchorData.TILE_ID) or td.get_biomev(rc) < 0:
					near_rock = true
		var t: Dictionary = tents[int(a["tentacle"])]
		var gap: float = (absf(float(a["cell"].x) + 0.5 - float(t["x"])) - 1.0) * 24.0 - TentData.WIDTH_BASE * 0.5
		var supported: bool = near_rock or gap <= AnchorData.CLAW_REACH
		if not supported:
			unsupported += 1
		out.append({"id": a["id"], "tentacle": a["tentacle"], "slot": a["slot"], "cell": a["cell"], "seg": a["seg"],
			"rows above base": int(t["base_row"]) - int(a["cell"].y), "tiles out": absi(int(a["cell"].x) - int(t["x"])), "supported": supported,
			"in air": int(a["cell"].y) < int(ocean["top"])})
	for ti in per:
		if int(per[ti]) != AnchorData.PER_TENTACLE:
			problems.append("tentacle %d has %d anchors" % [ti, per[ti]])
	return {"problems": problems, "anchors": out, "unsupported": unsupported}


func _reach(td) -> Dictionary:
	var ocean: Dictionary = td.get_meta("story_ocean", {})
	var rows: Dictionary = ocean["rows"]
	var top: int = int(ocean["top"])
	var ceiling: int = int(ocean["ceiling"])
	var ox0: int = int(ocean["x0"])
	var ox1: int = int(ocean["x1"])
	var in_ocean := func(c: Vector2i) -> bool:
		if c.y > ceiling and c.y < top:
			return c.x >= ox0 and c.x <= ox1
		return rows.has(c.y) and c.x >= int(rows[c.y][0]) and c.x <= int(rows[c.y][1])
	var out: Dictionary = {}
	for p: Dictionary in td.get_meta("story_tentacles", []):
		var fit: Dictionary = StoryGen._fit_tentacle(int(p["x"]), top, int(ocean["bottom"]), int(p["tip_row"]), [], in_ocean)
		for c: Vector2i in fit.get("reach", []):
			out[c] = true
	return out


# The ocean, 8 px a tile.
func _picture(h, td, label: String) -> void:
	var ocean: Dictionary = td.get_meta("story_ocean", {})
	var ch: Rect2i = td.get_meta("story_boss_chamber", Rect2i())
	var x0: int = int(ocean["x0"]) - 2
	var x1: int = int(ocean["x1"]) + 2
	var y0: int = int(ocean["ceiling"]) - 2
	var y1: int = ch.end.y + 3
	var S: int = 8
	var img: Image = Image.create((x1 - x0 + 1) * S, (y1 - y0 + 1) * S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.03, 0.03, 0.05))
	var reach: Dictionary = _reach(td)
	var cols: Dictionary = {}
	for p: Dictionary in td.get_meta("story_tentacles", []):
		for y in range(int(p["tip_row"]), int(p["base_row"])):
			cols[Vector2i(int(p["x"]), y)] = true
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c := Vector2i(x, y)
			if td.get_biomev(c) < 0:
				continue
			var id: int = td.get_resourcev(c)
			var col: Color = Color(0.25, 0.2, 0.28)
			if id == AnchorData.TILE_ID:
				col = Color("6b5cff")
			elif cols.has(c):
				col = Color("8a3fc0")
			elif id == Data.TILE_EMPTY:
				col = Color("e0522a") if y >= int(ocean["top"]) else Color(0.08, 0.08, 0.12)
				if reach.has(c):
					col = col.lerp(Color("ff4fd8"), 0.45)
			img.fill_rect(Rect2i((c - Vector2i(x0, y0)) * S, Vector2i(S, S)), col)
	# Each chain: anchor middle to its attach height on the column.
	var tents: Array = td.get_meta("story_tentacles", [])
	for a: Dictionary in td.get_meta("story_anchors", []):
		var t: Dictionary = tents[int(a["tentacle"])]
		var from := Vector2((float(a["cell"].x) + 1.0 - float(x0)) * S, (float(a["cell"].y) + 1.0 - float(y0)) * S)
		var seg_len: float = (float(int(t["base_row"]) - int(t["tip_row"])) * 24.0 + 8.0 - TentData.PAD_HEIGHT) / float(t["segments"])
		var hy: float = float(int(t["base_row"])) - float(a["seg"]) * seg_len / 24.0
		var to := Vector2((float(t["x"]) + 0.5 - float(x0)) * S, (hy - float(y0)) * S)
		for i in 40:
			var p: Vector2 = from.lerp(to, float(i) / 40.0)
			img.fill_rect(Rect2i(Vector2i(p), Vector2i(2, 2)), Color("b8b0ff"))
	var file: String = "%03d_ocean_%s.png" % [h.shot_index, label]
	h.shot_index += 1
	img.save_png(h.out_dir.path_join(file))
	h.note("picture " + file)
