extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 149: a dive straight down from B7, away from the map's centre, reaches
# the lava ocean. The keeper gets a strong drill and Heat Shielding IV so the
# dig, not the heat, is what's tested.

const TIMEOUT := 300

const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	var td = Level.map.tileData
	var o: Dictionary = td.get_meta("story_ocean", {})
	var ceiling: int = int(o["ceiling"])
	var field = Level.map.get_node("StoryLavaField")
	# Lava is its own hazard (and its own tickets): no breaches, no overheat.
	field.magma.clear()
	h.set_inv("money", 100000)
	for i in range(1, 5):
		await h.buy("storyheatshield%d" % i)
	Data.apply("player1.keeper1.drillStrength", 100000)
	h.note("fill", {"bottom fill tiles": td.get_meta("story_bottom_fill", 0), "ceiling": ceiling})
	var results: Array = []
	for x in [-22, 17, 5]:
		var start: int = -1
		for y in range(0, ceiling):
			if td.get_biomev(Vector2i(x, y)) == 6 and td.get_resourcev(Vector2i(x, y)) != Data.TILE_BORDER:
				start = y
				break
		if start < 0:
			h.note("column %d has no B7" % x, {})
			continue
		# Metal (B6-B8) stops a keeper's drill by design; the Suit Blaster or a
		# detour gets past it. Here it is swapped for rock, so the dive tests the
		# map's shape. Counted in the notes.
		var metal: int = 0
		for y in range(start, ceiling):
			if Metal.is_metal_id(td.get_resourcev(Vector2i(x, y))):
				td.set_resourcev(Vector2i(x, y), Data.TILE_DIRT_START)
				metal += 1
		# And no lava in or beside the shaft (pools are pre-filled caverns).
		var drained: int = 0
		for c in field.mass.keys():
			if absi(c.x - x) <= 3 and c.y >= start and c.y < ceiling:
				field.mass.erase(c)
				drained += 1
		await h.dig_room(Vector2i(x, start), Vector2i(x, start))
		await h.teleport_tile(Vector2i(x, start))
		field.heat = 0.0
		h.down("ui_down")
		var got: bool = await h.until(func():
			field.heat = 0.0
			return Level.map.getTileCoord(h.keeper().global_position).y >= ceiling - 1, 90.0)
		h.up("ui_down")
		var at: Vector2i = Level.map.getTileCoord(h.keeper().global_position)
		var below = Level.map.getTile(Vector2(at + Vector2i.DOWN))
		h.note("column %d stop" % x, {"at": at, "below type": below.type if below else "none", "below hardness": below.hardness if below else -1, "below res": td.get_resourcev(at + Vector2i.DOWN), "below biome": td.get_biomev(at + Vector2i.DOWN)})
		await h.shot("dive_x%d" % x)
		results.append({"x": x, "metal on the way": metal, "lava cells drained": drained, "from row": start, "reached row": at.y, "ceiling": ceiling})
		h.check("column %d: straight down from B7 (row %d) reaches the ocean ceiling (row %d)" % [x, start, ceiling], got, at)
	h.note("dives", results)
	# ---- Break through: the air gap over the lava, and its view.
	var top: int = int(o["top"])
	h.check("%d rows of air between the ceiling (row %d) and the lava (row %d)" % [top - ceiling - 1, ceiling, top], top - ceiling - 1 >= 3, o)
	var air_lava: float = 0.0
	for y in range(ceiling + 1, top):
		for x in range(int(o["x0"]), int(o["x1"]) + 1):
			air_lava += field.mass.get(Vector2i(x, y), 0.0)
	h.check("the air rows hold no lava", air_lava < 0.05, air_lava)
	var k: Vector2i = Level.map.getTileCoord(h.keeper().global_position)
	await h.dig_room(Vector2i(k.x - 1, ceiling), Vector2i(k.x + 1, ceiling))
	h.down("ui_down")
	await h.until(func():
		field.heat = 0.0
		return Level.map.getTileCoord(h.keeper().global_position).y >= ceiling + 2, 10.0)
	h.up("ui_down")
	await h.wait(0.5)
	field.heat = 0.0
	await h.shot("broke_into_ocean")
	h.speed(0.5)
	await h.wait(1.0)
	await h.shot("broke_into_ocean_2")
	h.speed(1.0)
	var top_full: float = field.mass.get(Vector2i(k.x + 4, top), 0.0)
	h.check("the lava surface stays at its row (row %d full)" % top, top_full >= 0.9, top_full)
