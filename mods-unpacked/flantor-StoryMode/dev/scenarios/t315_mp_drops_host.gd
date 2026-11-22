extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #315, host half: drops the host uses up go on the client too. A water drop
# lies on the floor of a dug room until lava fills that floor and hardens
# round it (lava_field._check_water); a mining charge spawned the way Velle's
# chamber spawns them (velle.spawn_bomb: no bomb cave behind it) is lit and
# goes off. The client sees each drop first, then sees it gone (its checks).
# Pair: t315_mp_drops_client.

const TIMEOUT := 300


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if not await host_start(h):
		return
	h.disable_waves()
	var rooms: Array = find_rooms(2)
	h.check("found two sealed rooms", rooms.size() == 2, rooms)
	if rooms.size() < 2:
		return
	for r in rooms:
		await h.dig_room(r[0], r[1])
	var lava = Level.map.get_node("StoryLavaField")
	var wr: Array = rooms[0]
	var br: Array = rooms[1]

	# ---- water, lying on the floor of room A
	var floor_y: int = wr[1].y
	var at: Vector2 = Level.map.getTilePos(Vector2i(wr[0].x + 1, floor_y)) + Vector2(0, 4)
	var water = Level.drops.network_spawn({"type": CONST.WATER, "position": at, "team": "team1"})
	h.check("a water drop spawned", water != null)
	if water == null:
		return
	share("rooms", {"water": room_arr(wr), "bomb": room_arr(br)})
	share("water", water.UID)
	# The client looks for it meanwhile (it can't share back: Data is the host's).
	await h.wait(8.0)
	var floating0: int = int(Data.ofOr("inventory.floating" + CONST.WATER, 0))
	# Both keepers wait in room B, clear of the lava.
	await h.teleport_tile(br[0])
	h.snap_camera()
	await h.shot("host_water_before")
	# Lava over room A's floor, where the drop lies.
	for x in range(wr[0].x, wr[1].x + 1):
		var c := Vector2i(x, floor_y)
		lava.mass[c] = 1.0
		lava._wake(c)
	lava.wake_all()
	var used: bool = await h.until(_gone.bind(weakref(water)), 10.0)
	h.check("the lava uses the water up on the host", used, {"hardened": lava.hardened, "last": lava.last_hardened})
	h.check("the host's floating water count went down", int(Data.ofOr("inventory.floating" + CONST.WATER, 0)) == floating0 - 1,
		[floating0, Data.ofOr("inventory.floating" + CONST.WATER, 0)])
	await h.wait(0.3)
	await h.shot("host_water_after")
	share("water_used", true)
	await h.wait(6.0)

	# ---- a mining charge, as Velle's chamber drops them
	var bat: Vector2 = Level.map.getTilePos(Vector2i(br[1].x, br[1].y))
	var bomb = Level.drops.network_spawn({"type": CONST.CAVEBOMB, "position": bat, "team": "team1"})
	h.check("a charge spawned", bomb != null)
	if bomb == null:
		return
	bomb.set_meta("story_calm", true)
	share("bomb", bomb.UID)
	await h.wait(6.0)
	await h.shot("host_bomb_before")
	bomb.activate()
	share("bomb_lit", true)
	var blown: bool = await h.until(_gone.bind(weakref(bomb)), 8.0)
	h.check("the charge goes off on the host", blown)
	await h.wait(0.3)
	await h.shot("host_bomb_after")
	share("done", true)
	await host_wait_clients_left(h)


# Freed or on its way out on the host (a weakref: a lambda that captured the
# drop itself errors once it is freed).
static func _gone(ref: WeakRef) -> bool:
	var d = ref.get_ref()
	return d == null or d.is_queued_for_deletion()
