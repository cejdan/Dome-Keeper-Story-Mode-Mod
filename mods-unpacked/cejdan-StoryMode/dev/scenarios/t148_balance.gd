extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 148: the economy report behind the balance pass. Over generated maps:
# dollars of minerals per biome (tiles x ~2 pieces x value) and running total,
# a medium tile's HP per biome, the keeper's hits per tile at each drill level,
# and what each drill level costs. The tables go into the log for the ticket.

const MapConfig = preload("res://mods-unpacked/cejdan-StoryMode/data/map_config.gd")
const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")

const SEEDS := 10
const TIMEOUT := 600


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	var B: int = MapConfig.BIOMES
	var dollars: Array = []
	var gems: Array = []   # dollars from sapphire and up, per biome
	var mythril: Array = []
	var tiles: Array = []
	for b in B:
		dollars.append(0.0)
		gems.append(0.0)
		mythril.append(0.0)
		tiles.append(0)
	for s in SEEDS:
		var td = h.generate_map(MapConfig.make_archetype(), 7000 + s)
		if td == null:
			continue
		var o: Dictionary = td.get_meta("story_ocean", {})
		for c: Vector2i in td.get_used_biome_cells():
			if not o.is_empty() and c.y >= int(o["ceiling"]):
				continue
			var b: int = td.get_biomev(c)
			if b < 0 or b >= B:
				continue
			tiles[b] += 1
			var r: int = td.get_resourcev(c)
			var m: String = Minerals.by_tile_id(r) if (r >= 40 or r == Data.TILE_IRON) else ""
			if m == "" or m == "unobtainium":
				continue
			var v: float = 2.0 * Minerals.value_of(m)
			dollars[b] += v
			if Minerals.ORDER.find(m) >= Minerals.ORDER.find("sapphire"):
				gems[b] += v
			if m == "mythril":
				mythril[b] += v
		td.queue_free()
		await h.frames(1)
	var per: float = Data.of("map.tileHealthMultiplierPerLayer")
	h.set_inv("money", 1000000)
	var strength: Array = [Data.of("player1.keeper1.drillStrength")]
	var paid: Array = [0]
	for id: String in ["drill1", "drill2", "drill3", "drill4", "drill4", "drill4"]:
		var m0: int = h.inv("money")
		await h.buy(id)
		paid.append(m0 - h.inv("money"))
		strength.append(Data.of("player1.keeper1.drillStrength"))
	var rows: Array = []
	var running: float = 0.0
	for b in B:
		running += dollars[b] / SEEDS
		var hp: float = 10.0 * 2.0 / 2.0 * pow(per, b)   # (3 + 2) x medium 2 x per^b
		var hits: Array = strength.map(func(st): return snappedf(hp / st, 0.1))
		rows.append({"biome": "B%d" % (b + 1), "tiles": tiles[b] / SEEDS, "$ in minerals": int(dollars[b] / SEEDS), "of it gems $": int(gems[b] / SEEDS),
			"of it mythril $": int(mythril[b] / SEEDS), "running $": int(running), "medium mineral HP": snappedf(hp, 0.1), "hits per tile at drill 0..6": hits})
	for r in rows:
		h.note(r["biome"], r)
	h.note("drill ladder", {"price per level 1..6": paid.slice(1), "strength 0..6": strength, "tile HP growth per biome": per})
	h.check("report written", rows.size() == B)
