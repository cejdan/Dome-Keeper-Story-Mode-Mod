extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 133: how much money a player can mine above the gate (B1 to B3), so the
# Blast Suit's price can be sized against it. Over 12 seeds, sums every ore
# tile above the gate at its value x its richness (vanilla drops richness
# pieces per tile on average), plus the B1 to B3 bones, and reports the gold
# within GOLD_ROWS rows above the gate. Checks the gate gold (#133) is placed
# on every seed. Checks the suit stays reachable: its
# price is at most REACH of the poorest seed's above-gate money.

const MapConfig = preload("res://mods-unpacked/cejdan-StoryMode/data/map_config.gd")
const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")
const Bones = preload("res://mods-unpacked/cejdan-StoryMode/data/bones.gd")
const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")

const SEEDS := 12
const GOLD_ROWS := 12
# The suit should cost no more than this share of what the worst seed offers
# above the gate (the rest pays for the drill and jetpack and a first gadget).
const REACH := 0.4


func boot() -> Dictionary:
	return {"seed": 12345}


func _suit_price() -> int:
	var u = Data.upgrades.get("storysuitblaster", {})
	var c = u.get("cost", {})
	return int(c.get("money", -1)) if c is Dictionary else -1


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	var rows: Array = []
	var worst: int = 1 << 30
	var bad_gold: Array = []
	for s in SEEDS:
		var td = h.generate_map(MapConfig.make_archetype(), 7000 + s)
		if td == null:
			continue
		var gate_top: Dictionary = {}   # x -> shallowest gate metal row
		for c: Vector2i in td.get_resource_cells_by_id(Metal.GATE_ID):
			gate_top[c.x] = mini(int(gate_top.get(c.x, 1 << 20)), c.y)
		var by_biome: Array = [0, 0, 0]
		var by_mineral: Dictionary = {}
		var gold_near: int = 0
		for m: String in Minerals.ORDER:
			var t: Dictionary = Minerals.TABLE[m]
			for c: Vector2i in td.get_resource_cells_by_id(int(t["tile_id"])):
				var b: int = td.get_biomev(c)
				if b < 0 or b > MapConfig.GATE_BELOW_BIOME:
					continue
				var v: int = int(round(int(t["value"]) * float(t["richness"])))
				by_biome[b] += v
				by_mineral[m] = int(by_mineral.get(m, 0)) + v
				if m == "gold" and gate_top.has(c.x) and int(gate_top[c.x]) - c.y <= GOLD_ROWS:
					gold_near += 1
		var gg: Array = td.get_meta("story_gate_gold", [])
		var gg_ok: bool = gg.size() == MapConfig.GATE_GOLD_DEPOSITS
		for p: Array in gg:
			gg_ok = gg_ok and int(p[2]) >= int(MapConfig.GATE_GOLD_SIZE[0]) and gate_top.has(int(p[0])) and int(gate_top[int(p[0])]) - int(p[1]) <= MapConfig.GATE_GOLD_ROWS
		if not gg_ok:
			bad_gold.append([7000 + s, gg])
		var bones: int = Bones.value_for(0) + Bones.value_for(1) + Bones.value_for(2)
		var total: int = by_biome[0] + by_biome[1] + by_biome[2] + bones
		worst = mini(worst, total)
		rows.append({"seed": 7000 + s, "total": total, "B1": by_biome[0], "B2": by_biome[1], "B3": by_biome[2], "bones": bones, "by_mineral": by_mineral, "gold_tiles_near_gate": gold_near})
		td.queue_free()
		await h.frames(1)
	var totals: Array = rows.map(func(r): return int(r["total"]))
	totals.sort()
	h.note("money above the gate", {"seeds": rows, "sorted_totals": totals, "suit_price": _suit_price()})
	h.check("every seed has %d gold deposits of %d+ tiles within %d rows above the gate" % [MapConfig.GATE_GOLD_DEPOSITS, MapConfig.GATE_GOLD_SIZE[0], MapConfig.GATE_GOLD_ROWS], bad_gold.is_empty(), bad_gold)
	var price: int = _suit_price()
	h.check("Blast Suit $%d is at most %d%% of the poorest seed's $%d above the gate" % [price, int(REACH * 100), worst], price > 0 and price <= worst * REACH, {"price": price, "worst": worst, "median": totals[totals.size() / 2] if totals.size() else 0})
