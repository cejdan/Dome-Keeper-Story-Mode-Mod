extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 212: gas catches under ceilings and in bends. The user's bent passage
# (x rock, o open, g gas), with the way out leading up to a dead-end room
# that catches whatever escapes:
#
#   o o o o o      the catch room                 y -7..-5
#   x o x x x      the way out, up from the bend  y -4..0
#   x o o o x      the bend                       y 1
#   x x x o x      the breach (rock until opened) y 2
#   g g g g x      the pocket                     y 3
#   x x x x x
#
# Before #212 every bit of the pocket's gas left through the bend. Now gas
# resting under a ceiling keeps a layer (CLING_MASS) that does not flow
# sideways, so the pocket's two cells away from the breach keep theirs. Since
# #217 the cell beside the breach spills into it, and the gas that climbs the
# breach into the bend has the momentum to run along the bend's ceiling to the
# way out, so the bend keeps none: the rest leaves, over a few seconds.

const GasData = preload("res://mods-unpacked/flantor-StoryMode/data/gas.gd")
const TIMEOUT := 200

var OX := 0
var OY := 30
var td
var field
var lava


func boot() -> Dictionary:
	return {"seed": 12345}


func _c(x: int, y: int) -> Vector2i:
	return Vector2i(OX + x, OY + y)


func _fits(ox: int, oy: int) -> bool:
	for y in range(oy - 9, oy + 6):
		for x in range(ox - 3, ox + 9):
			var c := Vector2i(x, y)
			if td.get_biomev(c) < 0 or td.get_resourcev(c) == Data.TILE_EMPTY or td.get_resourcev(c) == Data.TILE_BORDER or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE:
				return false
	return true


func _sum(cells: Array) -> float:
	var s := 0.0
	for c in cells:
		s += field.mass.get(c, 0.0)
	return s


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
	var found := false
	for oy in range(25, 110):
		for ox in range(-40, 30):
			if not found and _fits(ox, oy):
				OX = ox
				OY = oy
				found = true
	h.check("found solid rock for the passage", found, [OX, OY])
	var around: Array = []
	for y in range(-9, 6):
		for x in range(-3, 9):
			around.append(_c(x, y))
			td.set_resourcev(_c(x, y), Data.TILE_DIRT_START)
	await h.reveal(around)
	var pocket: Array = [_c(0, 3), _c(1, 3), _c(2, 3), _c(3, 3)]
	var bend: Array = [_c(1, 1), _c(2, 1), _c(3, 1)]
	var way: Array = []
	for y in range(-4, 1):
		way.append(_c(1, y))
	var room: Array = []
	for y in range(-7, -4):
		for x in range(-1, 6):
			room.append(_c(x, y))
	await h.clear_tiles(pocket + bend + way + room)
	# The keeper watches from the catch room.
	await h.teleport_tile(_c(4, -5))
	h.keeper().set("gravity_scale", 0.0)
	h.snap_camera()
	field.fill(pocket, 1.0)
	await h.wait(1.0)
	h.check("the sealed pocket holds its gas", absf(_sum(pocket) - 4.0) < 0.01, _sum(pocket))
	var lava_cool := func(): lava.heat = 0.0
	Level.map.get_tree().process_frame.connect(lava_cool)
	await h.shot("sealed")

	# ---- the breach
	await h.clear_tiles([_c(3, 2)])
	field.wake_all()
	var t0: float = h.now()
	var out_at := {}
	for t in [3.0, 8.0, 15.0, 30.0, 45.0]:
		await h.wait(t - (h.now() - t0))
		out_at[t] = _sum(way + room)
		if t == 8.0:
			await h.shot("venting_8s")
	var held_pocket: float = _sum(pocket)
	var held_bend: float = _sum(bend + [_c(3, 2)])
	var escaped: float = _sum(way + room)
	h.note("after 45 s", {"pocket": held_pocket, "bend": held_bend, "escaped": escaped, "escaped over time": out_at, "faded": field.faded, "cling": GasData.CLING_MASS})
	await h.shot("after_45s")
	h.check("gas is conserved", absf(field.total() + field.faded + field.vented - 4.0) < 0.01, field.stats())
	h.check("the pocket keeps CLING_MASS in each cell away from the breach", absf(held_pocket - 2.0 * GasData.CLING_MASS) < 0.08 and field.mass.get(_c(2, 3), 0.0) < 0.05, [held_pocket, field.mass.get(_c(2, 3), 0.0)])
	h.check("the bend lets the climbing gas through: it keeps none", held_bend < 0.05, held_bend)
	h.check("the rest escapes", absf(escaped - (4.0 - held_pocket - field.faded)) < 0.05, escaped)
	h.check("not all at once: under three quarters of it in the first 3 s", out_at[3.0] < 0.75 * escaped, out_at)
	h.check("what is held is still toxic", field.mass.get(_c(0, 3), 0.0) >= GasData.TOXIC_MASS and field.mass.get(_c(1, 3), 0.0) >= GasData.TOXIC_MASS, [field.mass.get(_c(0, 3), 0.0), field.mass.get(_c(1, 3), 0.0)])

	# ---- breaking the ceiling over trapped gas lets it rise (into the new
	# dead end above it)
	var under: float = field.mass.get(_c(0, 3), 0.0)
	await h.clear_tiles([_c(0, 2)])
	field.wake_all()
	await h.wait(6.0)
	h.check("opening a ceiling lets the gas under it climb", field.mass.get(_c(0, 3), 0.0) < 0.2 * under and field.mass.get(_c(0, 2), 0.0) > 0.3, [field.mass.get(_c(0, 3), 0.0), field.mass.get(_c(0, 2), 0.0), under])
	await h.shot("ceiling_opened")
