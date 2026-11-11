extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 21: the metal gate on the B3/B4 boundary. A 50-seed report checks
# that nothing below the gate can be reached from above without crossing
# metal; then, in the running game, one base Suit Blaster blast opens a way.

const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")
const MapConfig = preload("res://mods-unpacked/cejdan-StoryMode/data/map_config.gd")
const T17 = preload("res://mods-unpacked/cejdan-StoryMode/dev/scenarios/t17_report.gd")

const SEEDS: int = 50
const DIRS4: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIRS8: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]


func boot() -> Dictionary:
	return {"seed": 12345}


func _colors() -> Dictionary:
	var c: Dictionary = T17.colors()
	c[Metal.GATE_ID] = Color("#e8f0ff")
	c[Metal.TILE_ID] = Color("#a9b4c2")
	return c


# Cells below the gate reachable from the top without crossing gate metal or
# the border. `dirs` 4 = how the keeper moves; 8 = also squeezing diagonally.
func _leaks(td, dirs: Array) -> int:
	var above: int = MapConfig.GATE_BELOW_BIOME
	var seen: Dictionary = {}
	var open: Array = []
	for c: Vector2i in td.get_used_biome_cells():
		if td.get_biomev(c) <= above and td.get_resourcev(c) != Metal.GATE_ID and td.get_resourcev(c) != Data.TILE_BORDER:
			seen[c] = true
			open.append(c)
	var leaks: int = 0
	while open.size() > 0:
		var c: Vector2i = open.pop_back()
		if td.get_biomev(c) > above:
			leaks += 1
		for d: Vector2i in dirs:
			var n: Vector2i = c + d
			if seen.has(n) or td.get_biomev(n) < 0:
				continue
			var r: int = td.get_resourcev(n)
			if r == Metal.GATE_ID or r == Data.TILE_BORDER:
				continue
			seen[n] = true
			open.append(n)
	return leaks


func run(h) -> void:
	h.disable_waves()
	var failed: int = 0
	var leaks4: int = 0
	var leaks8: int = 0
	var gate_cells: int = 0
	var thin: int = 0
	var replaced: Dictionary = {}
	var moved: int = 0
	var lost: int = 0
	for s in SEEDS:
		var td = h.generate_map(MapConfig.make_archetype(), 1000 + s)
		if td == null:
			failed += 1
			continue
		var gate: Array = td.get_resource_cells_by_id(Metal.GATE_ID)
		gate_cells += gate.size()
		# Every gate cell sits in B4 or deeper.
		for c: Vector2i in gate:
			if td.get_biomev(c) <= MapConfig.GATE_BELOW_BIOME:
				thin += 1
		leaks4 += _leaks(td, DIRS4)
		leaks8 += _leaks(td, DIRS8)
		moved += int(td.get_meta("gate_moved", 0))
		lost += int(td.get_meta("gate_lost", 0))
		var rep: Dictionary = td.get_meta("gate_replaced", {})
		for k in rep:
			replaced[str(k)] = replaced.get(str(k), 0) + rep[k]
		if s < 2:
			h.map_png("gate_seed%d" % (1000 + s), _colors(), 6, td)
		td.queue_free()
		await h.frames(1)
	var n: int = SEEDS - failed
	h.check("all %d seeds generated" % SEEDS, failed == 0, failed)
	h.check("no path below the gate without crossing metal (4-way moves), 50 seeds", leaks4 == 0, leaks4)
	h.note("diagonal squeeze leaks (8-way, stricter than the keeper can move)", leaks8)
	h.check("every gate cell is below the B3/B4 boundary", thin == 0, thin)
	h.check("no relic, power core or chamber tile lost under the gate", lost == 0, {"moved": moved, "lost": lost})
	h.note("gate", {"avg cells per map": gate_cells / float(n), "replaced by resource id (all seeds)": replaced})

	# ---- the running game's gate
	var td2 = Level.map.tileData
	h.map_png("this_run_gate", _colors())
	var gate2: Array = td2.get_resource_cells_by_id(Metal.GATE_ID)
	h.check("the run's map has a gate", gate2.size() > 40, gate2.size())
	# Topmost gate cell in column x = 2.
	var x: int = 2
	var top: int = 1 << 20
	for c: Vector2i in gate2:
		if c.x == x and c.y < top:
			top = c.y
	var col: Array = []
	for c: Vector2i in gate2:
		if c.x == x:
			col.append(c.y)
	col.sort()
	h.note("gate column", {"x": x, "ys": col})
	# Look at it from above: dig a room over the gate and reveal around it.
	await h.dig_room(Vector2i(x - 5, top - 4), Vector2i(x + 5, top - 1))
	var around: Array = []
	for yy in range(top - 5, top + 5):
		for xx in range(x - 9, x + 10):
			around.append(Vector2i(xx, yy))
	await h.reveal(around)
	await h.teleport_tile(Vector2i(x, top - 1))
	await h.wait(8.0)
	await h.shot("gate_from_above")

	# Drilling does nothing.
	await h.hold("ui_down", 4.0)
	h.check("drilling the gate does nothing", td2.get_resourcev(Vector2i(x, top)) == Metal.GATE_ID)

	# One base blast.
	GameWorld.serverAddUpgrade("player1.suitblaster", "team1")
	await h.wait(1.0)
	Data.apply("player1.suitblaster.charge", 1.0)
	await h.teleport_tile(Vector2i(x, top - 1))
	await h.wait(1.0)
	await h.press("keeper_gadget1")
	await h.burst("blast", 16, 3)
	await h.wait(2.5)
	await h.shot("after_blast")
	var left: Array = []
	for y in col:
		if td2.get_resourcev(Vector2i(x, y)) == Metal.GATE_ID:
			left.append(y)
	h.check("one base blast clears the gate in the keeper's column", left.is_empty(), {"column": col, "still metal": left})
	# Through: drill on down past the gate (B4 rock is slow with the base drill).
	var below: Vector2i = Vector2i(x, int(col.back()) + 1)
	h.check("under the gate is plain rock, not metal", not Metal.is_metal_id(td2.get_resourcev(below)), td2.get_resourcev(below))
	await h.hold("ui_down", 28.0)
	var kt: Vector2i = h.keeper_tile()
	h.check("the keeper gets below the gate", kt.y > int(col.back()), {"keeper": kt, "gate bottom": col.back()})
	await h.shot("below_gate")
	h.snap("end", [])
	var bt = Level.map.getTile(Vector2(below))
	h.note("tile under gate", {"exists": bt != null, "type": bt.type if bt else "", "health": bt.health if bt else -1, "max": bt.max_health if bt else -1, "hardness": bt.hardness if bt else -1, "drill": Data.ofOr("player1.keeper.drillstrength", Data.ofOr("keeper1.drillStrength", -1))})
