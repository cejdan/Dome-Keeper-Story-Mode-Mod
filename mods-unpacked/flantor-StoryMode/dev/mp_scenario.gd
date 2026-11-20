extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Shared steps for online multiplayer scenarios (#223), run in pairs by
# dev/mp_playtest.ps1: a host scenario (boot `nethost: true`) and a client
# scenario (boot `netjoin: true`).

const DEV_SHARE := "story.dev.share"


# Host: waits in the loadout for `players` lobby members, picks `mode` (Story
# Mode by default), starts the run and waits until it is playable. False if
# any step failed.
func host_start(h, players: int = 2, mode: String = "storymode", dome: String = "", keepers: Array = []) -> bool:
	var stage = Level.stage
	GameWorld.figuredOutMovementInLoadout = true
	var joined: bool = await h.until(func(): return Lobby.members.size() >= players, 120.0)
	h.check("players joined the lobby", joined, Lobby.members.size())
	if not joined:
		return false
	var spawned: bool = await h.until(func():
		if Level.loadout.keepers.size() < players:
			return false
		for lk in Level.loadout.keepers:
			if lk.keeper == null:
				return false
		return true, 30.0)
	h.check("loadout keepers spawned", spawned, Level.loadout.keepers.size())
	stage.gameModeSelected(mode)
	await h.wait(2.0)
	h.check(mode + " selected", Level.loadout.modeId == mode, Level.loadout.modeId)
	if dome != "":
		# Another dome than the last one picked (#269).
		stage.domeSelected(dome, "team1", false)
		await h.wait(1.0)
		h.check(dome + " selected", Level.loadout.domes.front().domeId == dome, Level.loadout.domes.front().domeId)
	# Each player's keeper, in loadout order (#297): keepers[i] for keeper i.
	# Story Mode scenarios that name none get the Engineer for everyone, as
	# every Story run had before #297 opened the other keepers.
	if keepers.is_empty() and mode == "storymode":
		for i in Level.loadout.keepers.size():
			keepers.append("keeper1")
	if not keepers.is_empty():
		var i: int = 0
		for lk in Level.loadout.keepers.duplicate():
			if i < keepers.size() and lk.keeperId != keepers[i]:
				stage.changeKeeper(lk.playerId, keepers[i] + "-skin0")
			i += 1
		var swapped: bool = await h.until(func():
			for j in mini(keepers.size(), Level.loadout.keepers.size()):
				var lk2 = Level.loadout.keepers[j]
				if lk2.keeperId != keepers[j] or lk2.keeper == null or lk2.keeper.techId != keepers[j]:
					return false
			return true, 20.0)
		h.check("keepers picked: %s" % str(keepers), swapped, Level.loadout.keepers.map(func(lk): return [lk.playerId, lk.keeperId]))
		await h.wait(1.0)
	stage.startRun()
	var started: bool = await h.until(func(): return Level.stage is LevelStage and Level.stage.get("keeperInputStarted") == true and Level.map != null and Level.map.isMapReady(), 180.0)
	h.check("run started", started)
	if not started:
		return false
	h.mute_beats()
	h.disable_waves()
	# The hazard fields are added a few frames after the map is ready.
	if mode == "storymode":
		await h.until(func(): return Level.map.has_node("StoryGasField"), 20.0)
	# Vanilla sends tile reveals and breaks only to clients it sees in sync.
	var t0: float = h.now()
	var synced: bool = await h.until(func():
		for c in Network.clients:
			if c.connection_state != Network.ConnectionState.LEVEL_STAGE_SYNC:
				return false
		return true, 90.0)
	h.check("clients in sync", synced, {"states": Network.clients.map(func(c): return c.connection_state), "waited": h.now() - t0})
	return true


# Host: shares values with the client scenario through Data (synced).
func share(key: String, value) -> void:
	var d: Dictionary = {}
	var have = Data.ofOr(DEV_SHARE, "")
	if have is String and have != "":
		d = JSON.parse_string(have)
	d[key] = value
	Data.apply(DEV_SHARE, JSON.stringify(d))


# Client: a value the host shared, waiting for it up to `timeout` seconds.
func shared(h, key: String, timeout: float = 30.0):
	var get_it := func():
		var have = Data.ofOr(DEV_SHARE, "")
		if not have is String or have == "":
			return null
		return JSON.parse_string(have).get(key)
	await h.until(func(): return get_it.call() != null, timeout)
	return get_it.call()


# Host: stays up until every client has left (or `timeout`).
func host_wait_clients_left(h, timeout: float = 180.0) -> void:
	var left: bool = await h.until(func(): return Network.clients.is_empty(), timeout)
	h.note("clients left", left)


# --- a run's Story Mode state, for save and drop-in checks (#232) -------------

const MARKER_BEAT := "t232_marker"
const ROOM := Vector2i(4, 3)


# Host: `n` sealed rooms (ROOM tiles; [top-left, bottom-right]) of plain dirt
# in the upper map, with a dirt wall around each, away from lava, gas and
# each other.
func find_rooms(n: int) -> Array:
	var td = Level.map.tileData
	var lava = Level.map.get_node("StoryLavaField")
	var gas = Level.map.get_node("StoryGasField")
	var rooms: Array = []
	var cells: Array = td.get_resource_cells_by_id(Data.TILE_DIRT_START)
	cells.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and absi(a.x) < absi(b.x)))
	for c0 in cells:
		var c := Vector2i(c0)
		if c.y < 10 or c.y > 40 or absi(c.x) < 6:
			continue
		var ok := true
		for y in range(c.y - 1, c.y + ROOM.y + 1):
			for x in range(c.x - 1, c.x + ROOM.x + 1):
				var t := Vector2i(x, y)
				if td.get_resourcev(t) != Data.TILE_DIRT_START or td.get_hardnessv(t) >= Data.HARDNESS_INDESTRUCTIBLE \
						or lava.magma.has(t) or lava.mass.has(t) or gas.rock.has(t) or gas.mass.has(t):
					ok = false
		for r in rooms:
			if absi(r[0].x - c.x) < 12 and absi(r[0].y - c.y) < 8:
				ok = false
		if ok:
			rooms.append([c, c + ROOM - Vector2i.ONE])
			if rooms.size() == n:
				break
	return rooms


static func room_cells(r: Array) -> Array:
	var out: Array = []
	for y in range(r[0].y, r[1].y + 1):
		for x in range(r[0].x, r[1].x + 1):
			out.append(Vector2i(x, y))
	return out


static func room_arr(r: Array) -> Array:
	return [r[0].x, r[0].y, r[1].x, r[1].y]


static func room_of(a) -> Array:
	return [Vector2i(int(a[0]), int(a[1])), Vector2i(int(a[2]), int(a[3]))]


static func mass_in(masses: Dictionary, r: Array) -> float:
	var t := 0.0
	for c in room_cells(r):
		t += float(masses.get(c, 0.0))
	return t


# Host: sets up a run under way: money, a played beat, the translator stage,
# two heat shield tiers bought (by the host's keeper: per keeper since #265),
# lava in one sealed room and gas in another.
# Returns the rooms as shared ({"lava": [..], "gas": [..]}), or {} if none.
func setup_run_state(h) -> Dictionary:
	var rooms: Array = find_rooms(2)
	h.check("found two sealed rooms", rooms.size() == 2, rooms)
	if rooms.size() < 2:
		return {}
	var lava = Level.map.get_node("StoryLavaField")
	var gas = Level.map.get_node("StoryGasField")
	for r in rooms:
		await h.dig_room(r[0], r[1])
	# Lava on the room's floor, gas filling the other.
	for x in range(rooms[0][0].x, rooms[0][1].x + 1):
		var c := Vector2i(x, rooms[0][1].y)
		lava.mass[c] = 1.0
		lava._wake(c)
	lava.wake_all()
	gas.fill(room_cells(rooms[1]), 0.6)
	Data.apply("team1.inventory.money", 2318)
	Data.apply("team1.story.beatsplayed", str(Data.ofOr("team1.story.beatsplayed", "")) + "," + MARKER_BEAT)
	Data.apply("team1.story.translation", 2)
	await h.buy("storyHeatShield1")
	await h.buy("storyHeatShield2")
	var shared_rooms := {"lava": room_arr(rooms[0]), "gas": room_arr(rooms[1])}
	share("rooms", shared_rooms)
	h.note("run state set up", shared_rooms)
	return shared_rooms


# This instance's view of the run (host or client).
func facts(rooms: Dictionary) -> Dictionary:
	var lava = Level.map.get_node_or_null("StoryLavaField") if Level.map != null else null
	var gas = Level.map.get_node_or_null("StoryGasField") if Level.map != null else null
	var f := {
		"seed": Level.levelSeed,
		"money": int(Data.ofOr("team1.inventory.money", -1)),
		"marker beat": Array(str(Data.ofOr("team1.story.beatsplayed", "")).split(",")).has(MARKER_BEAT),
		"beats played": Array(str(Data.ofOr("team1.story.beatsplayed", "")).split(",", false)).size(),
		"translation": int(Data.ofOr("team1.story.translation", 0)),
		# Per keeper since #265: the host's keeper (player1) bought two tiers in
		# setup_run_state; "heat shields" is both keepers'.
		"heat shield": int(Data.ofOr("player1.suit.heatshield", 0)),
		"heat shields": "%d,%d" % [int(Data.ofOr("player1.suit.heatshield", 0)), int(Data.ofOr("player2.suit.heatshield", 0))],
		"boss": str(Data.ofOr("team1.story.boss", "")),
		"hearts": int(Data.ofOr("team1.story.hearts", -1)),
		"map meta": load("res://mods-unpacked/flantor-StoryMode/net/story_net.gd").map_meta_ready(Level.map),
		"ocean": Level.map.tileData.get_meta("story_ocean", {}).size() if Level.map != null and Level.map.tileData != null else -1,
	}
	if lava != null:
		var total := 0.0
		for c in lava.mass:
			total += lava.mass[c]
		f["lava cells"] = lava.mass.size()
		f["lava total"] = snappedf(total, 0.01)
		if rooms.has("lava"):
			f["lava room"] = snappedf(mass_in(lava.mass, room_of(rooms["lava"])), 0.001)
	if gas != null:
		var total := 0.0
		for c in gas.mass:
			total += gas.mass[c]
		f["gas cells"] = gas.mass.size()
		f["gas total"] = snappedf(total, 0.01)
		f["gas rock"] = gas.rock.size()
		if rooms.has("gas"):
			f["gas room"] = snappedf(mass_in(gas.mass, room_of(rooms["gas"])), 0.001)
	return f


# Client: compares its facts with the host's shared ones; `rel` is the
# tolerance for the moving fields (lava and gas totals, a share of the value).
func check_facts(h, mine: Dictionary, host: Dictionary, what: String, rel: float = 0.05) -> void:
	for k in ["seed", "money", "marker beat", "translation", "heat shield", "heat shields", "boss", "hearts", "ocean", "gas rock"]:
		if host.has(k):
			h.check("%s: %s is the host's" % [what, k], str(mine.get(k)) == str(host[k]) or (mine.get(k) is int and host[k] is float and int(host[k]) == mine[k]), {"mine": mine.get(k), "host": host[k]})
	for k in ["lava room", "gas room", "lava total", "gas total", "lava cells"]:
		if host.has(k):
			var a := float(mine.get(k, -1.0))
			var b := float(host[k])
			h.check("%s: %s is the host's" % [what, k], absf(a - b) <= maxf(0.02, absf(b) * rel), {"mine": a, "host": b})


# Stands this instance's keeper in the lava room's top corner, out of the
# heat (no recall to spoil the money), for a screenshot of both rooms.
func look_at_rooms(h, rooms: Dictionary) -> void:
	var lava = Level.map.get_node("StoryLavaField")
	if not _cooling:
		_cooling = true
		h.get_tree().process_frame.connect(func(): lava.heat = 0.0)
	# A sealed room isn't reached by the flood reveal from the surface that a
	# loaded map starts with (the test's rooms are dug apart from the mine).
	await h.reveal(room_cells(room_of(rooms["lava"])) + room_cells(room_of(rooms["gas"])))
	h.keeper().teleport(Level.map.getTilePos(room_of(rooms["lava"])[0]))
	h.snap_camera()
	await h.wait(0.5)


var _cooling := false


func keeper_rows(h) -> Array:
	var rows: Array = []
	for k in Keepers.getAll():
		rows.append({"player": k.playerId, "peer": k.peerId, "local": k.peerId == h.multiplayer.get_unique_id(), "tile": Level.map.getTileCoord(k.global_position)})
	return rows
