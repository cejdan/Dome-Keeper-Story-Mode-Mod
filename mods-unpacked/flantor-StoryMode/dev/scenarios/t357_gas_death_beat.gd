extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 357: a gas death plays its own beat (gas_death_1), not the lava
# overheat one, and doesn't use up the lava beat. The keeper is gassed, then
# overheats in lava, then is gassed again: gas_death_1, lava_death_1, nothing.

const GasData = preload("res://mods-unpacked/flantor-StoryMode/data/gas.gd")


func boot() -> Dictionary:
	return {"seed": 12345, "beats": true}


var gas
var lava
var room := Vector2i(0, 6)


func _room_cells() -> Array:
	var out: Array = []
	for y in range(-1, 2):
		for x in range(-1, 2):
			out.append(room + Vector2i(x, y))
	return out


func _clear_gas() -> void:
	gas.mass.clear()
	gas.wake_all()


func _gas_death(h, label: String) -> String:
	await h.teleport_tile(room)
	await h.wait(0.5)
	var r0: int = lava.recalls
	gas.fill(_room_cells(), 1.2)
	var died: bool = await h.until(func(): return lava.recalls > r0, 15.0)
	h.check("%s: the gas recalls the keeper" % label, died, [gas.gassed, lava.recalls])
	_clear_gas()
	return await h.read_beat(label, 8.0, true)


func _lava_death(h, label: String) -> String:
	await h.teleport_tile(room)
	await h.wait(0.5)
	var r0: int = lava.recalls
	lava.heat = lava.HEAT_MAX + 5.0
	var died: bool = await h.until(func(): return lava.recalls > r0, 5.0)
	h.check("%s: the heat recalls the keeper" % label, died, lava.recalls)
	return await h.read_beat(label, 8.0, true)


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	await h.until(func(): return Level.map.get_node_or_null("StoryGasField") != null, 10.0)
	gas = Level.map.get_node("StoryGasField")
	lava = Level.map.get_node("StoryLavaField")
	_clear_gas()
	await h.dig_room(room + Vector2i(-1, -1), room + Vector2i(1, 1))

	var got: Array = []
	got.append(await _gas_death(h, "gas1"))
	await h.wait(0.8)
	got.append(await _lava_death(h, "lava1"))
	await h.wait(0.8)
	got.append(await _gas_death(h, "gas2"))
	h.note("beats per death", got)
	h.check("gas plays gas_death_1, then lava still plays lava_death_1, then gas again nothing", got == ["gas_death_1", "lava_death_1", ""], got)
	h.check("3 recalls, 2 of them gas", lava.recalls == 3 and lava.gas_recalls == 2, [lava.recalls, lava.gas_recalls])
