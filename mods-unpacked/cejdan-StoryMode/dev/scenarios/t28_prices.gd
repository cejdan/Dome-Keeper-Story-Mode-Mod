extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 28: every Story Mode upgrade priced in dollars (the #27 tables in
# data/prices.gd), water and cobalt kept, tile HP per the #35 rule, and drill4
# repeats.

const Prices = preload("res://mods-unpacked/cejdan-StoryMode/data/prices.gd")
const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


func _short(id: String) -> String:
	var i: int = id.find(".")
	return id.substr(i + 1) if i >= 0 else id


func run(h) -> void:
	h.disable_waves()
	# ---- prices on every upgrade in the run
	var iron: Array = []
	var wrong: Array = []
	var lost_extra: Array = []
	var checked: int = 0
	for id: String in GameWorld.upgrades:
		var cost = GameWorld.upgrades[id].get("cost", {})
		if not cost is Dictionary:
			continue
		if cost.has("iron"):
			iron.append(id)
		var k: String = _short(id)
		var orig: Dictionary = Prices._vanilla.get(k, {}).get("cost", {})
		if orig.has("iron"):
			checked += 1
			var want: int = int(Prices.PRICES.get(k, int(orig["iron"]) * Prices.DEFAULT_RATE))
			# Bought repeatables have moved on; compare only unbought ones.
			if not GameWorld.boughtUpgrades.has(id) and int(cost.get("money", -1)) != want:
				wrong.append([id, cost, want])
		for extra: String in ["water", "sand"]:
			if orig.has(extra) and int(cost.get(extra, -1)) != int(orig[extra]):
				lost_extra.append([id, extra, cost])
	h.check("no upgrade in a Story Mode run costs iron", iron.is_empty(), iron)
	h.check("every former iron cost is its table price (%d checked)" % checked, wrong.is_empty() and checked >= 30, wrong)
	h.check("water and cobalt costs stay vanilla", lost_extra.is_empty(), lost_extra)
	for id_price: Array in [["drill1", 4], ["drill3", 200], ["jetpackstrength3", 170], ["laserstrength4", 6300], ["lasermove3", 4000],
			["dome1health2", 280], ["laseraimline", 7], ["domehealthmeter", 2], ["domewavemeter", 4], ["laserbend", 450],
			["laserhitprojectiles", 10000], ["domesupplementresurrection2", 950], ["shieldovercharge", 30], ["repellentdelay3", 280]]:
		var u: Dictionary = GameWorld.upgrades.get("team1." + id_price[0], GameWorld.upgrades.get("player1." + id_price[0], {}))
		if u.is_empty():
			h.note("not in this run's shop", id_price[0])
			continue
		h.check("%s is $%d" % id_price, int(u.get("cost", {}).get("money", -1)) == id_price[1], u.get("cost", {}))

	# Tech tree screenshots, scrolled through.
	h.set_inv("money", 50000)
	h.set_inv("water", 10)
	h.set_inv("sand", 10)
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	await h.shot("tree_top")
	for i in 4:
		for j in 3:
			await h.press("ui_down")
			await h.wait(0.2)
		await h.shot("tree_down_%d" % i)
	await h.press("ui_cancel")
	await h.wait(1.0)

	# ---- tile HP: medium-hardness tiles of each mineral and of rock, per biome
	var td = Level.map.tileData
	var base: float = Data.of("map.tileBaseHealth")
	var mult2: float = Data.of("map.hardnessMultiplier2")
	var per: float = Data.of("map.tileHealthMultiplierPerLayer")
	h.note("health rule", {"base": base, "medium": mult2, "per biome": per})
	var found: Dictionary = {}  # "type@biome" -> cell
	for c: Vector2i in td.get_used_biome_cells():
		if td.get_hardnessv(c) != 2:
			continue
		var r: int = td.get_resourcev(c)
		var type: String = "rock" if r == Data.TILE_DIRT_START else Minerals.by_tile_id(r) if (r >= 40 or r == Data.TILE_IRON) else ""
		if type == "":
			continue
		var key: String = "%s@%d" % [type, td.get_biomev(c)]
		if not found.has(key):
			found[key] = c
	var cells: Array = found.values()
	await h.reveal(cells)
	var bad: Array = []
	var rows: Dictionary = {}
	for key: String in found:
		var t = Level.map.getTile(Vector2(found[key]))
		if t == null:
			continue
		var b: int = td.get_biomev(found[key])
		var extra: float = 0.0 if key.begins_with("rock") else 2.0
		var want: int = int(round((base + extra) * mult2 * pow(per, b)))
		rows[key] = [t.max_health, want]
		if t.max_health != want:
			bad.append([key, t.max_health, want])
	h.note("tile max_health [got, want] by type@biome index", rows)
	h.check("tile HP matches round((3 + 2) x 2 x 2.1^(biome - 1)) and rock round(3 x 2 x 2.1^(biome - 1)) (%d samples)" % rows.size(), bad.is_empty() and rows.size() >= 20, bad)

	# ---- drill4 repeats
	h.set_inv("money", 100000)
	for id: String in ["drill1", "drill2", "drill3"]:
		await h.buy(id)
	var paid: Array = []
	var strength: Array = [Data.of("player1.keeper1.drillStrength")]
	for i in 3:
		var m0: int = h.inv("money")
		await h.buy("drill4")
		paid.append(m0 - h.inv("money"))
		strength.append(Data.of("player1.keeper1.drillStrength"))
	h.note("drill4", {"paid": paid, "strength": strength})
	h.check("drill4 three times costs $1,400, $9,400, $17,400", paid == [1400, 9400, 17400], paid)
	# Vanilla's repeat rule multiplies drill4's own gain by 3 (+56, +168, +504).
	var gains: Array = [strength[1] - strength[0], strength[2] - strength[1], strength[3] - strength[2]]
	h.check("drill strength gain rises x3 each time", absf(gains[1] - 3 * gains[0]) < 0.01 and absf(gains[2] - 3 * gains[1]) < 0.01, {"strength": strength, "gains": gains})
	h.snap("end", [])
