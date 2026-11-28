extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t369_rise.gd"

# #369: slot 69 (saved by t369_rise mid-rise) in a fresh process. The lava is
# back where it was saved: the state "rising" and the level from the save; the
# band at the level, everything open under it lava (implied, drawn), nothing
# stored under the band, no lava in rock; the rise goes on (easing in again)
# at the set speed; a suit death is still the too-late loss.


const FieldUtil = preload("res://mods-unpacked/flantor-StoryMode/util/field_util.gd")
static var _FieldUtil = FieldUtil  # calls go through this: lazy_preload makes const-preload calls slow


func boot() -> Dictionary:
	return {"load": SLOT}


func run(h) -> void:
	if not await setup(h, false):
		return
	var k = h.keeper()
	var saved: float = float(Data.ofOr(_RisingLava.ROW_KEY, -1.0))
	h.check("loaded mid-rise: rising, at the saved level", _RisingLava.state() == "rising" and lava.flood_active() and absf(rise.row - saved) < 1.0, [_RisingLava.state(), rise.row, saved])
	h.check("restored at once (not replayed from the ocean)", _RisingLava.events.any(func(e): return e["what"] == "restored"), _RisingLava.events)
	var st: Dictionary = lava.flood_stats()
	h.check("the band at the level, the rest implied", st["band_top"] == int(floor(rise.row)) and st["implied"][0] == st["band_top"] + Flood.BAND_ROWS, st)
	h.check("nothing stored under the band", lava.mass.keys().filter(func(c): return c.y >= st["implied"][0] and c.y < st["implied"][1]).is_empty())
	h.check("shaft B under the line is lava", lava.flooded(Vector2i(11, 90)) and lava.flooded(Vector2i(20, 71)), [lava.flooded(Vector2i(11, 90)), lava.flooded(Vector2i(20, 71))])
	h.check("no lava in rock", lava_in_rock().is_empty(), lava_in_rock().slice(0, 8))
	h.check("a suit death is still the too-late loss", _RisingLava.ends_run())
	var gas = Level.map.get_node_or_null("StoryGasField")
	if gas != null:
		gas.freeze_toxin = true
	# Look at the flooded mine below shaft C, and watch it come up.
	# (A dev dig leaves the mod's metal record behind: metal it cleared comes
	# back with a load, so look for a spot in shaft B that is open.)
	var spot := Vector2i(11, int(rise.row) - 9)
	for y in range(int(rise.row) - 6, 47, -1):
		var c := Vector2i(11, y)
		if Level.map.is_tile_empty(c) and not Level.map.tiles.has(Vector2(c)) and Level.map.is_tile_empty(c + Vector2i.UP):
			spot = c
			if y <= int(rise.row) - 8:
				break
	var dbg: Array = []
	for y in range(50, 72, 3):
		var row: Array = []
		for x in [3, 10, 11, 12, 13]:
			var c := Vector2i(x, y)
			row.append("%d:%s%s" % [Level.map.tileData.get_resourcev(c), "T" if Level.map.tiles.has(Vector2(c)) else "-", "S" if _FieldUtil.seen(Level.map, c) else "-"])
		dbg.append([y, row])
	h.note("cells after the load", dbg)
	await place(h, k, spot)
	# The route as the player had seen it (in this dev save the dug cells'
	# reveal doesn't all come back with the load: vanilla's, not the lava's).
	var cells: Array = []
	for r in ROUTE:
		for y in range(r[0].y, r[1].y + 1):
			for x in range(r[0].x, r[1].x + 1):
				cells.append(Vector2i(x, y))
	await h.reveal(cells)
	await h.wait(0.6)
	var cam = Level.viewports.getPlayerCam(k.playerId)
	cam.targetOffset = Vector2(0, 150)
	h.snap_camera(k)
	await h.wait(0.5)
	cool(h)
	h.note("after the load", {"keeper": k.global_position, "cell": h.keeper_tile(), "in_dome": k.isInsideDome, "visible": k.visible, "modulate": k.modulate,
		"seen_shaft": [_FieldUtil.seen(Level.map, Vector2i(11, 70)), _FieldUtil.seen(Level.map, Vector2i(11, 56))], "tiles_beside": Level.map.tiles.has(Vector2(10, 56)),
		"visible_n": Level.map.visibleTileCoords.size(), "tiles_n": Level.map.tiles.size(), "boxes": lava._view_boxes})
	await h.shot("after_the_load")
	h.check("the implied lava in view is drawn after the load (the seen cells marked)", lava.fl_cells_implied >= 20, lava.flood_stats())
	var r0: float = rise.row
	await h.wait(4.0)
	cool(h)
	var r1: float = rise.row
	await h.wait(4.0)
	cool(h)
	var fast: float = (r1 - rise.row) / 4.0 * 24.0
	h.check("it goes on rising (eased in, then the set speed)", r1 < r0 and fast > Flood.RISE_PX_PER_S * 0.6, [r0, r1, rise.row, fast])
	await h.shot("rising_on")
	cam.targetOffset = Vector2.ZERO
