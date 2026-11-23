extends "res://content/gadgets/droneyard/DroneDispatcher.gd"

# Drones that Story Mode's rock has cut off (#313). Rock comes back in open
# cells (lava hardened by water), so a drone can end up sealed in rock or in a
# pocket with no way home. It stays there: no way out is made for it.
#
# - tryFindPath: vanilla tries the drone's own cell, then the cell above, below
#   and to each side of it. From a cell with a graph point, the four others
#   are open neighbours in the same part of the graph (or rock), so when the
#   first search finds no way they find none either, after searching that
#   whole part again each: one search is enough. From a cell that is rock, the
#   others would start a path in an open cell beside it and fly the drone out
#   through the rock: no path. And a goal cell with no graph point (rock) is
#   answered at once (vanilla searches, five times, and logs a warning each).
# - The hand-out (_process, vanilla's with the changes marked): a drone in
#   WAIT sealed in rock gets no drop, so the drops near it go to drones that
#   can fetch them. One that fails to get a path to a drop and has no way home
#   either sits the hand-out out for a while, longer each time
#   (TransportDrone.gd), until a cell opens near it.
# - Also in the hand-out: vanilla calls TransportDrone.canTransport for every
#   drop on the map through the class name, ~300 us a call on the Nov 15
#   staging build (gdscript runtime/lazy_preload): with 35 drops lying around,
#   10 ms in one frame every 0.4-0.8 s. Through a static var the 35 calls take
#   47 us (t313_pets). shouldRefreshTargetPath's TransportDrone.State goes
#   through a constant the same way.

const HAND_OUT_RETRY_MS := 1000
const HAND_OUT_RETRY_MAX_MS := 6000
const PICKUP := 1   # TransportDrone.State.PICKUP

static var _TransportDrone = TransportDrone  # calls go through this: lazy_preload makes class-name calls slow


# The drones the hand-out may use: not sealed in rock, not sitting it out.
func _hand_out_drones() -> Array:
	var now: int = Time.get_ticks_msec()
	var out: Array = []
	for drone in getOwnDrones():
		if drone.state == 0:
			if _in_rock(drone.position):
				continue
			if "story_hand_out_after" in drone and drone.story_hand_out_after > now:
				continue
		out.append(drone)
	return out


func _process(delta):
	if GameWorld.paused or not multiplayer.is_server():
		return

	if cooldown > 0.0:
		cooldown -= delta
		return

	cooldown = randf_range(0.4, 0.8)

	var waitingDrones: = []
	var targettedDrops: = []
	for drone in _hand_out_drones():   # changed: was getOwnDrones()
		if drone.state == 0:
			waitingDrones.append(drone)
		elif shouldRefreshTargetPath(drone):
			var targettedDrop: Carryable = drone.targettedDrop
			networkTargetDrop(drone.UID, targettedDrop.UID, drone.global_position, targettedDrop.position, drone.baseSpeed)

		if drone.targettedDrop:
			targettedDrops.append(drone.targettedDrop)

	if waitingDrones.size() == 0:
		return

	var drops = []
	for drop in get_tree().get_nodes_in_group("drops"):
		if drop.carryableType != "resource":
			continue

		if not _TransportDrone.canTransport(drop):   # changed: was TransportDrone.canTransport
			continue

		if targettedDrops.has(drop):
			continue

		if drop.linear_velocity.length() > MAX_NEW_TARGET_SPEED:
			continue

		if drop.is_in_group("ignore-for-auto-transport"):
			continue

		drops.append(drop)

	drops.sort_custom(sortByDistance)

	while (waitingDrones.size() > 0 and drops.size() > 0):
		var idx = drops.size() - 1
		var drop = drops[idx]
		drops.remove_at(idx)
		var drone = getClosestTo(waitingDrones, drop.position)
		if not drone:

			if drop.position.length() > 100000:

				drop.shrink(teamId)
			else:

				var droneUIDs: = []
				for d in waitingDrones:
					droneUIDs.append(d.UID)
				networkResetDrones(droneUIDs)
			return
		waitingDrones.erase(drone)
		networkTargetDrop(drone.UID, drop.UID, drone.global_position, drop.position, drone.baseSpeed)


func shouldRefreshTargetPath(drone) -> bool:
	if drone.state != PICKUP or not is_instance_valid(drone.targettedDrop):   # changed: was TransportDrone.State.PICKUP
		return false
	var currentTargetSpot: Vector2 = drone.targettedDrop.global_position - drone.get_node("PickupSpot").position
	return currentTargetSpot.distance_squared_to(drone.targetSpot) >= GameWorld.TILE_SIZE * GameWorld.TILE_SIZE


# The same RPC as vanilla's (an override keeps it only when it says so).
@rpc("reliable")
func targetDrop(droneUID: int, dropUID: int, dronePosition: Vector2, dropPosition: Vector2, baseSpeed: float) -> void:
	super(droneUID, dropUID, dronePosition, dropPosition, baseSpeed)
	if not multiplayer.is_server() or not drones.has(droneUID):
		return
	var drone = drones[droneUID]
	if drone.state != 0 or not drone.has_method("no_way_found"):
		return
	# No path to the drop. The drop may be the one cut off: only a drone with
	# no way home either sits out.
	var home: Vector2 = Vector2(Level.domesByTeamId[teamId].global_position.x, (Vector2(0, -1) * GameWorld.TILE_SIZE + CONST.TILE_OFFSET).y)
	var path = tryFindPath(drone.position, home, drone.teamId)
	if path and not path.is_empty():
		return
	drone.no_way_found()
	var wait: int = mini(HAND_OUT_RETRY_MS << mini(drone.story_failed_asks - 1, 8), HAND_OUT_RETRY_MAX_MS)
	drone.story_hand_out_after = Time.get_ticks_msec() + wait


func tryFindPath(startPos, endPos, teamId):
	var map = Level.map
	var pf = map.pathfinder
	var to: Vector2 = Vector2(map.getTileCoord(endPos)) * GameWorld.TILE_SIZE + CONST.TILE_OFFSET
	if not pf.pointIdsByCoord.has(to):
		return null
	var from_c: Vector2i = map.getTileCoord(startPos)
	if from_c.y >= 0:
		if pf.pointIdsByCoord.has(Vector2(from_c) * GameWorld.TILE_SIZE + CONST.TILE_OFFSET):
			return map.findPath(startPos, endPos, teamId)
		if _in_rock(startPos):
			return null
	return super(startPos, endPos, teamId)


func _in_rock(pos: Vector2) -> bool:
	var c: Vector2i = Level.map.getTileCoord(pos)
	return c.y >= 0 and Level.map.tileData.get_resourcev(c) >= 0
