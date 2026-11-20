extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 289: Workshop footage, lava lighting the gas. Run it under Movie
# Maker (see dev/workshop_shoot.gd); "clip" notes give the frames to cut at.
#
# A long room in B2/B3 with a lava pit under its ceiling at the right end,
# and a gas pocket in its left wall. The keeper drills into the pocket and
# backs off; the gas rolls along the ceiling, reaches the lava, catches, and
# the fire races back through the whole cloud.
#
#   GGGG................      G the gas pocket           y 0..2
#   GGGG............#LLL      L lava in its pit          y 1
#   GGGG............####      the room                   y 0..2

const Shoot = preload("res://mods-unpacked/cejdan-StoryMode/dev/workshop_shoot.gd")
const TIMEOUT := 900

var R := Vector2i.ZERO
var field
var lava
var guard := true


func boot() -> Dictionary:
	return {"seed": 12345}


func _c(x: int, y: int) -> Vector2i:
	return R + Vector2i(x, y)


# Keeps the keeper alive: toxin and heat stop short of full.
func _guard(h) -> void:
	while guard:
		if field.toxin > 55.0:
			field.freeze_toxin = true
		var k = h.keeper()
		if lava.heat_of(k) > 60.0:
			lava.set_heat_of(k, 60.0)
		await h.frames(1)


func _fly(h, action: String, done: Callable, timeout: float) -> void:
	h.down(action)
	await h.until(done, timeout)
	h.up(action)


func run(h) -> void:
	Shoot.window_1080()
	h.disable_waves()
	await h.until(func(): return Level.map.get_node_or_null("StoryGasField") != null, 10.0)
	field = Level.map.get_node("StoryGasField")
	lava = Level.map.get_node("StoryLavaField")
	var td = Level.map.tileData
	var found: Vector2i = Shoot.find_rock(td, 17, 7, [1, 2, 3], 8, 90, -70, 70)
	h.check("found rock in B2/B3 for the set", found.x != -9999, found)
	R = found + Vector2i(4, 2)
	h.note("set", {"room": R, "biome": td.get_biomev(R)})
	Shoot.clear_hazards(lava, field, found, 17, 7)
	await h.reveal(Shoot.rect(found, 17, 7))
	var open: Array = []
	for x in 12:
		open.append(_c(x, 0))
	for x in 8:
		open.append(_c(x, 1))
		open.append(_c(x, 2))
	var pit: Array = [_c(9, 1), _c(10, 1), _c(11, 1)]
	await h.clear_tiles(open + pit)
	for c in pit:
		lava.mass[c] = 1.0
		lava.shown[c] = 1.0
	lava.wake_all()
	var pocket: Array = []
	for x in range(-3, 0):
		for y in range(0, 3):
			pocket.append(_c(x, y))
	field.add_pocket(pocket)
	await h.teleport_tile(_c(2, 2))
	await h.wait(3.0)
	h.snap_camera()
	await h.wait(1.0)
	_guard(h)

	Shoot.clip(h, "fire_sealed")
	await h.wait(2.0)
	await h.shot("sealed")
	await _fly(h, "ui_left", func(): return field.breaches > 0, 30.0)
	h.check("the keeper's drill opened the pocket", field.breaches > 0, field.stats())
	Shoot.clip(h, "fire_burst")
	await h.wait(0.3)
	await _fly(h, "ui_right", func(): return h.keeper_tile().x >= R.x + 5, 4.0)
	await h.wait(1.0)
	await h.shot("gas_rolls")
	var lit: bool = await h.until(func(): return field.ignitions > 0, 25.0)
	h.check("the gas caught on the lava", lit, field.stats())
	Shoot.clip(h, "fire_lit")
	for i in 6:
		await h.wait(0.5)
		await h.shot("fire_%d" % i)
	await h.until(func(): return field.fire.is_empty(), 20.0)
	await h.wait(2.0)
	await h.shot("burnt_out")
	Shoot.clip(h, "fire_end")
	h.note("stats", field.stats())
	guard = false
