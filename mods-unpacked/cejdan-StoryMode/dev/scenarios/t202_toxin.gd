extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 202: gas poisons the keeper. The green bar fills in gas (faster in
# thick gas than thin), clears out of it and at once in the dome; past 70% it
# flashes, the screen greens at the edges and the sound goes muffled; a full
# bar is the lava's recall (cargo dropped, half the money). Gas a tile away
# does nothing.

const GasData = preload("res://mods-unpacked/cejdan-StoryMode/data/gas.gd")
const C := Vector2i(6, 14)


func boot() -> Dictionary:
	return {"seed": 12345}


var field


func _room_cells() -> Array:
	var out: Array = []
	for y in range(-1, 2):
		for x in range(-2, 3):
			out.append(C + Vector2i(x, y))
	return out


func _gas(density: float) -> void:
	field.mass.clear()
	if density > 0.0:
		field.fill(_room_cells(), density)
	else:
		field.wake_all()


func run(h) -> void:
	h.disable_waves()
	await h.until(func(): return Level.map.get_node_or_null("StoryGasField") != null, 10.0)
	field = Level.map.get_node("StoryGasField")
	var lava = Level.map.get_node("StoryLavaField")
	lava.magma.clear()
	field.rock.clear()
	field.freeze_flow = true
	var fx = field.fx
	h.check("the gas field has its toxin effects", fx != null)
	await h.dig_room(C + Vector2i(-2, -1), C + Vector2i(6, 1))
	await h.teleport_tile(C)
	h.keeper().set("gravity_scale", 0.0)
	await h.wait(3.0)
	h.snap_camera()
	h.check("no toxin in clean air", field.toxin == 0.0 and not fx._rect.visible, field.toxin)
	await h.shot("clean")

	# ---- 1. thick gas: the bar fills at the full rate
	_gas(1.2)
	await h.wait(1.0)
	var t1: float = field.toxin
	h.check("thick gas fills the bar at about %d a second" % int(GasData.TOXIN_PER_SECOND), t1 > 0.8 * GasData.TOXIN_PER_SECOND and t1 < 1.2 * GasData.TOXIN_PER_SECOND, t1)
	await h.shot("filling")
	await h.until(func(): return field.toxin >= 80.0, 5.0)
	field.freeze_toxin = true
	await h.wait(0.8)
	await h.burst("warning", 8, 6)
	h.check("past 70% the screen greens and the sound is muffled", fx._rect.visible and fx.vignette > 0.3 and fx.muffle > 0.2 and fx._lowpass != null, [fx.vignette, fx.muffle])
	var GasSfx = load("res://mods-unpacked/cejdan-StoryMode/gas/gas_sfx.gd")
	h.check("the warning sounds", int(GasSfx.played.get("choke", 0)) >= 1, GasSfx.played)

	# ---- 2. out of the gas: it clears
	_gas(0.0)
	field.freeze_toxin = false
	var t2: float = field.toxin
	await h.wait(1.0)
	h.check("out of the gas the bar clears at about %d a second" % int(GasData.CLEAR_PER_SECOND), t2 - field.toxin > 24.0 and t2 - field.toxin < 36.0, [t2, field.toxin])
	await h.shot("clearing")
	await h.until(func(): return field.toxin <= 0.0, 5.0)
	await h.wait(1.5)
	h.check("clear again: no vignette, no muffling", field.toxin == 0.0 and not fx._rect.visible and fx._lowpass == null, [fx.vignette, fx.muffle])
	h.check("the master bus is as it was", AudioServer.get_bus_effect_count(0) == _master_effects, [AudioServer.get_bus_effect_count(0), _master_effects])

	# ---- 3. thin gas fills it slowly
	_gas(0.15)
	await h.wait(1.0)
	var thin: float = field.toxin
	h.check("thin gas fills the bar much slower", thin > 8.0 and thin < 20.0, thin)
	_gas(0.0)
	await h.until(func(): return field.toxin <= 0.0, 5.0)

	# ---- 4. gas a tile away does nothing
	field.fill([C + Vector2i(2, -1), C + Vector2i(2, 0), C + Vector2i(2, 1)], 1.5)
	await h.wait(1.0)
	h.check("gas two tiles over does nothing", field.toxin == 0.0, field.toxin)
	await h.shot("gas_beside")

	# ---- 5. a full bar: the recall, with half the money
	h.set_inv("money", 1001)
	var r0: int = lava.recalls
	_gas(1.2)
	var done: bool = await h.until(func(): return field.gassed > 0, 5.0)
	await h.frames(3)
	h.snap_camera()
	await h.wait(0.6)
	await h.shot("after_recall")
	var dome = Level.getDome("team1")
	h.check("a full bar recalls the keeper to the dome", done and lava.recalls == r0 + 1 and h.keeper().global_position.distance_to(dome.global_position) < 24 * 6, [field.gassed, lava.recalls])
	h.check("money goes 1001 -> 501", int(h.inv("money")) == 501, h.inv("money"))
	h.check("the bar is empty after the recall", field.toxin == 0.0, field.toxin)
	await h.wait(2.0)
	h.check("the effects are gone after the recall", not fx._rect.visible and fx._lowpass == null, [fx.vignette, fx.muffle])


var _master_effects: int = AudioServer.get_bus_effect_count(0)
