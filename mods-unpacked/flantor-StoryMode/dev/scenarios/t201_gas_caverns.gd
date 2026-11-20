extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 201: sealed gas caverns in the generated map. They sit from B2 down
# to above the lava ocean, clear of lava pools and special tiles; each is
# sealed, full, and at rest from the first step. Opening a cavern's floor lets
# nothing out; opening its ceiling does.

const GasData = preload("res://mods-unpacked/flantor-StoryMode/data/gas.gd")
const TIMEOUT := 300


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	await h.until(func(): return Level.map.get_node_or_null("StoryGasField") != null, 10.0)
	var field = Level.map.get_node("StoryGasField")
	var map = Level.map
	var td = map.tileData
	var all: Array = td.get_meta("story_gas_caverns", [])
	var pools := {}
	for pool in td.get_meta("story_pools", []):
		for c in pool:
			pools[Vector2i(c)] = true
	var ocean: Dictionary = td.get_meta("story_ocean", {})

	# ---- 1. where they are
	var by_biome := {}
	var sizes: Array = []
	var shallow := 0
	var near_pool := 0
	var in_ocean := 0
	for cavern in all:
		sizes.append(cavern.size())
		var b: int = td.get_biomev(cavern[0])
		by_biome[b] = by_biome.get(b, 0) + 1
		for c in cavern:
			if td.get_biomev(c) < GasData.CAVERN_START_BIOME:
				shallow += 1
			if not ocean.is_empty() and c.y >= int(ocean["ceiling"]) - 2:
				in_ocean += 1
			for ox in range(-2, 3):
				for oy in range(-2, 3):
					if pools.has(Vector2i(c) + Vector2i(ox, oy)):
						near_pool += 1
	h.note("gas caverns", {"count": all.size(), "by biome": by_biome, "sizes": sizes, "skipped": field.caverns_skipped})
	h.check("the map has gas caverns", all.size() >= 6, all.size())
	h.check("none above B2", shallow == 0, shallow)
	h.check("none at the lava ocean", in_ocean == 0, in_ocean)
	h.check("none within 2 tiles of a lava pool", near_pool == 0, near_pool)
	h.check("caverns from B2 to B8", by_biome.has(1) and by_biome.has(7), by_biome)
	h.check("deeper caverns are bigger", sizes.max() >= 2 * sizes.min(), [sizes.min(), sizes.max()])

	# ---- 2. sealed, full and at rest
	h.check("every cavern is filled, or was opened by a cave", field.caverns.size() + field.caverns_skipped == all.size() and field.caverns.size() >= all.size() - 3, [field.caverns.size(), field.caverns_skipped])
	var before: float = field.total()
	await h.wait(3.0)
	var st: Dictionary = field.stats()
	h.check("the caverns' gas is at rest: nothing awake, nothing lost", int(st["awake"]) == 0 and absf(float(st["total"]) - before) < 0.001 and float(st["faded"]) == 0.0, st)
	var full := true
	for cavern in field.caverns:
		for c in cavern:
			if field.mass.get(c, 0.0) < 1.0:
				full = false
	h.check("every cavern cell holds at least a cell of gas", full)
	h.check("hidden pockets are still there too", field.rock.size() > 20, field.rock.size())

	# ---- 3. a cavern opened from below, then from above
	var cavern: Array = []
	var low := Vector2i.ZERO
	var high := Vector2i.ZERO
	for cv in field.caverns:
		var lo: Vector2i = cv[0]
		var hi: Vector2i = cv[0]
		for c in cv:
			if c.y > lo.y:
				lo = c
			if c.y < hi.y:
				hi = c
		var ok := true
		for c in [lo + Vector2i.DOWN, lo + Vector2i(0, 2), hi + Vector2i.UP, hi + Vector2i(0, -2)]:
			if map.is_tile_empty(c) or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE or td.get_biomev(c) < 0 or field.rock.has(c):
				ok = false
		if ok and cv.size() >= 6 and cavern.is_empty():
			cavern = cv
			low = lo
			high = hi
	h.check("picked a cavern to open", not cavern.is_empty(), [low, high])
	var gas0: float = 0.0
	for c in cavern:
		gas0 += field.mass[c]
	await h.reveal(cavern + [low + Vector2i.DOWN, low + Vector2i(0, 2), high + Vector2i.UP, high + Vector2i(0, -2)])
	await h.clear_tiles([low + Vector2i.DOWN, low + Vector2i(0, 2)])
	field.wake_all()
	await h.teleport_tile(low + Vector2i(0, 2))
	h.keeper().set("gravity_scale", 0.0)
	field.freeze_toxin = true
	await h.wait(3.0)
	h.snap_camera()
	await h.burst("opened_from_below", 6, 10)
	var gas1: float = 0.0
	for c in cavern:
		gas1 += field.mass.get(c, 0.0)
	h.check("opened from below, the cavern keeps its gas", absf(gas1 - gas0) < 0.05 and field.mass.get(low + Vector2i.DOWN, 0.0) < 0.05, [gas0, gas1, field.mass.get(low + Vector2i.DOWN, 0.0)])
	await h.clear_tiles([high + Vector2i.UP, high + Vector2i(0, -2)])
	field.wake_all()
	await h.teleport_tile(high + Vector2i(0, -2))
	h.keeper().set("gravity_scale", 0.0)
	await h.burst("opened_from_above", 12, 8)
	await h.wait(2.0)
	var gas2: float = 0.0
	for c in cavern:
		gas2 += field.mass.get(c, 0.0)
	h.check("opened from above, gas comes up out of it", field.mass.get(high + Vector2i(0, -2), 0.0) > 0.5 and gas2 < gas1 - 1.0, [gas1, gas2, field.mass.get(high + Vector2i(0, -2), 0.0)])
	h.check("gas is conserved", absf(field.total() + field.vented + field.faded - before) < 0.01, [field.total(), before])
