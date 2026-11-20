extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Tickets 46 and 187: passive heat by depth and Heat Shielding tier. Each biome
# from B4 down is one heat level deeper; each tier moves the scale down a
# biome (data/lava.gd). Measures the heat rise in a dug room in each biome for
# tiers 0, 1, 2 and 4, times an overheat in a "rough" and a "deadly" biome,
# checks a "cool" biome drains the bar, and that lava still heats at tier IV.
# Run with -Extra "--mode=relichunt" to check vanilla has none.

const LavaData = preload("res://mods-unpacked/flantor-StoryMode/data/lava.gd")
const TIMEOUT := 700


func boot() -> Dictionary:
	return {"seed": 12345}


var field
var td
var rooms: Dictionary = {}   # biome index -> centre of a dug 3 x 3 room


# A dug 3 x 3 room in the middle rows of biome `b`, near column 0.
func _room_in_biome(h, b: int) -> Vector2i:
	var rows: Array = []
	for c: Vector2i in td.get_used_biome_cells():
		if td.get_biomev(c) == b and absi(c.x) <= 2 and not rows.has(c.y):
			rows.append(c.y)
	rows.sort()
	if rows.is_empty():
		return Vector2i(9999, 9999)
	var mid: int = rows[rows.size() / 2]
	for dy in [0, -2, 2, -4, 4, -6, 6]:
		for dx in range(0, 30):
			for x in [dx, -dx]:
				var c := Vector2i(x, mid + dy)
				var fits: bool = true
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						var n: Vector2i = c + Vector2i(ox, oy)
						fits = fits and td.get_biomev(n) == b and td.get_resourcev(n) != Data.TILE_BORDER and td.get_hardnessv(n) < Data.HARDNESS_INDESTRUCTIBLE
				if fits:
					for oy in range(-1, 2):
						for ox in range(-1, 2):
							var n: Vector2i = c + Vector2i(ox, oy)
							if td.get_resourcev(n) != Data.TILE_EMPTY:
								td.set_resourcev(n, Data.TILE_DIRT_START)
					await h.dig_room(c + Vector2i(-1, -1), c + Vector2i(1, 1))
					return c
	return Vector2i(9999, 9999)


func _tier(t: int) -> void:
	Data.apply(LavaData.shield_key(), t)   # the keeper's own tier (#265)


# Puts the keeper in room `c` with heat `h0` and runs `secs` game seconds (the
# lava field's own clock). Returns [heat after, seconds to an overheat or -1].
func _stay(h, c: Vector2i, h0: float, secs: float) -> Array:
	var r0: int = field.recalls
	# No lava (pools, flows) anywhere: this measures depth heat only.
	field.mass.clear()
	await h.teleport_tile(c)
	await h.frames(2)
	field.heat = h0
	var t0: float = field._time
	while field._time - t0 < secs:
		await h.frames(1)
		if field.recalls > r0:
			return [field.heat, snappedf(field._time - t0, 0.1)]
	return [field.heat, -1.0]


func run(h) -> void:
	h.disable_waves()
	if Level.loadout.modeId != "storymode":
		h.check("vanilla has no lava field, so no passive heat", Level.map.get_node_or_null("StoryLavaField") == null)
		return
	field = Level.map.get_node("StoryLavaField")
	td = Level.map.tileData
	field.magma.clear()
	for b in range(2, 8):
		rooms[b] = await _room_in_biome(h, b)
	h.note("rooms", rooms)
	h.check("found a room in B3 to B8", not rooms.values().has(Vector2i(9999, 9999)), rooms)

	# Rate table: measured heat rise over 3 game seconds against the rule.
	h.speed(4.0)
	var names := {-1: "cool", 0: "fine", 1: "rough", 2: "deadly", 3: "deadly+"}
	for t in [0, 1, 2, 4]:
		_tier(t)
		var row: Dictionary = {}
		var ok: bool = true
		for b in range(2, 8):
			var want: float = LavaData.passive_rate(b)
			var r: Array = await _stay(h, rooms[b], 0.0, 3.0)
			var got: float = float(r[0]) / 3.0
			var lvl: int = clampi(LavaData.passive_level(b), -1, 3) if b >= LavaData.PASSIVE_HEAT_START_BIOME else -1
			row["B%d" % (b + 1)] = "%s %.2f/s (rule %.2f)" % [names[lvl], got, want]
			if want == 0.0:
				ok = ok and float(r[0]) == 0.0
			elif want < 20.0:   # faster ones overheat inside the window
				ok = ok and absf(got - want) <= maxf(0.05, want * 0.15)
		h.check("tier %d: heat per biome follows the rule" % t, ok, row)

	# The user's examples, timed.
	_tier(0)
	var b4: Array = await _stay(h, rooms[3], 0.0, 60.0)
	h.check("tier 0, B4 (fine): under a quarter of the bar after a minute", b4[1] < 0 and float(b4[0]) < 25.0, b4)
	var b5: Array = await _stay(h, rooms[4], 0.0, 90.0)
	h.check("tier 0, B5 (rough): overheats in about a minute", b5[1] > 45.0 and b5[1] < 75.0, b5)
	var b6: Array = await _stay(h, rooms[5], 0.0, 30.0)
	h.check("tier 0, B6 (practically lava): overheats in about 10 s", b6[1] > 6.0 and b6[1] < 14.0, b6)
	_tier(1)
	var b4c: Array = await _stay(h, rooms[3], 50.0, 10.0)
	h.check("tier 1, B4 (cool): the bar drains", float(b4c[0]) < 50.0, b4c)
	var b7: Array = await _stay(h, rooms[6], 0.0, 30.0)
	h.check("tier 1, B7 (practically death): overheats in about 10 s", b7[1] > 6.0 and b7[1] < 14.0, b7)
	_tier(2)
	var b5c: Array = await _stay(h, rooms[4], 50.0, 10.0)
	h.check("tier 2, B5 (cool): the bar drains", float(b5c[0]) < 50.0, b5c)
	h.speed(1.0)

	# A screenshot of the bar in a rough biome.
	_tier(0)
	await h.teleport_tile(rooms[4])
	field.heat = 0.0
	await h.wait(6.0)
	await h.shot("tier0_B5_rough_bar")

	# Back in the dome the suit cools to 0.
	field.heat = 60.0
	var dome = Level.getDome("team1")
	h.keeper().teleport(dome.global_position)
	h.snap_camera()
	await h.until(func(): return h.keeper().isInsideDome, 5.0)
	await h.until(func(): return field.heat <= 0.0, 10.0)
	h.check("in the dome the suit cools to 0", h.keeper().isInsideDome and field.heat == 0.0, {"inside": h.keeper().isInsideDome, "heat": field.heat})

	# Tier IV: B8 is fine, and lava still heats (faster than B8's depth heat).
	_tier(4)
	var deep: Vector2i = rooms[7]
	for y in range(-1, 2):
		for x in range(-1, 2):
			field.mass[deep + Vector2i(x, y)] = 1.0 + 0.25 * (y + 1)
	field.wake_all()
	await h.teleport_tile(deep)
	field.heat = 0.0
	await h.wait(2.0)
	# Lava takes a moment to settle into the keeper's cell; B8's depth heat
	# alone would give about 0.7 in these 2 s.
	h.check("at tier IV lava still heats, faster than B8's depth heat", field.heat > 1.5 and field.heat < 2.0 * LavaData.HEAT_PER_SECOND * LavaData.lava_heat_mult() + 3.0, field.heat)
