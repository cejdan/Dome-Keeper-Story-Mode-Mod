extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 44: Heat Shielding I-IV. Run with -Extra "--mode=relichunt" to check
# vanilla doesn't offer it.

const LavaData = preload("res://mods-unpacked/cejdan-StoryMode/data/lava.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


func _cost(i: int) -> int:
	return int(GameWorld.upgrades.get("team1.storyheatshield%d" % i, {}).get("cost", {}).get("money", -1))


func _shop_shot(h, label: String) -> void:
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	for i in 24:
		await h.press("ui_down")
		await h.wait(0.15)
	# Onto the Story Mode track's first entry, then down to its last row.
	await h.press("ui_right")
	await h.wait(0.2)
	for i in 8:
		await h.press("ui_down")
		await h.wait(0.15)
	await h.shot(label)
	await h.press("ui_cancel")
	await h.wait(1.0)


# Seconds from 0 heat to an overheat (the recall), standing in deep lava.
func _time_to_overheat(h, field, cell: Vector2i) -> float:
	field.heat = 0.0
	var r0: int = field.recalls
	await h.teleport_tile(cell)
	await h.frames(2)
	var t0: float = h.now()
	var ok: bool = await h.until(func(): return field.recalls > r0, 60.0)
	return h.now() - t0 if ok else -1.0


func run(h) -> void:
	h.disable_waves()
	if Level.loadout.modeId != "storymode":
		h.check("vanilla doesn't offer Heat Shielding", not GameWorld.upgrades.has("team1.storyheatshield1") and not GameWorld.upgrades.has("storyheatshield1"))
		return

	h.check("the shop offers Heat Shielding I at $200", _cost(1) == 200, _cost(1))
	# The shop's panels go by GameWorld.isUpgradeAddable (Tech2.updateState).
	h.check("tier II isn't buyable in the shop before tier I", GameWorld.upgrades.has("team1.storyheatshield2") and not GameWorld.isUpgradeAddable("team1.storyheatshield2"))
	h.set_inv("money", 40000)
	await _shop_shot(h, "shop_before")
	var tiers: Array = []
	for i in range(1, 5):
		var m0: int = int(h.inv("money"))
		var ok: bool = await h.buy("storyheatshield%d" % i)
		var nid: String = "team1.storyheatshield%d" % (i + 1)
		tiers.append({"tier": i, "bought": ok, "paid": m0 - int(h.inv("money")), "next offered": GameWorld.upgrades.has(nid) and GameWorld.isUpgradeAddable(nid)})
		if i == 2:
			await _shop_shot(h, "shop_after_II")
	h.note("purchases", tiers)
	h.check("I-IV cost $200, $1,000, $4,000, $25,000", tiers.map(func(t): return t["paid"]) == [200, 1000, 4000, 25000], tiers)
	h.check("each tier unlocks the next", tiers[0]["next offered"] and tiers[1]["next offered"] and tiers[2]["next offered"], tiers)
	h.check("the suit is at tier IV", LavaData.shield_tier("team1") == 4, LavaData.shield_tier("team1"))

	# A sealed 3 x 3 room of deep lava to stand in.
	var field = Level.map.get_node("StoryLavaField")
	field.magma.clear()
	var c: Vector2i = Vector2i(6, 14)
	await h.dig_room(c + Vector2i(-1, -1), c + Vector2i(1, 1))
	for y in range(-1, 2):
		for x in range(-1, 2):
			field.mass[c + Vector2i(x, y)] = 1.0 + 0.25 * (y + 1)
	field.wake_all()
	await h.teleport_tile(c)
	await h.wait(1.0)
	await h.shot("in_lava")
	var rows: Array = []
	for tier in range(0, 5):
		Data.apply("team1." + LavaData.HEAT_SHIELD_KEY, tier)
		var want: float = 100.0 / (55.0 * float(LavaData.HEAT_SHIELD_LAVA_MULT[tier]))
		var got: float = await _time_to_overheat(h, field, c)
		rows.append({"tier": tier, "seconds": snappedf(got, 0.01), "expected": snappedf(want, 0.01)})
		h.check("tier %d: 0 to 100 heat in %.2f s (expected %.2f)" % [tier, got, want], got > 0 and absf(got - want) <= want * 0.10, rows.back())
		await h.wait(1.0)
	h.note("overheat times", rows)
	h.check("at tier IV the keeper still overheats in lava", rows[4]["seconds"] > 0)
