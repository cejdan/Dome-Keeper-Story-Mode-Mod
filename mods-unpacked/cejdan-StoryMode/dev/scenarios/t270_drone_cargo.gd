extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 270: drone yard drones carrying Story Mode minerals show them in their
# claws and play the carry animation. A Story run with the drone yard; gold
# pieces lie in a room under the dome; a drone fetches one. Also: every Story
# piece's carry art, a pack with Story pieces, and the drone cave's Squidley.

const TIMEOUT := 180
const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")
const Bones = preload("res://mods-unpacked/cejdan-StoryMode/data/bones.gd")


func boot() -> Dictionary:
	return {"seed": 12345, "gadget": "droneyard"}


func _drones(h) -> Array:
	return h.get_tree().get_nodes_in_group("team1-transport_drones").filter(func(d): return is_instance_valid(d))


func run(h) -> void:
	h.disable_waves()
	h.set_inv("money", 100000)
	await h.wait(1.0)
	if _drones(h).is_empty():
		await h.buy("droneyarddrones")
	await h.until(func(): return not _drones(h).is_empty(), 15.0)
	h.check("the drone yard has drones", not _drones(h).is_empty(), _drones(h).size())

	# A room a few tiles under the dome, with gold pieces lying in it.
	var a := Vector2i(-4, 5)
	var b := Vector2i(4, 8)
	await h.dig_room(a, b)
	await h.dig_room(Vector2i(0, 0), Vector2i(1, 4))
	await h.teleport_tile(Vector2i(-2, 8))
	await h.wait(1.0)
	for i in 4:
		Level.drops.network_spawn({"type": "gold", "position": Level.map.getTilePos(Vector2i(2 + (i % 2), 8)) + Vector2(0, -2), "impulse": Vector2.ZERO})
		await h.frames(4)
	await h.wait(2.0)
	await h.shot("gold_in_room")
	h.note("gold drops", h.get_tree().get_nodes_in_group("drops").filter(func(d): return d.type == "gold").map(func(d): return {"type": d.carryableType, "can": TransportDrone.canTransport(d), "v": d.linear_velocity.length(), "ignore": d.is_in_group("ignore-for-auto-transport"), "pos": d.global_position}))
	h.note("drones", _drones(h).map(func(d): return {"state": d.state, "pos": d.global_position, "disp": d.dispatcherId, "path": Level.map.findPath(d.position, Level.map.getTilePos(Vector2i(2, 8)), "team1")}))
	var carrying := func():
		for d in _drones(h):
			if Minerals.is_mod_mineral(d.carriedResource):
				return d
		return null
	var got: bool = await h.until(func(): return carrying.call() != null, 60.0)
	var carrier = carrying.call()
	h.check("a drone picks up a Story mineral", got and carrier != null, carrier.carriedResource if carrier else null)
	if carrier == null:
		return
	await h.frames(2)
	var tex = carrier.get_node("CarriedResource").texture
	h.check("it shows the mineral in its claws", tex != null and tex.get_width() <= 10, [tex.get_width() if tex else null])
	# (Standing still, vanilla's drone body plays "idle" even with iron; the
	# claws overlay carries, and the body carries once it flies.)
	var over = carrier.get_node("SpriteOverlay")
	var flying: bool = await h.until(func(): return not is_instance_valid(carrier) or str(carrier.get_node("Sprite").animation).begins_with("carry_"), 5.0)
	h.check("and plays the carry animation", flying and is_instance_valid(carrier) and over.visible and str(over.animation).begins_with("carry"), [str(carrier.get_node("Sprite").animation) if is_instance_valid(carrier) else null, over.animation if is_instance_valid(carrier) else null])
	# Follow it home for the pictures (zoomed in on the drone).
	for i in 3:
		if not is_instance_valid(carrier) or carrier.carriedResource == "":
			break
		h.keeper().teleport(carrier.global_position + Vector2(0, 12))
		h.snap_camera()
		await h.frames(2)
		await h.shot("drone_carrying_%d" % i)
		await h.wait(0.5)
	var m0: int = int(h.inv("gold"))
	var home: bool = await h.until(func(): return int(h.inv("gold")) > m0 or int(h.inv("money")) > 100000, 40.0)
	h.check("the drone delivers it", home, [h.inv("gold"), h.inv("money")])

	# Every Story piece, a pack, and the drone cave's Squidley.
	var drone = load("res://content/gadgets/droneyard/TransportDrone.tscn").instantiate()
	Level.map.add_child(drone)
	var missing: Array = []
	for t: String in Minerals.MOD_MINERALS + [Bones.TYPE]:
		drone.setCarriedResource(t)
		if drone.get_node("CarriedResource").texture == null or not str(drone.get_node("Sprite").animation).begins_with("carry"):
			missing.append(t)
	h.check("every Story piece has carry art on a drone", missing.is_empty(), missing)
	drone.setCarriedResource("")
	drone.packedDropContent = [["gold", 0, 0], ["iron", 2, 0], ["ruby", -2, 1]]
	drone.setCarriedResource(CONST.PACK)
	var kids: Array = drone.get_node("CarriedResource").get_children()
	h.check("a pack shows its Story pieces too", kids.size() == 3 and kids.all(func(k): return k.texture != null), kids.map(func(k): return k.texture != null))
	drone.queue_free()
	var squid = load("res://content/gadgets/droneyard/Squidley.tscn").instantiate()
	Level.map.add_child(squid)
	squid.setCarriedResource("sapphire")
	h.check("the drone cave's Squidley shows it too", squid.get_node("CarriedResource").texture != null)
	squid.queue_free()
	await h.frames(2)
