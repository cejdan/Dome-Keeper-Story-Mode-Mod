extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 289: Workshop footage, the gas. Run it under Movie Maker (see
# dev/workshop_shoot.gd); "clip" notes give the frames to cut at.
#
# 1. A mine in B2/B3 the way a player digs one: a room with alcoves in its
#    ceiling, a shaft down from its right end and a tunnel along the bottom.
#    The keeper drills from the tunnel into the green cracks of a gas pocket;
#    the pocket bursts, the keeper runs for the shaft and up into the room,
#    and the gas comes after it, climbs the shaft and rolls under the
#    ceiling. The keeper flies back through the cloud.
# 2. The surface: gas leaving the mine in a plume beside the dome.
#
#   ...##.....##....      alcoves                           y -1
#   ................      the room                          y 0..2
#   #############.##      the shaft                         y 3..4
#   ##GGGG#######.##      G the pocket                      y 4..6
#   ##GGGG........##      the tunnel                        y 5

const Shoot = preload("res://mods-unpacked/flantor-StoryMode/dev/workshop_shoot.gd")
const TIMEOUT := 900

var R := Vector2i.ZERO
var field
var guard := true


func boot() -> Dictionary:
	return {"seed": 12345}


func _c(x: int, y: int) -> Vector2i:
	return R + Vector2i(x, y)


# Keeps the keeper alive in the cloud: the bar stops short of full.
func _guard(h) -> void:
	while guard:
		if field.toxin > 55.0:
			field.freeze_toxin = true
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
	var lava = Level.map.get_node("StoryLavaField")
	var td = Level.map.tileData
	var found: Vector2i = Shoot.find_rock(td, 18, 10, [1, 2, 3], 8, 90, -70, 70)
	h.check("found rock in B2/B3 for the set", found.x != -9999, found)
	R = found + Vector2i(1, 2)
	h.note("set", {"room": R, "biome": td.get_biomev(R)})
	Shoot.clear_hazards(lava, field, found, 18, 10)
	await h.reveal(Shoot.rect(found, 18, 10))
	var open: Array = [_c(3, -1), _c(4, -1), _c(10, -1), _c(11, -1), _c(13, 3), _c(13, 4)]
	for x in 16:
		for y in 3:
			open.append(_c(x, y))
	for x in range(6, 14):
		open.append(_c(x, 5))
	await h.clear_tiles(open)
	var pocket: Array = []
	for x in range(2, 6):
		for y in range(4, 7):
			pocket.append(_c(x, y))
	field.add_pocket(pocket)
	await h.teleport_tile(_c(8, 5))
	await h.wait(3.0)
	h.snap_camera()
	await h.wait(1.0)

	# ---- 1. the breach
	Shoot.clip(h, "gas_sealed")
	await h.wait(3.0)
	await h.shot("sealed")
	Shoot.clip(h, "gas_drill")
	await _fly(h, "ui_left", func(): return field.breaches > 0, 30.0)
	h.check("the keeper's drill opened the pocket", field.breaches > 0, field.stats())
	Shoot.clip(h, "gas_burst")
	_guard(h)
	await h.wait(0.5)
	await _fly(h, "ui_right", func(): return h.keeper_tile().x >= R.x + 13, 6.0)
	await _fly(h, "ui_up", func(): return h.keeper_tile().y <= R.y + 1, 6.0)
	await _fly(h, "ui_left", func(): return h.keeper_tile().x <= R.x + 8, 4.0)
	h.keeper().set("gravity_scale", 0.0)
	await h.wait(1.0)
	await h.shot("gas_climbs")
	await h.wait(4.0)
	await h.shot("gas_rolls")
	Shoot.clip(h, "gas_wake")
	await _fly(h, "ui_left", func(): return h.keeper_tile().x <= R.x + 1, 4.0)
	await h.wait(0.6)
	await _fly(h, "ui_right", func(): return h.keeper_tile().x >= R.x + 14, 5.0)
	await h.wait(1.0)
	await h.shot("in_the_cloud")
	await h.wait(2.0)
	Shoot.clip(h, "gas_wake_end")
	h.note("toxin", {"toxin": field.toxin, "stats": field.stats()})

	guard = false
