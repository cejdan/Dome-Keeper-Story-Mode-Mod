extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t347_meter.gd"

# Ticket 347: players saw 1-2 fps "when going to the bottom lava lake". This
# goes there the real way on a Medium map (the loadout's default size): the
# keeper drills straight down from the dome with its own drill (metal in the
# column turned to rock, as t149 does, so the drill isn't stopped), mines a
# tunnel along the ocean's ceiling, breaks through, mines on along the ceiling
# with the ocean in view, then drops into the lava. Suit heat is held at zero
# throughout; the frame meter (t347_meter.gd) is the test.
#
#   --mapsize=<id>   map size (default regular-medium)
#   --ablate=1       switch suspects off one at a time over the ocean

const TIMEOUT := 600
# Average frame time allowed over the ocean (ms), and how far above the frame
# at the surface it may be (vsync off, so these are cost, not refresh).
const OCEAN_FRAME_MS_MAX := 8.0

const Metal = preload("res://mods-unpacked/flantor-StoryMode/data/metal.gd")
static var _Metal = Metal  # calls go through this: lazy_preload makes const-preload calls slow


func boot() -> Dictionary:
	return {"seed": 12345, "mapsize": _Story_arg("mapsize", "regular-medium")}


func _ktile(h) -> Vector2i:
	return Level.map.getTileCoord(h.keeper().global_position)


# Digs `c` open (revealing around it) and moves the keeper into it.
func _dig_to(h, c: Vector2i, sec: float) -> void:
	if not Level.map.is_tile_empty(c):
		await h.dig_room(c, c)
	await h.teleport_tile(c)
	if sec > 0.0:
		await h.wait(sec)


func run(h) -> void:
	h.disable_waves()
	var map = Level.map
	var td = map.tileData
	var o: Dictionary = td.get_meta("story_ocean", {})
	h.check("the map has a lava ocean", not o.is_empty(), o)
	if o.is_empty():
		return
	var ceiling: int = int(o["ceiling"])
	h.set_inv("money", 1000000)
	for i in range(1, 5):
		await h.buy("storyheatshield%d" % i)
	Data.apply("player1.keeper1.drillStrength", 100000)
	meter_start(h)
	await h.wait(1.0)
	await measure(h, "surface", 5.0)
	await h.shot("surface")
	# The column: a few tiles off the dome's lift, metal turned to rock.
	var x: int = 4
	var metal := 0
	for y in range(0, ceiling):
		if _Metal.is_metal_id(td.get_resourcev(Vector2i(x, y))):
			td.set_resourcev(Vector2i(x, y), Data.TILE_DIRT_START)
			metal += 1
		if td.get_hardnessv(Vector2i(x, y)) >= Data.HARDNESS_INDESTRUCTIBLE and td.get_resourcev(Vector2i(x, y)) != -1:
			td.set_hardnessv(Vector2i(x, y), Data.HARDNESS_MEDIUM)
	# Walk out of the dome to the column, then drill down.
	var start: Vector2i = _ktile(h)
	h.note("descent", {"from": start, "column": x, "ceiling": ceiling, "ocean": o, "metal swapped": metal})
	# The mine is dug cell by cell at about a drill's pace, the keeper moved
	# along: each cell is revealed and broken the way the drill breaks it (tile
	# signals, so pockets on the way breach and the flood reveal runs). (The
	# keeper's own drill outruns the reveal in harness runs and drops through
	# rock that has no tiles yet.)
	step = "descent"
	var t0: float = h.now()
	for y in range(0, ceiling):
		await _dig_to(h, Vector2i(x, y), 0.08)
	step = ""
	h.note("descent done", {"at": _ktile(h), "seconds": h.now() - t0, "tiles": map.tiles_node.tiles.size(), "seen": map.visibleTileCoords.size(),
		"lava": _lava.stats(), "gas": _gas.stats() if _gas else {}})
	h.check("the keeper dug down to the ocean ceiling (row %d)" % ceiling, _ktile(h).y >= ceiling - 2, _ktile(h))
	await h.shot("at_ceiling")
	await measure(h, "at the ceiling, ocean hidden", 5.0)
	# Mine along the ceiling (the row above it), the ocean still sealed.
	step = "ceiling tunnel, ocean hidden"
	for i in range(1, 9):
		await _dig_to(h, Vector2i(x - i, ceiling - 1), 0.25)
	step = ""
	# Break through the ceiling, then back up into the tunnel beside the hole.
	var hole := Vector2i(x - 8, ceiling)
	step = "break in"
	await h.dig_room(hole, hole)
	await h.teleport_tile(Vector2i(x - 7, ceiling - 1))
	await h.wait(3.0)
	step = ""
	h.check("broke through the ocean ceiling", map.is_tile_empty(hole), hole)
	await h.shot("broke_in")
	await measure(h, "over the ocean, idle", 6.0)
	await h.shot("over_ocean")
	await ablate(h, "over the ocean")
	step = "mining the ceiling over the ocean"
	for i in range(1, 25):
		await _dig_to(h, Vector2i(x + i, ceiling - 1), 0.25)
	step = ""
	await h.shot("mined_along")
	# Into the lava: the screen full of it.
	await h.teleport_tile(hole + Vector2i(0, 4))
	step = "falling in"
	await h.wait(3.0)
	step = ""
	await measure(h, "in the ocean", 6.0)
	await h.shot("in_ocean")
	await ablate(h, "in the ocean")
	meter_stop()
	var rep: Dictionary = report(h)
	h.note("lava", _lava.stats())
	var surf: float = avg(rep, "surface")
	for st in ["over the ocean, idle", "mining the ceiling over the ocean", "in the ocean"]:
		var a: float = avg(rep, st)
		h.check("%s: average frame %.2f ms (surface %.2f, limit %.1f)" % [st, a, surf, OCEAN_FRAME_MS_MAX], a >= 0.0 and a < OCEAN_FRAME_MS_MAX, rep.get(st, {}))
