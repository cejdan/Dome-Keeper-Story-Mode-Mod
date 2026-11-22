extends RefCounted

# Miner bones carried home by a drone yard drone or the drone cave's Squidley
# (#280). Vanilla's drones keep only the carried drop's type: at the dome they
# spawn a fresh drop of that type (TransportDrone.releaseToShredder), and a
# fresh bones drop is worth $0 with no biome, so its sale paid nothing and
# opened the first biome's log at most. The drone now keeps the bones' value
# and biome (`of` at pickup, kept in its save) and gives them to the drop it
# spawns (`hook`, `respawn`), so the shredder sells drone-delivered bones
# the way it sells a keeper's (drops/BonesDrop.gd).

const TYPE := "minerbones"


# What a drone picking up `drop` keeps of it: the bones' value and biome, or
# nothing for any other drop.
static func of(drop) -> Dictionary:
	if is_instance_valid(drop) and drop.type == TYPE and "value" in drop:
		return {"value": drop.value, "biome": drop.biome}
	return {}


static func apply(drop, cargo: Dictionary) -> void:
	if cargo.is_empty() or not is_instance_valid(drop) or drop.type != TYPE:
		return
	drop.value = int(cargo.get("value", 0))
	drop.biome = int(cargo.get("biome", 0))


# For a drone's retrieve (vanilla's spawns the drop at the dome): a
# drop_spawned listener that gives `cargo` to the first bones drop spawned,
# or a null Callable when there is nothing to give. The host spawns it in
# DropSynchronizer.network_spawn, which emits drop_spawned before it returns,
# so the drone connects it only around vanilla's retrieve. Clients spawn
# nothing there; only the host sells (BonesDrop._sold).
static func hook(cargo: Dictionary) -> Callable:
	if cargo.is_empty() or Level.drops == null:
		return Callable()
	var left: Dictionary = cargo.duplicate()
	return func(drop):
		if not left.is_empty() and is_instance_valid(drop) and drop.type == TYPE:
			apply(drop, left)
			left.clear()


# Vanilla's kill for a drone carrying bones (TransportDrone.kill,
# Squidley.kill): the carried piece falls where the drone was, with its value.
static func respawn(drone, cargo: Dictionary) -> void:
	drone.queue_free()
	Data.changeByInt("inventory.total" + drone.carriedResource, -1)
	var drop = Data.DROP_SCENES.get(drone.carriedResource).instantiate()
	apply(drop, cargo)
	drop.position = drone.get_node("CarriedResource").global_position
	Level.map.call_deferred("addDrop", drop)
