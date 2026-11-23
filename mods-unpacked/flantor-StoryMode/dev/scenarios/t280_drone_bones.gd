extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 280: a drone yard drone carrying miner bones home sells them like a
# keeper delivery: the team is paid the bones' value and their biome's data
# log opens. Before the fix the drone spawned a fresh $0 bones drop at the
# dome. A Story run with the drone yard; B3 bones lie in a room under the
# dome; a drone fetches them.

const TIMEOUT := 180
const Bones = preload("res://mods-unpacked/flantor-StoryMode/data/bones.gd")
static var _Bones = Bones  # calls go through this: lazy_preload makes const-preload calls slow
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
static var _StoryBeats = StoryBeats  # calls go through this: lazy_preload makes const-preload calls slow

const BONES_BIOME := 2


func boot() -> Dictionary:
	return {"seed": 12345, "gadget": "droneyard", "beats": true}


func _drones(h) -> Array:
	return h.get_tree().get_nodes_in_group("team1-transport_drones").filter(func(d): return is_instance_valid(d))


func _money() -> int:
	return int(Data.ofOr("team1.inventory.money", 0))


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	# Every beat played but the bones' log (B3), so nothing else opens.
	Data.apply("team1.story.beatsplayed", "biome_b2,biome_b3,biome_b4,biome_b5,biome_b6,biome_b7,biome_b8,lava_ocean,first_gem,gate_broken,lava_death_1,lava_death_2,lava_death_3,lava_death_4,log_b1,log_b2,log_b4,log_b5,log_b6,log_b7,log_b8")
	h.set_inv("money", 100000)
	if _drones(h).is_empty():
		await h.buy("droneyarddrones")
	await h.until(func(): return not _drones(h).is_empty(), 15.0)
	h.check("the drone yard has drones", not _drones(h).is_empty(), _drones(h).size())

	# A room a few tiles under the dome, the keeper off to one side.
	await h.dig_room(Vector2i(-4, 5), Vector2i(4, 8))
	await h.dig_room(Vector2i(0, 0), Vector2i(1, 4))
	await h.teleport_tile(Vector2i(-2, 8))
	await h.wait(1.0)
	# Ore the dig broke out would be fetched first: clear it away.
	for c in h.get_tree().get_nodes_in_group("drops"):
		if is_instance_valid(c) and c.has_method("remove") and "absorbed" in c and not c.absorbed:
			c.remove()
	await h.wait(0.5)
	var value: int = _Bones.value_for(BONES_BIOME)
	var d = Level.drops.network_spawn({"type": _Bones.TYPE, "position": Level.map.getTilePos(Vector2i(3, 8)) + Vector2(0, -2), "impulse": Vector2.ZERO})
	d.value = value
	d.biome = BONES_BIOME
	var m0: int = _money()
	await h.wait(1.0)
	await h.shot("bones_in_room")

	var carrying := func():
		for dr in _drones(h):
			if dr.carriedResource == _Bones.TYPE:
				return dr
		return null
	var got: bool = await h.until(func(): return carrying.call() != null, 60.0)
	var carrier = carrying.call()
	h.check("a drone picks up the bones", got and carrier != null)
	if carrier == null:
		return
	h.check("it keeps their value and biome", carrier._cargo == {"value": value, "biome": BONES_BIOME}, carrier._cargo)
	h.keeper().teleport(carrier.global_position + Vector2(0, 12))
	h.snap_camera()
	await h.frames(2)
	await h.shot("drone_carrying_bones")

	var paid: bool = await h.until(func(): return _money() > m0, 40.0)
	h.check("the drone delivery pays $%d (got $%d)" % [value, _money() - m0], paid and _money() - m0 == value, {"m0": m0, "m1": _money()})
	var log_id: String = "log_b%d" % (BONES_BIOME + 1)
	var opened: bool = await h.until(func(): return _StoryBeats.instance().open_id == log_id, 8.0)
	h.check("and opens the bones' log (%s)" % log_id, opened, _StoryBeats.instance().open_id)
	if opened:
		await h.read_beat(log_id, 3.0, true)
		await h.wait(0.5)
