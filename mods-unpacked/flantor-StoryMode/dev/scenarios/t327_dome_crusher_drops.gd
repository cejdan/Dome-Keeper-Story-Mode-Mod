extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 327: the Engineer carries every Story Mode drop (each mod mineral,
# miner bones, a translator) and vanilla iron into the dome and takes the dome
# computer. Taking a station pulls every carried drop to the dome's target for
# its type (Keeper.enterStation -> Dome.getDropTarget): minerals and bones go
# to the crusher and are paid for, the translator to the relic socket. Nothing
# may be left floating with no target, unpickable, or fall out of the dome.
#
# Two trips, each with one of every type picked up in a room under the dome:
#   fly    the keeper flies up into the dome and takes the computer (what a
#          player does; the dome's shredder area and relic socket take what
#          reaches them on the way in, the computer pulls the rest)
#   shaft  the keeper takes the computer while the load is still in the room
#          below, out of reach of the dome's areas, so the computer's pull is
#          all that brings it in (where #327's bones fell down the shaft)
#   jam    as shaft, with the translator (left carried, and frozen by the
#          paused world) put right above the pieces: they must work their way
#          past it (a piece wedged under it stayed there for good before #327)
#
# `-Extra "--carry=<type,...>"` carries only those types (default: all).
# `-Extra "--vanilla"`: the same in Relic Hunt with iron, water and sand (fly
# and shaft trips), to show vanilla delivery is unchanged.

const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
static var _Minerals = Minerals  # calls go through this: lazy_preload makes const-preload calls slow
const Bones = preload("res://mods-unpacked/flantor-StoryMode/data/bones.gd")
static var _Bones = Bones  # calls go through this: lazy_preload makes const-preload calls slow

const TIMEOUT := 330
const UNDER := Vector2i(0, 3)


func boot() -> Dictionary:
	if _vanilla():
		return {"mode": "relichunt", "seed": 12345}
	return {"seed": 12345}


func _vanilla() -> bool:
	return OS.get_cmdline_user_args().has("--vanilla")


func _types() -> Array:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--carry="):
			return Array(a.substr(8).split(","))
	if _vanilla():
		return ["iron", "water", "sand"]
	return ["iron"] + _Minerals.MOD_MINERALS + [_Bones.TYPE, "translator"]


func _row(d) -> Dictionary:
	if not is_instance_valid(d):
		return {"gone": true}
	return {
		"type": d.type, "pos": d.global_position.round(), "absorbed": d.absorbed,
		"independent": d.independent, "carried": d.isCarried(), "target": str(d.dropTargetRef),
		"layer": d.collision_layer, "mask": d.collision_mask, "pickable": d.canFocusCarry(),
		"still_for": snappedf(d.independantTimeSinceLastMove, 0.01) if "independantTimeSinceLastMove" in d else null,
	}


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	var k = h.keeper()
	var dome = Level.getDome("team1")
	h.note("keeper", {"class": k.get_script().resource_path, "player": k.playerId})
	h.note("places", {"station_keeper_pos": dome.stations[0].getKeeperPosition(), "shredder": dome.getDropTarget("iron").global_position, "relic": dome.RelicDropPoint.global_position, "dome": dome.global_position})
	# Max jetpack, so the Engineer lifts the whole load (eleven drops).
	if not _vanilla():
		load("res://mods-unpacked/flantor-StoryMode/dev/boss_dev.gd").give_gear()
	await h.dig_room(UNDER + Vector2i(-2, -3), UNDER + Vector2i(2, 1))
	await _trip(h, "fly")
	await h.press("ui_cancel")
	await h.until(func(): return not k.isInsideStation and not GameWorld.paused, 5.0)
	await h.wait(0.5)
	await _trip(h, "shaft")
	if _vanilla():
		return
	await h.press("ui_cancel")
	await h.until(func(): return not k.isInsideStation and not GameWorld.paused, 5.0)
	await h.wait(0.5)
	await _trip(h, "jam", ["mythril", "diamond", "iron", _Bones.TYPE, "translator"])


# `jam`: as `shaft`, but the translator (which a station leaves carried, and
# the paused world then freezes in place) is put right above the pieces, so
# they are pulled up into it and must work their way past.
func _trip(h, mode: String, types: Array = []) -> void:
	if types.is_empty():
		types = _types()
	var k = h.keeper()
	var dome = Level.getDome("team1")
	var st = dome.stations[0]
	await h.teleport_tile(UNDER)
	await h.wait(0.5)
	# Ore the dig broke out (and anything left from the last trip) would be
	# sold too: clear it away first.
	for c in h.get_tree().get_nodes_in_group("carryable"):
		if "absorbed" in c and not c.absorbed and c.global_position.distance_to(k.global_position) < 200.0:
			h.note("%s: cleared a stray %s" % [mode, c.type], c.global_position)
			c.remove()
	await h.wait(0.3)
	var drops: Array = []
	var inv0: Dictionary = {}
	for t: String in types:
		inv0[t] = int(h.inv(t))
		var d = Level.drops.network_spawn({"type": t, "position": k.global_position + Vector2(randf_range(-6, 6), 4), "impulse": Vector2.ZERO})
		if t == _Bones.TYPE:
			d.value = _Bones.value_for(2)
			d.biome = 2
		drops.append(d)
		await h.frames(2)
		Level.drops.network_pickup(d, k.playerId)
		await h.frames(2)
	await h.wait(0.5)
	h.check("%s: the Engineer carries all %d drops" % [mode, drops.size()], drops.all(func(d): return k.carriedCarryables.has(d)), drops.map(_row))
	await h.shot(mode + "_carrying")
	if mode == "fly":
		for i in 8:
			await h.hold("ui_up", 1.5)
			if k.isInsideDome and Level.map.getTileCoord(k.global_position).y <= -5:
				break
		await h.wait(0.5)
		h.check("fly: the keeper flew into the dome", k.isInsideDome, Level.map.getTileCoord(k.global_position))
		await h.shot("fly_in_dome")
	h.note("%s: before the computer" % mode, drops.map(_row))

	var m0: int = int(h.inv("money"))
	var y0: Dictionary = {}
	for i in drops.size():
		# Taken already on the way in: count it from where it was carried.
		y0[types[i]] = drops[i].global_position.y if is_instance_valid(drops[i]) else 0.0
	var in_station: bool = st.useHit(k)
	await h.until(func(): return k.isInsideStation, 5.0)
	h.check("%s: the keeper takes the dome computer" % mode, k.isInsideStation, in_station)
	await h.frames(10)
	h.note("%s: just after taking the computer" % mode, drops.map(_row))
	if mode == "jam":
		# Right above the pieces, which then rise into it (as the iron did
		# under a carried translator in a shaft trip before the fix).
		var under: Array = drops.filter(func(d): return is_instance_valid(d) and d.type != "translator" and d.dropTargetRef != null)
		var mid := Vector2.ZERO
		for d in under:
			mid += d.global_position / under.size()
		for d in drops:
			if d.type == "translator":
				d.global_position = mid + Vector2(0, -14)
		h.note("jam: the frozen translator put right above the pieces", drops.map(_row))
	if mode != "fly":
		# The station view shows the dome from outside: look at the shaft.
		var cam = Level.viewports.getPlayerCam(k.playerId)
		cam.position = Level.map.getTilePos(UNDER + Vector2i(0, -3))
	await h.burst(mode + "_pull", 8, 8)

	# The crusher takes one piece a second at its slowest.
	var lowest: Dictionary = {}
	var unstuck: Dictionary = {}
	var t_end: float = h.now() + drops.size() * 1.2 + 8.0
	while h.now() < t_end:
		for d in drops:
			if is_instance_valid(d):
				lowest[d.type] = maxf(lowest.get(d.type, -INF), d.global_position.y)
				# The stuck check let it pass through what held it.
				if d.independent and not d.get_collision_mask_value(CONST.LAYER_DROP_COLLISION) and not unstuck.has(d.type):
					unstuck[d.type] = d.global_position.round()
		if drops.all(func(d): return not is_instance_valid(d) or d.absorbed or not d.independent):
			break
		await h.wait(0.25)
	await h.wait(1.5)
	await h.shot(mode + "_after")
	h.note("%s: after" % mode, drops.map(_row))
	h.note("%s: let through by the stuck check (where)" % mode, unstuck)
	h.note("%s: lowest y per type after the computer, and where each was when it was taken" % mode, {"lowest": lowest, "at_computer": y0})

	var paid: int = int(h.inv("money")) - m0
	var expect_paid: int = 0
	for i in drops.size():
		var t: String = types[i]
		var d = drops[i]
		var gone: bool = not is_instance_valid(d) or d.absorbed
		# More than two tiles below where it was when the computer was taken.
		var fell: bool = lowest.get(t, -INF) > y0[t] + 48.0
		var crushable: bool = _Minerals.is_mineral(t) or t == _Bones.TYPE or ["water", "sand"].has(t)
		if _vanilla():
			pass  # no money in Relic Hunt
		elif t == _Bones.TYPE:
			expect_paid += _Bones.value_for(2)
		elif _Minerals.is_mineral(t):
			expect_paid += _Minerals.value_of(t)
		var counted: bool = int(h.inv(t)) == inv0[t] + 1
		if crushable:
			h.check("%s: %s crushed and counted (inventory %d -> %d)" % [mode, t, inv0[t], int(h.inv(t))], gone and counted, _row(d))
		else:
			h.note("%s: %s delivered %s (inventory %d -> %d)" % [mode, t, gone and counted, inv0[t], int(h.inv(t))], _row(d))
		h.check("%s: %s does not fall (lowest y %.0f, %.0f at the computer)" % [mode, t, lowest.get(t, 0.0), y0[t]], not fell, _row(d))
		if not gone:
			h.check("%s: %s left behind solid and pickable" % [mode, t], not d.independent and d.canFocusCarry() and d.get_collision_layer_value(CONST.LAYER_CARRYABLES) and d.get_collision_mask_value(CONST.LAYER_DROP_COLLISION), _row(d))
	h.check("%s: paid $%d for what was crushed (expected $%d)" % [mode, paid, expect_paid], paid == expect_paid, {"paid": paid, "expected": expect_paid})
	# A look at whatever was left behind, out of the station.
	var left: Array = drops.filter(func(d): return is_instance_valid(d) and not d.absorbed)
	if not left.is_empty():
		await h.press("ui_cancel")
		await h.until(func(): return not k.isInsideStation and not GameWorld.paused, 5.0)
		var cam = Level.viewports.getPlayerCam(k.playerId)
		for i in 10:
			cam.position = left[0].global_position
			await h.frames(1)
		await h.shot(mode + "_left_behind")
		h.note("%s: left behind" % mode, left.map(_row))
