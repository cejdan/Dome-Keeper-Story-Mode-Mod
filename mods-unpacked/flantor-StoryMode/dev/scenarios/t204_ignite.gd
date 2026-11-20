extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 204: lava ignites gas. A long room; at its right end the ceiling
# runs on over a pit of lava. Gas let out at the left end spreads along the
# ceiling, reaches the lava and catches; the fire races back through the
# whole cloud and uses it up. The keeper, inside the cloud, takes suit heat
# and no more toxin. No rock breaks; the lava is unchanged.
#
#   ................      the ceiling row runs over the pit      y 0
#   ............#LLL      L lava in its pit                      y 1
#   ............####      the room                               y 1..2
#   ############

const TIMEOUT := 300

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
	for y in range(oy - 3, oy + 6):
		for x in range(ox - 2, ox + 18):
			var c := Vector2i(x, y)
			if td.get_biomev(c) < 0 or td.get_resourcev(c) == Data.TILE_EMPTY or td.get_resourcev(c) == Data.TILE_BORDER or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE:
				return false
	return true


func _rock_count() -> int:
	var n := 0
	for y in range(-3, 6):
		for x in range(-2, 18):
			if not Level.map.is_tile_empty(_c(x, y)):
				n += 1
	return n


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
	for oy in range(20, 110):
		for ox in range(-40, 30):
			if not found and _fits(ox, oy):
				OX = ox
				OY = oy
				found = true
	h.check("found solid rock for the cavern", found, [OX, OY])
	var around: Array = []
	for y in range(-3, 6):
		for x in range(-2, 18):
			around.append(_c(x, y))
			td.set_resourcev(_c(x, y), Data.TILE_DIRT_START)
	await h.reveal(around)
	var open: Array = []
	for x in 16:
		open.append(_c(x, 0))
	for x in 12:
		open.append(_c(x, 1))
		open.append(_c(x, 2))
	var pit: Array = [_c(13, 1), _c(14, 1), _c(15, 1)]
	await h.clear_tiles(open + pit)
	await h.teleport_tile(_c(8, 1))
	h.keeper().set("gravity_scale", 0.0)
	h.snap_camera()
	await h.wait(3.0)
	h.snap_camera()

	# Gas in the room's upper two rows, held still short of the pit for now.
	var gas_cells: Array = []
	for x in 12:
		gas_cells.append(_c(x, 0))
		gas_cells.append(_c(x, 1))
	field.freeze_flow = true
	field.freeze_toxin = true
	field.fill(gas_cells, 1.0)
	for c in pit:
		lava.mass[c] = 1.0
		lava.shown[c] = 1.0
	lava.wake_all()
	var lava_before: float = lava.stats()["total"]
	var rock_before: int = _rock_count()
	var gas_before: float = field.total()
	await h.wait(2.0)
	await h.shot("gas_and_lava")
	h.check("nothing burns while the gas is away from the lava", field.fire.is_empty() and field.ignitions == 0, field.stats())
	var heat_before: float = lava.heat
	var recalls_before: int = lava.recalls
	h.check("the keeper waits in the cloud", h.keeper_tile() == _c(8, 1) and field.gassed == 0, h.keeper_tile())

	# The gas reaches over the pit.
	field.freeze_flow = false
	field.fill([_c(12, 0), _c(13, 0)], 1.0)
	var lit: bool = await h.until(func(): return field.ignitions > 0, 5.0)
	h.check("gas over the lava catches fire", lit, field.stats())
	var peak_heat := 0.0
	for i in 40:
		await h.shot_quiet("fire", i) if h.has_method("shot_quiet") else await h.burst("fire_%02d" % i, 1, 3)
		peak_heat = maxf(peak_heat, lava.heat)
	var out: bool = await h.until(func(): return field.fire.is_empty(), 20.0)
	await h.shot("burnt_out")
	var st: Dictionary = field.stats()
	h.note("after the fire", st)
	h.check("the fire burnt out", out, st)
	h.check("the fire ran through the whole cloud", float(st["burned"]) > 0.85 * (gas_before + 2.0) and float(st["total"]) < 0.1 * gas_before, [st["burned"], gas_before, st["total"]])
	h.check("the keeper in the fire took suit heat", peak_heat > heat_before + 15.0 or lava.recalls > recalls_before, [heat_before, peak_heat, lava.recalls - recalls_before])
	h.check("no rock broke", _rock_count() == rock_before, [rock_before, _rock_count()])
	h.check("the lava is as it was", absf(float(lava.stats()["total"]) - lava_before) < 0.3, [lava_before, lava.stats()["total"]])
	var GasSfx = load("res://mods-unpacked/flantor-StoryMode/gas/gas_sfx.gd")
	h.check("the fire roared", int(GasSfx.played.get("ignite", 0)) >= 1, GasSfx.played)

	# Burning gas is not breathed: toxin only from gas that is not on fire.
	field.freeze_toxin = false
	field.toxin = 0.0
	field.freeze_flow = true
	await h.teleport_tile(_c(4, 1))
	h.keeper().set("gravity_scale", 0.0)
	field.fill([_c(3, 1), _c(4, 1), _c(5, 1), _c(3, 0), _c(4, 0), _c(5, 0)], 1.0)
	field.ignite(_c(4, 1))
	await h.wait(0.3)
	h.check("the keeper breathes no burning gas", field.in_fire and field.toxin < 16.0, [field.in_fire, field.toxin])
