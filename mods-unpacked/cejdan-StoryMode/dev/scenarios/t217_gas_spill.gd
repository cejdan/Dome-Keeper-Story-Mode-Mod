extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 217: clinging gas (#212) spills into an opening beside it that leads
# up, and gas that has climbed carries momentum along the ceiling it hits.
# Four passages side by side in solid rock (x rock, o open, g gas), each with a
# dead-end catch room at the top of its way out:
#
#   A  the user's spill:      B  the user's stuck:
#      x x o x x                 x x o x x x
#      x x o g x                 x x o o g x
#      x x x x x                 x x x x x x
#
#   C  a tall shaft into a ceiling, the way up 4 cells along it:
#      x o x x x x
#      x o o o o o      <- the ceiling row, y 0
#      x x x x x o
#      x x x x x o      (the shaft, 6 tall)
#      x x x x x g      <- the gas starts at its bottom
#
#   D  the same ceiling with no shaft: the gas starts in the ceiling row's
#      right end, with no climb behind it.
#   E  the same ceiling over a shaft only 2 tall: a short climb, a short run.

const GasData = preload("res://mods-unpacked/cejdan-StoryMode/data/gas.gd")
const TIMEOUT := 200
# Each passage gets its own patch of solid rock; _c(x, y) is in passage P's.
var ORIG: Array = []
var P := 0
var td
var field
var lava


func boot() -> Dictionary:
	return {"seed": 12345}


func _c(x: int, y: int) -> Vector2i:
	return ORIG[P] + Vector2i(x, y)


func _fits(ox: int, oy: int) -> bool:
	for o in ORIG:
		if absi(o.x - ox) < 12 and absi(o.y - oy) < 20:
			return false
	for y in range(oy - 9, oy + 9):
		for x in range(ox - 3, ox + 8):
			var c := Vector2i(x, y)
			if td.get_biomev(c) < 0 or td.get_resourcev(c) == Data.TILE_EMPTY or td.get_resourcev(c) == Data.TILE_BORDER or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE:
				return false
	return true


func _sum(cells: Array) -> float:
	var s := 0.0
	for c in cells:
		s += field.mass.get(c, 0.0)
	return s


# The way up at column `x` from row -1 to -4, and its catch room.
func _way(x: int) -> Array:
	var cells: Array = []
	for y in range(-4, 0):
		cells.append(_c(x, y))
	for y in range(-7, -4):
		for rx in range(x - 2, x + 3):
			cells.append(_c(rx, y))
	return cells


func run(h) -> void:
	h.disable_waves()
	td = Level.map.tileData
	await h.until(func(): return Level.map.get_node_or_null("StoryGasField") != null, 10.0)
	field = Level.map.get_node("StoryGasField")
	lava = Level.map.get_node("StoryLavaField")
	lava.magma.clear()
	lava.mass.clear()
	lava.shown.clear()
	field.rock.clear()
	field.mass.clear()
	field.freeze_toxin = true
	for i in 5:
		var found := false
		for oy in range(25, 160, 2):
			for ox in range(-60, 50, 2):
				if not found and _fits(ox, oy):
					ORIG.append(Vector2i(ox, oy))
					found = true
	h.check("found solid rock for the passages", ORIG.size() == 5, ORIG)
	var around: Array = []
	for i in 5:
		P = i
		for y in range(-9, 9):
			for x in range(-3, 8):
				around.append(_c(x, y))
				td.set_resourcev(_c(x, y), Data.TILE_DIRT_START)
	await h.reveal(around)

	# A: way up at x 2, gas beside it at x 3.
	P = 0
	var a_way: Array = _way(2) + [_c(2, 0), _c(2, 1)]
	var a_gas := _c(3, 1)
	# B: way up at x 2, (3, 1) under rock, gas at x 4.
	P = 1
	var b_way: Array = _way(2) + [_c(2, 0), _c(2, 1)]
	var b_mid := _c(3, 1)
	var b_gas := _c(4, 1)
	# C and D: ceiling row 0 from x 0..4, the way up at x 0. C has the shaft.
	var c_row: Array = []
	var d_row: Array = []
	var c_shaft: Array = []
	P = 2
	for x in range(0, 5):
		c_row.append(_c(x, 0))
	for y in range(1, 7):
		c_shaft.append(_c(4, y))
	var c_way: Array = _way(0)
	P = 3
	for x in range(0, 5):
		d_row.append(_c(x, 0))
	var d_way: Array = _way(0)
	var e_row: Array = []
	P = 4
	for x in range(0, 5):
		e_row.append(_c(x, 0))
	var e_shaft: Array = [_c(4, 1), _c(4, 2)]
	var e_way: Array = _way(0)
	await h.clear_tiles(a_way + [a_gas] + b_way + [b_mid, b_gas] + c_way + c_row + c_shaft + d_way + d_row + e_way + e_row + e_shaft)
	var lava_cool := func(): lava.heat = 0.0
	Level.map.get_tree().process_frame.connect(lava_cool)
	P = 2
	await h.teleport_tile(_c(1, -6))
	h.keeper().set("gravity_scale", 0.0)
	h.snap_camera()
	await h.wait(0.5)

	field.fill([a_gas], 1.0)
	field.fill([b_gas], 1.0)
	field.fill([c_shaft[-1]], 1.0)
	field.fill([d_row[-1]], 1.0)
	field.fill([e_shaft[-1]], 1.0)
	field.wake_all()
	var seen_rise := 0.0
	var t0: float = h.now()
	while h.now() - t0 < 3.0:
		seen_rise = maxf(seen_rise, field.rise.get(c_row[-1], 0.0))
		await h.frames(1)
	await h.shot("c_splash_3s")
	await h.wait(22.0)
	await h.shot("settled_25s")

	var a_left: float = field.mass.get(a_gas, 0.0)
	var a_escaped: float = _sum(a_way)
	var b_held: float = field.mass.get(b_gas, 0.0)
	var b_middle: float = field.mass.get(b_mid, 0.0)
	var b_escaped: float = _sum(b_way)
	var c_held: float = _sum(c_row.slice(1)) + _sum(c_shaft)
	var c_escaped: float = _sum(c_way + [c_row[0]])
	var d_held: float = _sum(d_row.slice(1))
	var d_escaped: float = _sum(d_way + [d_row[0]])
	var e_held: float = _sum(e_row.slice(1)) + _sum(e_shaft)
	var e_escaped: float = _sum(e_way + [e_row[0]])
	h.note("after 25 s", {
		"A spill: left in place": a_left, "A escaped": a_escaped,
		"B stuck: held": b_held, "B middle": b_middle, "B escaped": b_escaped,
		"C shaft: held": c_held, "C escaped": c_escaped, "C row": c_row.map(func(c): return snappedf(field.mass.get(c, 0.0), 0.01)), "C top momentum seen": seen_rise,
		"D no climb: held": d_held, "D escaped": d_escaped, "D row": d_row.map(func(c): return snappedf(field.mass.get(c, 0.0), 0.01)),
		"E short climb: held": e_held, "E escaped": e_escaped, "E row": e_row.map(func(c): return snappedf(field.mass.get(c, 0.0), 0.01)),
		"faded": field.faded, "rise left": field.rise.size()})
	h.check("gas is conserved", absf(field.total() + field.faded + field.vented - 5.0) < 0.01, field.stats())
	h.check("A: gas under rock beside a way up spills out of it", a_left < 0.03 and a_escaped > 0.9, [a_left, a_escaped])
	h.check("B: one cell further along, it sticks (about CLING_MASS)", absf(b_held - GasData.CLING_MASS) < 0.06 and b_middle < 0.03, [b_held, b_middle])
	h.check("B: the rest gets out (some of it thins away in the catch room)", b_escaped > 0.3, [b_escaped, field.faded])
	h.check("C: the gas reached the ceiling with momentum", seen_rise >= 3.0, seen_rise)
	h.check("D: with no climb behind it, the ceiling holds nearly all of it", d_escaped < 0.1, [d_held, d_escaped])
	h.check("C: after a tall climb, more than half splashes along to the way up", c_escaped > 0.5, [c_held, c_escaped])
	h.check("E: after a short climb it runs a short way and clings", e_escaped < 0.1 and e_held > 0.8, [e_held, e_escaped])
	h.check("C: momentum is spent: what is left clings and stays", field.rise.size() == 0 or field.rise.values().max() < 0.05, field.rise.values())

	# Still-clinging gas stays put: nothing more leaves in another 10 s.
	var before: float = c_escaped + d_escaped + b_escaped
	await h.wait(10.0)
	var after: float = _sum(c_way + [c_row[0]]) + _sum(d_way + [d_row[0]]) + _sum(b_way)
	h.check("what clings stays clung", absf(after - before) < 0.02, [before, after])
