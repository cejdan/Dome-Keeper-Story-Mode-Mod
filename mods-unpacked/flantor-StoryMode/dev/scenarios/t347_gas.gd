extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t347_meter.gd"

# Ticket 347: gas, and gas with lava, under the frame meter (t347_meter.gd), on
# a Medium map. For the three biggest sealed gas caverns the map generator
# filled (#201), a room is dug just above it and the keeper drills down into
# the cavern with its own drill, so the cavern's gas climbs into the room and
# hangs there as a cloud. In the first room the keeper then drills into a gas
# pocket in its wall (a second cloud in view), and last into a magma pocket in
# the other wall: the lava pours in and lights the gas. Toxin and suit heat are
# held at zero; the meter is the test.
#
#   --mapsize=<id>   map size (default regular-medium)
#   --ablate=1       switch suspects off one at a time in the cloud and the fire

const TIMEOUT := 420
const GAS_FRAME_MS_MAX := 8.0


func boot() -> Dictionary:
	return {"seed": 12345, "mapsize": _Story_arg("mapsize", "regular-medium")}


func _ktile(h) -> Vector2i:
	return Level.map.getTileCoord(h.keeper().global_position)


func _solid(td, cells: Array) -> void:
	for c in cells:
		if td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE or td.get_resourcev(c) == -1:
			td.set_hardnessv(c, Data.HARDNESS_MEDIUM)
		td.set_resourcev(c, Data.TILE_DIRT_START)


func _drill_until(h, action: String, cond: Callable, sec: float) -> bool:
	h.down(action)
	var ok: bool = await h.until(cond, sec)
	h.up(action)
	return ok


func run(h) -> void:
	h.disable_waves()
	var map = Level.map
	var td = map.tileData
	h.set_inv("money", 1000000)
	Data.apply("player1.keeper1.drillStrength", 100000)
	meter_start(h)
	await h.wait(1.0)
	await measure(h, "surface", 5.0)
	# The caverns still full, biggest first, not right under the surface.
	var caverns: Array = _gas.caverns.filter(func(cv): return cv.size() >= 8 and cv.all(func(c): return c.y > 12 and _gas.mass.has(c)))
	caverns.sort_custom(func(a, b): return a.size() > b.size())
	h.note("caverns", {"filled": _gas.caverns.size(), "usable": caverns.size(), "sizes": caverns.map(func(cv): return cv.size())})
	h.check("the map has gas caverns to open", caverns.size() >= 2, caverns.size())
	var rooms: Array = []
	for cv in caverns.slice(0, 3):
		var top: Vector2i = cv[0]
		for c in cv:
			if c.y < top.y:
				top = c
		# A room above the cavern, two rows of rock between, and a hole down to
		# the last row of rock over it.
		var room_a := Vector2i(top.x - 6, top.y - 8)
		var room_b := Vector2i(top.x + 6, top.y - 3)
		var wall: Array = []
		for y in range(room_a.y - 1, room_b.y + 2):
			for x in range(room_a.x - 3, room_b.x + 4):
				var c := Vector2i(x, y)
				if not cv.has(c) and _gas.mass.get(c, 0.0) <= 0.0 and _lava.mass.get(c, 0.0) <= 0.0:
					wall.append(c)
		_solid(td, wall)
		await h.dig_room(room_a, room_b)
		await h.dig_room(Vector2i(top.x, top.y - 2), Vector2i(top.x, top.y - 2))
		var lid := Vector2i(top.x, top.y - 1)
		await h.teleport_tile(Vector2i(top.x, top.y - 2))
		var broke: bool = await _drill_until(h, "ui_down", func(): return map.is_tile_empty(lid), 10.0)
		await h.teleport_tile(Vector2i(top.x + 3, room_b.y))
		h.check("drilled into the cavern at %s" % [top], broke, cv.size())
		rooms.append({"top": top, "a": room_a, "b": room_b})
		await measure(h, "cloud %d forming" % rooms.size(), 8.0)
		await h.shot("cloud_%d" % rooms.size())
	if rooms.is_empty():
		return
	var r: Dictionary = rooms[0]
	var a: Vector2i = r["a"]
	var b: Vector2i = r["b"]
	# Gas pocket in the left wall: the keeper drills into it from the room.
	var pocket: Array = [Vector2i(a.x - 2, b.y), Vector2i(a.x - 3, b.y), Vector2i(a.x - 2, b.y - 1), Vector2i(a.x - 3, b.y - 1)]
	_gas.add_pocket(pocket)
	await h.dig_room(Vector2i(a.x - 1, b.y), Vector2i(a.x - 1, b.y))
	await h.teleport_tile(Vector2i(a.x - 1, b.y))
	var opened: bool = await _drill_until(h, "ui_left", func(): return not _gas.rock.has(pocket[0]), 6.0)
	h.check("drilled into the gas pocket", opened, pocket[0])
	await h.teleport_tile(Vector2i(a.x + 4, b.y))
	await measure(h, "big cloud, pocket opened", 6.0)
	await h.shot("big_cloud")
	await measure(h, "big cloud, idle", 6.0)
	await ablate(h, "big cloud")
	h.note("gas", _gas.stats())
	# Lava into the cloud: a magma pocket in the right wall.
	var magma: Array = [Vector2i(b.x + 2, b.y), Vector2i(b.x + 3, b.y), Vector2i(b.x + 2, b.y - 1), Vector2i(b.x + 3, b.y - 1)]
	_lava.add_pocket(magma)
	var b0: int = _lava.breaches
	await h.dig_room(Vector2i(b.x + 1, b.y), Vector2i(b.x + 1, b.y))
	await h.teleport_tile(Vector2i(b.x + 1, b.y))
	var breached: bool = await _drill_until(h, "ui_right", func(): return _lava.breaches > b0, 8.0)
	h.check("drilled into the magma pocket", breached, _lava.breaches)
	await h.teleport_tile(Vector2i(a.x + 3, b.y))
	await measure(h, "lava into the cloud", 8.0)
	await h.shot("lava_and_gas")
	h.note("fire", {"ignitions": _gas.ignitions, "burning": _gas.fire.size(), "lava": _lava.stats()})
	await measure(h, "lava and gas, after", 6.0)
	await ablate(h, "lava and gas")
	meter_stop()
	var rep: Dictionary = report(h)
	h.note("gas end", _gas.stats())
	var surf: float = avg(rep, "surface")
	for st in ["big cloud, idle", "lava into the cloud", "lava and gas, after"]:
		var v: float = avg(rep, st)
		h.check("%s: average frame %.2f ms (surface %.2f, limit %.1f)" % [st, v, surf, GAS_FRAME_MS_MAX], v >= 0.0 and v < GAS_FRAME_MS_MAX, rep.get(st, {}))
