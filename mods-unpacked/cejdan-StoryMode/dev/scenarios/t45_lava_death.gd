extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 45: an overheat in lava recalls the keeper, drops its cargo where it
# died, and takes half the money (none from $0).


func boot() -> Dictionary:
	return {"seed": 12345}


func _lava_room(h, field, c: Vector2i) -> void:
	await h.dig_room(c + Vector2i(-1, -1), c + Vector2i(1, 1))
	for y in range(-1, 2):
		for x in range(-1, 2):
			field.mass[c + Vector2i(x, y)] = 1.0 + 0.25 * (y + 1)
	field.wake_all()


func _die(h, field, c: Vector2i, label: String) -> Dictionary:
	var r0: int = field.recalls
	await h.teleport_tile(c)
	await h.until(func(): return field.recalls > r0, 10.0)
	await h.frames(3)
	h.snap_camera()
	await h.wait(0.6)
	await h.shot(label)
	var k = h.keeper()
	var dome = Level.getDome("team1")
	return {"recalled": field.recalls > r0, "keeper_tile": h.keeper_tile(), "near dome": k.global_position.distance_to(dome.global_position) < 24 * 6, "money": h.inv("money"), "penalty": field.last_penalty}


func run(h) -> void:
	h.disable_waves()
	var field = Level.map.get_node("StoryLavaField")
	field.magma.clear()
	var c: Vector2i = Vector2i(6, 14)
	await _lava_room(h, field, c)

	# $1,001 and a carried piece of cargo.
	h.set_inv("money", 1001)
	await h.teleport_tile(c + Vector2i(0, -3))
	Level.drops.network_spawn({"type": "bronze", "position": h.keeper().global_position, "carriers": ["player1"], "team": "team1"})
	await h.wait(1.0)
	var carried: int = h.keeper().carriedCarryables.size()
	h.check("the keeper carries cargo", carried > 0, carried)
	var r: Dictionary = await _die(h, field, c, "after_death_1001")
	h.note("death with $1,001", r)
	h.check("overheat recalls the keeper to the dome", r["recalled"] and r["near dome"], r)
	h.check("money goes 1001 -> 501", int(r["money"]) == 501 and int(r["penalty"]) == 500, r)
	var dropped_near: bool = false
	for d in Level.drops.find_children("*", "", true, false):
		if is_instance_valid(d) and "type" in d and d.type == "bronze":
			if d.global_position.distance_to(Level.map.getTilePos(Vector2(c))) < 24 * 5:
				dropped_near = true
	h.check("the cargo was dropped where the keeper died", h.keeper().carriedCarryables.size() == 0 and dropped_near)

	# Again with $0.
	h.set_inv("money", 0)
	await h.wait(1.0)
	var r2: Dictionary = await _die(h, field, c, "after_death_0")
	h.note("death with $0", r2)
	h.check("with $0 the recall still happens and the balance stays $0", r2["recalled"] and int(r2["money"]) == 0 and int(r2["penalty"]) == 0, r2)
