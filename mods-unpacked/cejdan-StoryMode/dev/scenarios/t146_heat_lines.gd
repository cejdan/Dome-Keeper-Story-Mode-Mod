extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 146: the keeper's heat lines. B3 is calm. B4 says "so hot", B5
# "feels even hotter". Back up to B4: quiet. Up to B3 with heat on the bar:
# a relieved line. Down again: "so hot" again, and the next relief is a
# different line. With Heat Shielding IV (no passive heat) B5 says nothing.

const Lines = preload("res://mods-unpacked/cejdan-StoryMode/data/heat_lines.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


var td


# A dug 3 x 3 room in the middle rows of biome index `b`, near column 0.
func _room_in_biome(h, b: int) -> Vector2i:
	var rows: Array = []
	for y in range(0, 400):
		if td.get_biomev(Vector2i(0, y)) == b:
			rows.append(y)
	if rows.is_empty():
		return Vector2i(9999, 9999)
	var y0: int = rows[rows.size() / 2]
	for dx in range(0, 30):
		for x in [dx, -dx]:
			var c := Vector2i(x, y0)
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


func _talk():
	return h_ref.get_tree().get_first_node_in_group("story-heat-talk")


var h_ref


# Moves the keeper to `c`, waits `sec` and returns the lines shown meanwhile.
func _go(h, c: Vector2i, sec: float, label: String) -> Array:
	var talk = _talk()
	var n0: int = talk.shown.size()
	await h.teleport_tile(c)
	var shot_done: bool = false
	var t: float = 0.0
	while t < sec:
		await h.wait(0.1)
		t += 0.1
		if not shot_done and talk.shown.size() > n0:
			await h.wait(0.5)
			await h.shot(label)
			shot_done = true
	if not shot_done:
		await h.shot(label)
	var new: Array = talk.shown.slice(n0).map(func(s): return s["text"])
	var k = h.keeper()
	h.note(label, {"lines": new, "heat": Level.map.get_node("StoryLavaField").heat, "keeper tile": Level.map.getTileCoord(k.global_position), "in dome": k.isInsideDome, "disabled": k.disabled, "state": talk._pending, "hot_section": talk.hot_section})
	return new


func run(h) -> void:
	h_ref = h
	h.disable_waves()
	td = Level.map.tileData
	Level.map.get_node("StoryLavaField").magma.clear()
	var b3: Vector2i = await _room_in_biome(h, 2)
	var b4: Vector2i = await _room_in_biome(h, 3)
	var b5: Vector2i = await _room_in_biome(h, 4)
	h.note("rooms", {"b3": b3, "b4": b4, "b5": b5})
	h.check("rooms dug in B3, B4 and B5", b3.x < 999 and b4.x < 999 and b5.x < 999)
	var calm: Array = await _go(h, b3, 2.0, "b3_calm")
	h.check("B3 with no heat: no line", calm.is_empty(), calm)
	var hot: Array = await _go(h, b4, 5.0, "b4_so_hot")
	h.check("B4: \"so hot\"", hot == ["so hot"], hot)
	var hotter: Array = await _go(h, b5, 5.0, "b5_hotter")
	h.check("B5: \"feels even hotter\"", hotter == ["feels even hotter"], hotter)
	var back: Array = await _go(h, b4, 3.0, "b4_back_up")
	h.check("back up to B4, still hot: quiet", back.is_empty(), back)
	var cool1: Array = await _go(h, b3, 4.0, "b3_cooler")
	h.check("up to B3 with heat on the bar: one relieved line", cool1.size() == 1 and Lines.COOL.has(cool1[0]), cool1)
	var again: Array = await _go(h, b4, 4.0, "b4_again")
	h.check("down again: \"so hot\" again", again == ["so hot"], again)
	var cool2: Array = await _go(h, b3, 4.0, "b3_cooler_again")
	h.check("the next relief is a different line", cool2.size() == 1 and cool2[0] != cool1[0], [cool1, cool2])
	# Heat Shielding IV: no passive heat, no hot lines.
	h.set_inv("money", 100000)
	for i in range(1, 5):
		await h.buy("storyheatshield%d" % i)
	await h.wait(3.0)
	var shielded: Array = await _go(h, b5, 4.0, "b5_shielded")
	h.check("with Heat Shielding IV, B5 says nothing", shielded.is_empty(), shielded)
	h.snap("end", [])
