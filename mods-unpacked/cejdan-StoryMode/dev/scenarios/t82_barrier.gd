extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 82: the energy barrier over the boss chamber holds the ocean back
# where the crust is broken, and lets the keeper through.

const LavaData = preload("res://mods-unpacked/cejdan-StoryMode/data/lava.gd")


func boot() -> Dictionary:
	# The boss fight (#160) would seal the chamber; it has its own scenarios.
	return {"seed": 12345, "boss": false}


func run(h) -> void:
	h.disable_waves()
	var field = Level.map.get_node("StoryLavaField")
	var td = Level.map.tileData
	var ch: Rect2i = td.get_meta("story_boss_chamber")
	h.check("the run has a boss chamber", ch.size == Vector2i(20, 10), ch)
	h.check("no barrier while the crust is whole", field.barrier_columns().is_empty(), field.barrier_columns())
	Data.apply("team1." + LavaData.HEAT_SHIELD_KEY, 4)

	# Reveal the chamber and the ocean above a few crust columns, then break two.
	var area: Array = []
	for y in range(ch.position.y - 6, ch.position.y + 4):
		for x in range(ch.position.x - 2, ch.position.x + 12):
			area.append(Vector2i(x, y))
	await h.reveal(area)
	var crust_y: int = ch.position.y - 1
	var holes: Array = [Vector2i(ch.position.x + 4, crust_y), Vector2i(ch.position.x + 5, crust_y)]
	await h.clear_tiles(holes)
	await h.wait(4.0)
	var cols: Array = field.barrier_columns()
	h.note("barrier columns", cols)
	h.check("the barrier shows exactly where the crust is broken", cols == [holes[0].x, holes[1].x], cols)
	h.check("the ocean rests on the barrier (lava in the broken crust cells)", field.mass.get(holes[0], 0.0) >= 0.9 and field.mass.get(holes[1], 0.0) >= 0.9, [field.mass.get(holes[0], 0.0), field.mass.get(holes[1], 0.0)])

	# From inside the chamber, under the barrier.
	await h.teleport_tile(Vector2i(holes[0].x, ch.position.y + 2))
	await h.wait(2.0)
	await h.shot("from_inside")
	# From above, in the ocean.
	await h.teleport_tile(Vector2i(holes[0].x, crust_y - 3))
	await h.wait(1.5)
	await h.shot("from_above")

	# The keeper passes through: from the chamber up into the broken crust cell.
	await h.teleport_tile(Vector2i(holes[0].x, ch.position.y + 1))
	await h.wait(0.5)
	h.down("ui_up")
	var passed: bool = await h.until(func(): return h.keeper_tile().y <= crust_y, 4.0)
	h.up("ui_up")
	h.check("the keeper passes up through the barrier", passed, h.keeper_tile())

	await h.wait(5.0)
	var dry: float = 0.0
	for c in field.mass:
		if ch.has_point(c):
			dry += field.mass[c]
	h.check("the chamber stays dry", dry == 0.0, dry)
