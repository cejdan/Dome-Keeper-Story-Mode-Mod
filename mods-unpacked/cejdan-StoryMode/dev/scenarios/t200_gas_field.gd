extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 200: the gas field. Hidden pockets sit from B2 down; a breached pocket
# bursts and its gas climbs a dug shaft, is held by an upward dead end, and is
# let out by a vent drilled above it; gas is conserved apart from venting and
# fading; a settled field sleeps; the gas survives a save and reload.
#
#   ...##...........      an alcove in the ceiling (a trap)   y -1
#   ................      the room                            y 0..2
#   ########.#######      the shaft                           y 3..5
#   #GGG####.#######      G gas rock (the pocket)             y 4..5
#   #GGG.....#######

const GasData = preload("res://mods-unpacked/cejdan-StoryMode/data/gas.gd")
const SLOT := 11
const TIMEOUT := 480

var OX := 0
var OY := 30
var td
var field


func boot() -> Dictionary:
	return {"seed": 12345}


func _c(x: int, y: int) -> Vector2i:
	return Vector2i(OX + x, OY + y)


func _fits(ox: int, oy: int) -> bool:
	for y in range(oy - 3, oy + 8):
		for x in range(ox - 2, ox + 18):
			var c := Vector2i(x, y)
			if td.get_biomev(c) < 0 or td.get_resourcev(c) == Data.TILE_EMPTY or td.get_resourcev(c) == Data.TILE_BORDER or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE:
				return false
	return true


func _accounted() -> float:
	return field.total() + field.vented + field.faded


func run(h) -> void:
	h.disable_waves()
	td = Level.map.tileData
	await h.until(func(): return Level.map.get_node_or_null("StoryGasField") != null, 10.0)
	field = Level.map.get_node_or_null("StoryGasField")
	h.check("the run has a gas field", field != null)
	var lava = Level.map.get_node("StoryLavaField")

	# ---- 1. the pockets the run starts with
	var shallow := 0
	var on_magma := 0
	var by_biome := {}
	for c in field.rock:
		var b: int = td.get_biomev(c)
		by_biome[b] = by_biome.get(b, 0) + 1
		if b < 1:
			shallow += 1
		if lava.magma.has(c):
			on_magma += 1
	h.note("gas rock by biome", by_biome)
	h.check("the map has hidden gas pockets", field.rock.size() > 20, field.rock.size())
	h.check("no gas rock above B2", shallow == 0, shallow)
	h.check("no gas rock on magma", on_magma == 0, on_magma)
	h.check("gas rock down to B8", by_biome.has(7), by_biome)
	var in_caverns := 0
	for cv in field.caverns:
		in_caverns += cv.size()
	h.check("no gas before any breach, outside the sealed caverns", field.mass.size() == in_caverns and field.stats()["awake"] == 0, field.stats())
	var kt: Vector2i = h.keeper_tile()
	var sky := {}
	for y in range(-2, 3):
		var row := ""
		for x in range(kt.x - 6, kt.x + 7):
			var c := Vector2i(x, y)
			row += "S" if field._is_sky(c) else ("." if Level.map.is_tile_empty(c) else "#")
		sky[y] = row
	h.note("the surface around the keeper (S sky, . open, # rock)", {"keeper": kt, "rows": sky})

	# ---- 2. a cavern of its own, with a pocket
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
	for y in range(-3, 8):
		for x in range(-2, 18):
			around.append(_c(x, y))
			td.set_resourcev(_c(x, y), Data.TILE_DIRT_START)
	await h.reveal(around)
	var open: Array = [_c(3, -1), _c(4, -1)]
	for x in 16:
		for y in 3:
			open.append(_c(x, y))
	for y in range(3, 6):
		open.append(_c(8, y))
	for x in range(4, 8):
		open.append(_c(x, 5))
	await h.clear_tiles(open)
	var pocket: Array = []
	for x in range(1, 4):
		for y in range(4, 6):
			pocket.append(_c(x, y))
	field.add_pocket(pocket)
	await h.teleport_tile(_c(10, 2))
	h.keeper().set("gravity_scale", 0.0)
	h.snap_camera()
	await h.wait(3.0)
	h.snap_camera()
	await h.shot("pocket_sealed")

	# ---- 3. the breach: one cell is broken, the pocket bursts
	var volume: float = 3.0 * pocket.size()
	Level.map.destroyTile("team1", "", Level.map.getTile(Vector2(_c(3, 5))))
	await h.wait(0.4)
	await h.shot("burst")
	await h.wait(1.6)
	h.check("the whole pocket burst", field.breaches == pocket.size() and field.rock.is_empty(), field.stats())
	await h.shot("climbing")
	h.check("gas is conserved while it flows", absf(_accounted() - volume) < 0.01, [_accounted(), volume])

	# ---- 4. it settles under the ceiling and the field sleeps
	var slept: bool = await h.until(func(): return field.stats()["awake"] == 0 and field.sources.is_empty(), 180.0)
	h.check("the settled field sleeps", slept, field.stats())
	await h.shot("settled")
	# The pocket's own top row is a dead end too, and keeps a cell of gas each.
	# The corridor's low ceiling keeps a clinging layer (#212), except its
	# last cell, beside the shaft, which spills into it (#217); the shaft,
	# which climbs, keeps none.
	var held := 0.0
	var corridor := 0.0
	var in_shaft := 0.0
	var room := 0.0
	for c in field.mass:
		if c.y == OY + 4 and c.x <= OX + 3:
			held += field.mass[c]
		elif c.y == OY + 5 and c.x >= OX + 4 and c.x <= OX + 7:
			corridor += field.mass[c]
		elif c.x == OX + 8 and c.y >= OY + 3:
			in_shaft += field.mass[c]
		elif c.y <= OY + 2:
			room += field.mass[c]
	h.note("where the gas settled", {"pocket top": held, "corridor": corridor, "shaft": in_shaft, "room": room, "total": field.total()})
	h.check("the shaft is clear", in_shaft < 0.05, in_shaft)
	h.check("the corridor's ceiling holds a clinging layer, about CLING_MASS a cell, bar the cell beside the shaft", corridor > 2.6 * GasData.CLING_MASS and corridor < 3.4 * GasData.CLING_MASS and field.mass.get(_c(7, 5), 0.0) < 0.05, [corridor, field.mass.get(_c(7, 5), 0.0)])
	h.check("the pocket's top row holds about a cell of gas each", held > 2.5 and held < 4.0, held)
	h.check("the alcove is full", field.mass.get(_c(3, -1), 0.0) >= 0.95 and field.mass.get(_c(4, -1), 0.0) >= 0.95, [field.mass.get(_c(3, -1), 0.0), field.mass.get(_c(4, -1), 0.0)])
	var top := 0.0
	for x in 16:
		top += field.mass.get(_c(x, 0), 0.0)
	h.check("the room's gas lies under its ceiling", top > 0.6 * (room - 2.0), [top, room])
	h.check("gas is conserved once settled", absf(_accounted() - volume) < 0.01, [_accounted(), volume])
	h.check("little faded", field.faded < 0.1 * volume, field.faded)
	var t0: int = field.phys_us
	var f0: int = field.phys_frames
	await h.wait(2.0)
	h.note("settled field cost, ms a physics frame", float(field.phys_us - t0) / 1000.0 / maxi(field.phys_frames - f0, 1))

	# ---- 5. save and reload: the same gas comes back
	var before: Dictionary = field.stats()
	var alcove_before: float = field.mass.get(_c(3, -1), 0.0)
	await SaveGame.saveGame(SaveGame.get_run_folder(), SLOT, true)
	await h.wait(1.0)
	h.check("gas went into the save", str(Data.ofOr("story.gas", "")).length() > 10 and str(Data.serialize()).find("story.gas") >= 0)
	GameWorld.paused = true
	Level.map.remove_child(field)
	field.queue_free()
	GameWorld.paused = false
	await h.until(func(): return Level.map.get_node_or_null("StoryGasField") != null, 10.0)
	var f2 = Level.map.get_node_or_null("StoryGasField")
	h.check("a new gas field came up", f2 != null and f2 != field)
	field = f2
	await h.wait(0.5)
	var after: Dictionary = field.stats()
	h.check("same gas after the reload", int(after["cells"]) == int(before["cells"]) and absf(float(after["total"]) - float(before["total"])) < 0.01, [before, after])
	h.check("the alcove's gas came back", absf(field.mass.get(_c(3, -1), 0.0) - alcove_before) < 0.001)
	h.check("no pockets came back", field.rock.is_empty() and field.breaches == pocket.size(), after)

	# ---- 6. a vent drilled above the alcove lets its gas out
	await h.clear_tiles([_c(3, -2)])
	field.wake_all()
	await h.wait(4.0)
	h.check("the vent cell took the alcove's gas", field.mass.get(_c(3, -2), 0.0) > 0.5, field.mass.get(_c(3, -2), 0.0))
	await h.shot("vent_open")

	# ---- 7. the surface: gas in a shaft that reaches open sky leaves the mine
	var col := -999
	for x in range(kt.x - 3, kt.x + 9):
		if col == -999 and field._is_sky(Vector2i(x, -1)) and not Level.map.is_tile_empty(Vector2i(x, 0)) and td.get_hardnessv(Vector2i(x, 3)) < Data.HARDNESS_INDESTRUCTIBLE:
			col = x
	h.check("found a column under open sky", col != -999, col)
	var shaft: Array = []
	for y in 4:
		shaft.append(Vector2i(col, y))
	await h.reveal(shaft)
	await h.clear_tiles(shaft)
	await h.teleport_tile(Vector2i(col, 3))
	h.check("the shaft is open to the sky", Level.map.is_tile_empty(Vector2i(col, 0)) and field._is_sky(Vector2i(col, -1)), col)
	var had: float = field.total()
	var vented0: float = field.vented
	field.fill([Vector2i(col, 3), Vector2i(col, 2)], 2.0)
	await h.wait(0.15)
	await h.shot("surface_venting")
	await h.wait(10.0)
	h.check("the shaft's gas left through the surface", field.vented - vented0 > 3.9, [field.vented - vented0, field.total() - had])
	h.check("none of it is left in the shaft", field.mass.get(Vector2i(col, 0), 0.0) < 0.01 and field.mass.get(Vector2i(col, 3), 0.0) < 0.01)
	h.check("gas is conserved to the end", absf(_accounted() - volume - 4.0) < 0.02, _accounted())
