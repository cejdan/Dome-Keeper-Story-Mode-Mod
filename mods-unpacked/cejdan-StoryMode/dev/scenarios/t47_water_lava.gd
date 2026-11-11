extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 47: water hardens up to 6 lava cells into mineable rock.

const SLOT := 11


func boot() -> Dictionary:
	return {"seed": 12345}


var field
var td


# Plain rock round `cells`, then opens and fills them (hydrostatic, as pools are).
func _lava(h, cells: Array, air: Array) -> void:
	var top: int = 1 << 20
	for c in cells:
		top = mini(top, c.y)
	var around: Array = []
	for c in cells + air:
		for oy in range(-2, 3):
			for ox in range(-2, 3):
				around.append(c + Vector2i(ox, oy))
	for c in around:
		if td.get_resourcev(c) != Data.TILE_EMPTY:
			td.set_resourcev(c, Data.TILE_DIRT_START)
	await h.reveal(around)
	await h.clear_tiles(cells + air)
	for c in cells:
		field.mass[c] = 1.0 + 0.25 * (c.y - top)
	field.wake_all()


# A column x near the centre where a w-wide strip at row y sits in solid ground
# (no holes, no border within 3 tiles), so lava put there can't drain away.
func _solid_x(y: int, w: int) -> int:
	for dx in range(0, 30):
		for x in [dx, -dx]:
			var ok: bool = true
			for yy in range(y - 4, y + 4):
				for xx in range(x - 3, x + w + 3):
					var c := Vector2i(xx, yy)
					ok = ok and td.get_biomev(c) >= 0 and td.get_resourcev(c) != Data.TILE_EMPTY and td.get_resourcev(c) != Data.TILE_BORDER
			if ok:
				return x
	return 0


func _water(at: Vector2, carried: bool) -> void:
	var d: Dictionary = {"type": CONST.WATER, "position": at, "team": "team1"}
	if carried:
		d["carriers"] = ["player1"]
	Level.drops.network_spawn(d)


func run(h) -> void:
	h.disable_waves()
	field = Level.map.get_node("StoryLavaField")
	td = Level.map.tileData
	field.magma.clear()

	# ---- a lava shaft 1 wide and 8 deep, open above
	var x: int = 8
	var y: int = 16
	var shaft: Array = []
	for i in 8:
		shaft.append(Vector2i(x, y + i))
	var air: Array = []
	for yy in range(y - 4, y):
		for xx in range(x - 1, x + 2):
			air.append(Vector2i(xx, yy))
	await _lava(h, shaft, air)
	await h.teleport_tile(Vector2i(x + 1, y - 2))
	await h.wait(1.5)
	await h.shot("shaft_before")
	var tiles0: int = Level.map.tiles.size()
	var h0: int = field.hardened
	var cells0: int = field.mass.size()
	_water(Level.map.getTilePos(Vector2(x, y - 2)), false)
	await h.until(func(): return field.hardened > h0, 8.0)
	await h.wait(0.3)
	await h.shot("shaft_steam")
	await h.wait(1.5)
	await h.shot("shaft_after")
	var got: Array = field.last_hardened
	h.note("shaft hardening", {"cells": got, "lava cells before": cells0, "after": field.mass.size(), "tiles added": Level.map.tiles.size() - tiles0})
	h.check("one water drop hardens 6 shaft cells", got.size() == 6 and field.hardened - h0 == 6, got)
	h.check("the 6 cells left the lava and became rock tiles", got.all(func(c): return not field.mass.has(c) and td.get_resourcev(c) == Data.TILE_DIRT_START and Level.map.tiles.has(Vector2(c))))
	h.check("the 2 cells below stay lava", field.mass.get(Vector2i(x, y + 6), 0.0) > 0.5 and field.mass.get(Vector2i(x, y + 7), 0.0) > 0.5)
	# The keeper drills into the new rock.
	await h.teleport_tile(Vector2i(x, y - 1))
	await h.hold("ui_down", 8.0)
	h.check("the keeper drills through the new rock", not Level.map.tiles.has(Vector2(x, y)) and not Level.map.tiles.has(Vector2(x, y + 1)))
	await h.shot("shaft_drilled")

	# ---- carried water into a 3 x 3 pool
	var pool: Array = []
	for yy in range(14, 17):
		for xx in range(-14, -11):
			pool.append(Vector2i(xx, yy))
	await _lava(h, pool, [Vector2i(-13, 12), Vector2i(-13, 13), Vector2i(-12, 12), Vector2i(-12, 13)])
	await h.teleport_tile(Vector2i(-13, 12))
	_water(h.keeper().global_position, true)
	await h.wait(1.0)
	var carrying: int = h.keeper().carriedCarryables.size()
	h.check("the keeper carries the water", carrying > 0, carrying)
	var h1: int = field.hardened
	await h.teleport_tile(Vector2i(-13, 15))
	await h.until(func(): return field.hardened > h1, 6.0)
	await h.frames(5)
	h.note("carried water", {"cells": field.last_hardened, "still carried": h.keeper().carriedCarryables.size()})
	h.check("carried water hardens 6 cells around the contact point", field.hardened - h1 == 6, field.last_hardened)
	h.check("and leaves the tether", h.keeper().carriedCarryables.size() == 0)
	var carried_cells: Array = field.last_hardened.duplicate()
	await h.teleport_tile(Vector2i(-13, 12))
	await h.wait(1.0)
	await h.shot("pool_after_carried")

	# ---- only 4 connected cells: 4 harden
	var fx: int = _solid_x(30, 4)
	var four: Array = [Vector2i(fx, 30), Vector2i(fx + 1, 30), Vector2i(fx + 2, 30), Vector2i(fx + 3, 30)]
	await _lava(h, four, [Vector2i(fx + 1, 28), Vector2i(fx + 1, 29)])
	await h.wait(0.5)
	h.note("4-cell pool before water", four.map(func(c): return snappedf(field.mass.get(c, 0.0), 0.01)))
	var h2: int = field.hardened
	_water(Level.map.getTilePos(Vector2(fx + 1, 28)), false)
	await h.until(func(): return field.hardened > h2, 6.0)
	h.check("a 4-cell pool hardens only 4", field.hardened - h2 == 4, field.last_hardened)

	# ---- a thin film doesn't trigger
	var film: Vector2i = Vector2i(14, 26)
	await _lava(h, [film], [film + Vector2i(0, -1), film + Vector2i(0, -2)])
	field.mass[film] = 0.1
	field.wake_all()
	var h3: int = field.hardened
	_water(Level.map.getTilePos(Vector2(film + Vector2i(0, -2))), false)
	await h.wait(3.0)
	h.check("a thin film (under BURN_MASS) doesn't harden", field.hardened == h3, field.hardened - h3)

	# ---- water outside lava behaves as before
	var floating: int = int(Data.ofOr("inventory.floatingwater", 0))
	h.check("water outside lava is still a normal drop", floating >= 1, floating)

	# ---- the hardened rock is in the save
	await SaveGame.saveGame(SaveGame.get_run_folder(), SLOT, true)
	var path: String = SaveGame.SAVE_TILE_FILE_TEMPLATE % [SaveGame.get_run_folder(), SLOT]
	var packed = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var saved = packed.instantiate() if packed else null
	var in_save: bool = saved != null and carried_cells.all(func(c): return saved.get_resourcev(c) == Data.TILE_DIRT_START)
	h.check("the saved map holds the hardened rock", in_save, path)
	if saved:
		saved.queue_free()
