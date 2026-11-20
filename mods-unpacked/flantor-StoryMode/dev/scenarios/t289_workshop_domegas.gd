extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 289: Workshop footage, gas building up in the dome. Run it under
# Movie Maker (see dev/workshop_shoot.gd). Gas climbs a shaft under the dome
# and vents in; the haze thickens and the keeper's toxin bar fills.

const Shoot = preload("res://mods-unpacked/flantor-StoryMode/dev/workshop_shoot.gd")
static var _Shoot = Shoot  # calls go through this: lazy_preload makes const-preload calls slow
const TIMEOUT := 900


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	_Shoot.window_1080()
	h.disable_waves()
	await h.until(func(): return Level.map.get_node_or_null("StoryGasField") != null, 10.0)
	var field = Level.map.get_node("StoryGasField")
	await h.wait(3.0)
	var col := -999
	for x in range(-3, 4):
		if col == -999 and field._is_sky(Vector2i(x, -1)) and field.under_dome(Vector2i(x, 0)):
			col = x
	h.check("a shaft under the dome", col != -999, col)
	var shaft: Array = []
	for y in 6:
		shaft.append(Vector2i(col, y))
	await h.reveal(shaft)
	await h.clear_tiles(shaft)
	await h.wait(1.0)
	h.snap_camera()
	_Shoot.clip(h, "dome_start")
	for i in 14:
		if field.toxin > 70.0:
			field.freeze_toxin = true
		field.fill([Vector2i(col, 5), Vector2i(col, 4)], 2.5)
		await h.wait(0.5)
		if i % 4 == 3:
			await h.shot("dome_gas_%d" % i)
	field.freeze_toxin = true
	await h.wait(3.0)
	await h.shot("dome_gas_full")
	_Shoot.clip(h, "dome_end")
	h.check("gas built up in the dome", field.dome.amount > 3.0, field.dome.amount)
