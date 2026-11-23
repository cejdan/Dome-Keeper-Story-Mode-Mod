extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #345: the Beastmaster's (keeper4) catgoblins mine Story Mode's minerals the
# way they mine iron. A dug-out hole in a room whose floor holds bronze, gold,
# sapphire, emerald, a diamond and an iron tile (the control); the cats have
# the Dig upgrade. Each mineral tile must give up its pieces of its own type
# and turn to dirt; the diamond gives exactly one (#186). An unobtainium tile
# mined this way weakens the seal like a broken one (#95, beats/awakening.gd).

const TIMEOUT := 200
const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
const Keeper2Run = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t297_keeper2.gd")
const Awakening = preload("res://mods-unpacked/flantor-StoryMode/beats/awakening.gd")

const ROOM := [Vector2i(-4, 7), Vector2i(4, 9)]
const HOLE := Vector2i(0, 9)
const FLOOR_Y := 10
const PLANT := {
	-3: "bronze", -2: "iron", -1: "gold", 1: "sapphire", 2: "emerald", 3: "diamond", 4: "unobtainium",
}

var spawned: Dictionary = {}  # drop UID -> type, every drop seen near the room


func boot() -> Dictionary:
	return {"seed": 12345, "keeper": "keeper4"}


func _floor(x: int) -> Vector2i:
	return Vector2i(x, FLOOR_Y)


func _track_drops() -> void:
	for d in Level.drops.get_children():
		if not is_instance_valid(d) or not ("type" in d) or not ("UID" in d):
			continue
		if spawned.has(d.UID):
			continue
		var c: Vector2i = Level.map.getTileCoord(d.global_position)
		if c.y >= ROOM[0].y - 1 and c.y <= FLOOR_Y + 1 and c.x >= ROOM[0].x - 1 and c.x <= ROOM[1].x + 1:
			spawned[d.UID] = str(d.type)


func _count(type: String) -> int:
	return spawned.values().filter(func(t): return t == type).size()


func run(h) -> void:
	h.disable_waves()
	var k = h.keeper()
	h.check("the run's keeper is the Beastmaster", k != null and k.techId == "keeper4", k.techId if k else null)
	await h.wait(1.0)
	await Keeper2Run.close_tutorials(h)
	var td = Level.map.tileData
	var pid: String = k.playerId

	# The floor: the planted minerals, plain dirt between and below.
	for x in range(ROOM[0].x - 1, ROOM[1].x + 2):
		td.set_resourcev(_floor(x), Data.TILE_DIRT_START)
		td.set_resourcev(Vector2i(x, FLOOR_Y + 1), Data.TILE_DIRT_START)
	for x: int in PLANT:
		td.set_resourcev(_floor(x), int(Minerals.TABLE[PLANT[x]]["tile_id"]))
	await h.dig_room(ROOM[0], ROOM[1])
	var below: Array = []
	for x in range(ROOM[0].x - 1, ROOM[1].x + 2):
		below.append(_floor(x))
		below.append(Vector2i(x, FLOOR_Y + 1))
	await h.reveal(below)
	for x: int in PLANT:
		var t = Level.map.getTile(Vector2(_floor(x)))
		h.check("%s planted at %s" % [PLANT[x], _floor(x)], t != null and t.type == PLANT[x], t.type if t else "none")
	var diamond = Level.map.getTile(Vector2(_floor(3)))
	h.note("diamond richness", diamond.richness if diamond else null)

	# Cats with the Dig upgrade, and a dug-out hole in the room.
	Data.apply(pid + ".keeper4.catgoblincount", 6)
	Data.apply(pid + ".keeper4.catgoblinminingspeed", 4.0)
	var unob0: int = Awakening.mined()
	var goblins = Level.getDome(k.teamId).goblins
	var hole = goblins.spawn_hole(pid, Level.map.getTilePos(HOLE))
	for i in Keeper4GameplaySettings.HOLE_TOTAL_PUNCHES:
		hole.receive_punch()
	var dug: bool = await h.until(func(): return is_instance_valid(hole) and hole.hole_state == GoblinHole.HoleState.DUG_OUT, 10.0)
	h.check("the hole is dug out", dug)
	var tm = goblins.get_task_manager(pid)
	h.note("task manager script", tm.get_script().resource_path)
	await h.teleport_tile(Vector2i(-1, 9), k)
	await h.wait(2.0)
	await h.shot("room")

	# Let them work until every planted tile is dirt, or a minute goes by.
	var t_end: float = h.now() + 60.0
	var left: Array = PLANT.keys()
	while h.now() < t_end and not left.is_empty():
		_track_drops()
		left = PLANT.keys().filter(func(x):
			var t = Level.map.getTile(Vector2(_floor(x)))
			return t != null and t.type == PLANT[x])
		await h.wait(0.25)
	await h.shot("after")
	_track_drops()

	var state: Dictionary = {}
	for x: int in PLANT:
		var t = Level.map.getTile(Vector2(_floor(x)))
		state[PLANT[x]] = {"now": t.type if t else "none", "pieces": _count(PLANT[x])}
	h.note("floor after", state)
	for x: int in PLANT:
		var m: String = PLANT[x]
		h.check("the cats mined the %s tile to dirt" % m, state[m]["now"] != m, state[m])
		h.check("it gave %s pieces" % m, state[m]["pieces"] >= 1, state[m])
	h.check("the diamond gave exactly one diamond (#186)", _count("diamond") == 1, _count("diamond"))
	h.check("the cat-mined unobtainium counts against the seal", Awakening.mined() == unob0 + 1 and Awakening.freed(_floor(4)), [unob0, Awakening.mined()])
	h.snap("end", [])

