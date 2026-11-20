extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 213: vented gas builds up in the dome. Gas leaving the mine up the
# shaft under the dome is counted as the dome's gas (in pockets' worth); a
# green haze over the dome's inside thickens with it; in the dome the toxin bar
# fills from it, faster the more there is, and a full bar there is a gas death
# without the trip home; going down into clean air clears the bar; the shop's
# Vent the Dome clears the gas; the amount survives a save and reload.

const GasData = preload("res://mods-unpacked/cejdan-StoryMode/data/gas.gd")
const TIMEOUT := 300
const SLOT := 12

var field
var dome_gas


func boot() -> Dictionary:
	return {"seed": 12345}


func _in_dome(h, home: Vector2) -> void:
	h.keeper().global_position = home
	await h.frames(5)
	h.snap_camera()


func run(h) -> void:
	h.disable_waves()
	await h.until(func(): return Level.map.get_node_or_null("StoryGasField") != null, 10.0)
	field = Level.map.get_node("StoryGasField")
	dome_gas = field.dome
	h.check("the gas field keeps the dome's gas", dome_gas != null)
	var lava = Level.map.get_node("StoryLavaField")
	var cool := func(): lava.heat = 0.0
	Level.map.get_tree().process_frame.connect(cool)
	var dome = Level.domesByTeamId["team1"]
	var home: Vector2 = h.keeper().global_position
	await h.wait(1.0)
	h.check("the keeper starts in the dome, in clean air", h.keeper().isInsideDome and dome_gas.amount == 0.0 and field.toxin == 0.0, [h.keeper().isInsideDome, dome_gas.amount])
	await h.shot("dome_clean")

	# ---- 1. where gas leaves the mine: the top row, under the dome or not
	var row := {}
	for x in range(-12, 13):
		var c := Vector2i(x, 0)
		row[x] = "%s%s%s" % ["S" if field._is_sky(c + Vector2i.UP) else "-", "." if Level.map.is_tile_empty(c) else "#", "D" if field.under_dome(c) else " "]
	h.note("top row: sky above / open / under the dome", {"dome x": dome.global_position.x, "row": row})
	var col := -999
	for x in range(-3, 4):
		if col == -999 and field._is_sky(Vector2i(x, -1)) and field.under_dome(Vector2i(x, 0)):
			col = x
	h.check("the shaft under the dome opens to the air", col != -999, col)
	var shaft: Array = []
	for y in 4:
		shaft.append(Vector2i(col, y))
	await h.reveal(shaft)
	await h.clear_tiles(shaft)
	field.fill([Vector2i(col, 3), Vector2i(col, 2)], 2.0)
	var vented0: float = field.vented
	await h.until(func(): return field.vented - vented0 > 3.9, 15.0)
	await h.wait(0.5)
	h.check("gas vented up the dome's shaft went into the dome", absf(dome_gas.amount - (field.vented - vented0)) < 0.01 and dome_gas.amount > 3.9, [dome_gas.amount, field.vented - vented0])
	await _in_dome(h, home)
	await h.wait(1.0)
	await h.shot("after_venting_4")

	# ---- 2. the haze at 1-5 pockets
	field.freeze_toxin = true
	var seen := []
	for p in [1, 2, 3, 4, 5]:
		dome_gas.amount = p * GasData.DOME_POCKET_MASS
		await h.until(func(): return absf(dome_gas.shown - dome_gas.haze()) < 0.01, 8.0)
		await h.wait(0.3)
		seen.append(snappedf(dome_gas.shown, 0.01))
		await h.shot("haze_%d_pockets" % p)
	h.note("haze shown at 1-5 pockets", seen)
	h.check("the haze thickens with each pocket", seen[0] > 0.1 and seen[0] < seen[1] and seen[1] < seen[2] and seen[2] < seen[3] and seen[3] < seen[4] and seen[4] >= 0.99, seen)
	await h.burst("haze_5_swirl", 6, 8)
	field.freeze_toxin = false

	# ---- 3. the bar in the dome
	var rates := {}
	for p in [1, 3, 5]:
		dome_gas.amount = p * GasData.DOME_POCKET_MASS
		field.toxin = 10.0
		var t0: float = h.now()
		await h.wait(4.0)
		rates[p] = (field.toxin - 10.0) / (h.now() - t0)
	var want := {}
	for p in rates:
		want[p] = GasData.dome_toxin_rate(p)
	h.note("toxin a second in the dome, by pockets (measured, wanted)", [rates, want])
	for p in rates:
		h.check("%d pocket(s): the bar fills at %.2f a second (full in %d s)" % [p, want[p], int(100.0 / want[p])], absf(rates[p] - want[p]) < 0.15 * want[p], rates[p])
	dome_gas.amount = 0.02 * GasData.DOME_POCKET_MASS
	field.toxin = 60.0
	await h.wait(0.3)
	h.check("a mere trace: the dome's air clears the bar at once", field.toxin == 0.0, field.toxin)

	# ---- 4. going down to breathe
	dome_gas.amount = 4 * GasData.DOME_POCKET_MASS
	field.toxin = 60.0
	var below: Vector2i = Vector2i(col, 3)
	await h.teleport_tile(below)
	await h.wait(1.0)
	h.check("below the dome, in clean air, the bar clears", not h.keeper().isInsideDome and field.toxin < 40.0, field.toxin)
	await _in_dome(h, home)

	# ---- 5. a full bar in the dome
	h.set_inv("money", 1000)
	dome_gas.amount = 6 * GasData.DOME_POCKET_MASS
	field.toxin = 95.0
	var gassed0: int = field.gassed
	var died: bool = await h.until(func(): return field.gassed > gassed0, 10.0)
	await h.frames(3)
	await h.shot("gassed_in_dome")
	h.check("a full bar in the dome is a gas death", died, field.gassed)
	h.check("it costs half the money", int(h.inv("money")) == 500, h.inv("money"))
	h.check("the keeper stays in the dome", h.keeper().isInsideDome)
	h.check("the bar starts over", field.toxin < 5.0, field.toxin)
	await h.wait(1.0)
	var bb = h.beat_box()
	if bb != null:
		await h.read_beat("death_line")

	# ---- 6. the shop's vent
	var vent_id := "team1.storyventdome"
	h.check("the shop sells Vent the Dome", GameWorld.upgrades.has(vent_id), GameWorld.upgrades.get(vent_id, {}).get("cost", {}))
	h.set_inv("water", 5)
	dome_gas.amount = 5 * GasData.DOME_POCKET_MASS
	field.toxin = 0.0
	await h.wait(1.0)
	var water0: int = int(h.inv("water"))
	var cost: int = int(GameWorld.upgrades[vent_id]["cost"].get("water", 0))
	h.check("it costs water", cost > 0, cost)
	h.check("the dome has gas, so the vent is for sale", dome_gas.has_gas())
	var ok: bool = await h.buy("storyventdome")
	h.check("bought: the dome's gas is gone", ok and dome_gas.amount == 0.0 and dome_gas.vents == 1, [ok, dome_gas.amount])
	h.check("it took its water", int(h.inv("water")) == water0 - cost, [water0, h.inv("water")])
	await h.wait(0.6)
	await h.shot("venting")
	await h.until(func(): return dome_gas.shown <= 0.0, 6.0)
	await h.shot("vented")
	h.check("the haze cleared", dome_gas.shown <= 0.0, dome_gas.shown)
	h.check("with no gas, the vent is not for sale", not dome_gas.has_gas())
	dome_gas.amount = GasData.DOME_POCKET_MASS
	ok = await h.buy("storyventdome")
	h.check("it can be bought again", ok and dome_gas.amount == 0.0 and dome_gas.vents == 2, [ok, dome_gas.amount, h.inv("water")])

	# ---- 7. save and reload
	dome_gas.amount = 2.5 * GasData.DOME_POCKET_MASS
	await SaveGame.saveGame(SaveGame.get_run_folder(), SLOT, true)
	await h.wait(1.0)
	GameWorld.paused = true
	Level.map.remove_child(field)
	field.queue_free()
	GameWorld.paused = false
	await h.until(func(): return Level.map.get_node_or_null("StoryGasField") != null, 10.0)
	field = Level.map.get_node_or_null("StoryGasField")
	await h.wait(0.5)
	h.check("the dome's gas came back", field != null and absf(field.dome.amount - 2.5 * GasData.DOME_POCKET_MASS) < 0.01, field.dome.amount if field != null else -1)
	await h.wait(4.0)
	await h.shot("reloaded")
	h.check("one haze, not two", dome.get_children().filter(func(n): return n.name.begins_with("StoryGasHaze") and not n.is_queued_for_deletion()).size() <= 2)
