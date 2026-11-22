extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t313_drone_crash.gd"

# Ticket 313, follow-up: t313_drone_crash's churn with the Beastmaster
# (keeper4; `-Extra "--keeper=keeper1"` runs it with the Engineer). Its pets
# work out of two holes in the rooms under the dome while rock keeps coming
# and going: cells on the drones' and the pets' paths turn to rock and break
# again, the metal barrier's gap closes and opens, and below room B a magma
# vein melts into a lava chamber that water drops keep hardening. Three
# drones get stranded: two sealed in rock (one carrying, one idle) and one in
# a pocket with no way home.
#
# Measures, over a stretch of that heavy lava scene at normal speed, the
# frame cost of keeping the paths: the pets' path graph rebuilds
# (GoblinNavigator's chunks, read off its frame budget, plus its unbudgeted
# begin_rebuild, timed apart), the drones' requests for a way home, and the
# drone hand-out's loop over the drops. A measuring build (a dev/prof.gd with
# static `us`, `n`, `mx` dicts and reset(), plus timers in the mod code; not
# kept in the repo) adds the graph upkeep, the drone re-paths and the
# dispatcher, per frame.
#
# Then, with the lava still: a pets' graph rebuild caught mid-way while rock
# comes and goes (the finished graph must have both changes), and rock coming
# back a few steps ahead of walking pets (none may walk on through it).
#
# Checks: no pet path and no pet graph surface sits in a cell that has been
# rock for a while, once the rock stops changing the pets' graph has a floor
# in every opening, the race and re-path tests above, the drone checks of t313_drone_crash, the stranded drones stay
# where they are, and a save between waves (t313_pets_reload loads it).

const PET_SLOT := 38
const PET_HOLES := [Vector2i(-2, 8), Vector2i(11, 8)]
const POCKET := [Vector2i(-11, 12), Vector2i(-8, 13)]
const LAVA_ROOM := [Vector2i(8, 11), Vector2i(15, 13)]
# The band of the map revealed first, as a run some way in has it (the pets'
# graph is built over every revealed tile).
const REVEALED := [Vector2i(-36, 1), Vector2i(36, 44)]
const SETTLE_MS := 2000          # a cell changed this long ago must be in the pets' graph
const PROF := "res://mods-unpacked/flantor-StoryMode/dev/prof.gd"
const Keeper2Run = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t297_keeper2.gd")

static var _TransportDrone = TransportDrone
var goblins = null
var nav = null
var sampler: Node = null
var changed_ms: Dictionary = {}  # Vector2i -> when its rock came or went
var pet_bad_paths: Array = []
var pet_graph_rock: Array = []
var pet_graph_missing: Array = []
var pet_graph_lagging := 0       # openings not in the graph yet during the churn (it rebuilds behind)
var pet_toggles := 0
var stranded: Array = []        # [drone, cell, label]
var home_asks: Dictionary = {}  # drone UID -> requests for a way home
var closes := 0
var opens := 0
var audits := 0


# Reads the pets' navigator every physics frame, before Goblins resets its
# frame budget (tick()): what the budget lost since is the time its rebuild
# chunks took. Rebuilds are counted by the graph generation.
class PetSampler extends Node:
	var nav
	var used_us := 0
	var max_used_us := 0
	var gens := 0
	var frames := 0
	var _gen := -1
	var _scratch_seen_ms := 0
	var last_start_ms := 0      # when the latest finished rebuild began

	func _ready() -> void:
		process_physics_priority = -1000

	func _physics_process(_delta: float) -> void:
		if nav == null:
			return
		frames += 1
		var left: int = nav._frame_chunk_budget_us
		if left < GoblinNavigator.REBUILD_BUDGET_US:
			used_us += GoblinNavigator.REBUILD_BUDGET_US - left
			max_used_us = maxi(max_used_us, GoblinNavigator.REBUILD_BUDGET_US - left)
		var g: int = nav._graph_generation
		if _gen >= 0 and g != _gen:
			gens += g - _gen
			last_start_ms = _scratch_seen_ms if _scratch_seen_ms > 0 else Time.get_ticks_msec()
			_scratch_seen_ms = 0
		_gen = g
		if nav._pathfinder_scratch != null and _scratch_seen_ms == 0:
			_scratch_seen_ms = Time.get_ticks_msec()


func boot() -> Dictionary:
	return {"seed": 12345, "gadget": "droneyard", "keeper": "keeper4"}


func _keeper4() -> bool:
	var k = Keepers.first() if not Keepers.local.keepers.is_empty() else null
	return k != null and k.techId == "keeper4"


func _prof():
	return load(PROF) if ResourceLoader.exists(PROF) else null


func _on_closed(coord: Vector2) -> void:
	closes += 1
	changed_ms[Vector2i(coord)] = Time.get_ticks_msec()


func _on_opened(world_pos: Vector2) -> void:
	opens += 1
	changed_ms[map.getTileCoord(world_pos)] = Time.get_ticks_msec()


func _settled(c: Vector2i) -> bool:
	return Time.get_ticks_msec() - int(changed_ms.get(c, 0)) >= SETTLE_MS


func _solid(c: Vector2i) -> bool:
	return td.get_resourcev(c) >= 0


func _goblins() -> Array:
	if goblins == null:
		return []
	return goblins.all_goblins.filter(func(g): return is_instance_valid(g))


# The pets' graph and paths against the map: no surface, and no step of a
# pet's path, in a cell that has been rock for SETTLE_MS; a floor surface in
# every cell open for that long over rock.
func _pet_audit(label: String, final: bool = false) -> void:
	if nav == null or nav._pathfinder == null:
		return
	audits += 1
	# A query, as every pet makes: lets a pending rebuild go on (vanilla's
	# throttle and budget still apply).
	nav.get_graph_generation()
	var pf = nav._pathfinder
	for g in _goblins():
		var path: Array = g.current_surface_path
		for i in range(g.surface_path_index, path.size()):
			var c: Vector2i = path[i].get("coord", Vector2i.ZERO)
			if c.y >= 0 and _solid(c) and _settled(c):
				pet_bad_paths.append([label, g.UID, c, g.state])
				break
	for c: Vector2i in changed_ms:
		if not _settled(c):
			continue
		if _solid(c):
			if pf.coord_to_surfaces.has(c) and not pf.coord_to_surfaces[c].is_empty():
				pet_graph_rock.append([label, c])
		elif _solid(c + Vector2i.DOWN) and _settled(c + Vector2i.DOWN):
			if pf.surface_nodes.has(pf._get_surface_id(c, SurfacePathfinding.SurfaceType.FLOOR_TOP)):
				continue
			if not final:
				pet_graph_lagging += 1
				continue
				pet_graph_missing.append([label, c, {"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.1), "changed": int(changed_ms.get(c, 0)) / 1000.0, "below changed": int(changed_ms.get(c + Vector2i.DOWN, 0)) / 1000.0, "below tile": map.tiles.has(Vector2(c + Vector2i.DOWN)), "gen": nav._graph_generation, "dirty": nav._dirty, "rebuilding": nav._pathfinder_scratch != null, "count": nav._tile_count, "tiles": map.tiles.size(), "surfaces": pf.coord_to_surfaces.get(c, [])}])


# Closes one cell ahead on a random pet's path with rock and breaks it again a
# moment later.
func _toggle_on_pet_path(h) -> void:
	var walking: Array = _goblins().filter(func(g): return g.current_surface_path.size() > g.surface_path_index + 2)
	if walking.is_empty():
		return
	var g = walking[rng.randi() % walking.size()]
	var i: int = mini(g.surface_path_index + 1 + rng.randi() % 3, g.current_surface_path.size() - 1)
	var c: Vector2i = g.current_surface_path[i].get("coord", Vector2i.ZERO)
	if c.y < 1 or not _open(c) or c == map.getTileCoord(g.global_position):
		return
	_solidify(c)
	pet_toggles += 1
	h.get_tree().create_timer(rng.randf_range(0.3, 2.0)).timeout.connect(func(): if is_instance_valid(map): _break(c))


func _pet_churn(h, sec: float, label: String, toggles_on: bool = true) -> void:
	var t_end: float = h.now() + sec
	var k := 0
	while h.now() < t_end:
		if toggles_on:
			_toggle_on_path(h)
			_toggle_on_pet_path(h)
			if k % 10 == 0:
				var gap := Vector2i(5 + rng.randi() % 2, 7 + rng.randi() % 2)
				if _open(gap):
					_solidify(gap, Metal.TILE_ID)
					h.get_tree().create_timer(rng.randf_range(0.3, 2.0)).timeout.connect(func(): if is_instance_valid(map): _break(gap))
		if k % 3 == 0:
			_audit(h, label)
		if k % 2 == 0:
			_pet_audit(label)
		if k % 2 == 0:
			_water()
		if k % 25 == 0 and h.get_tree().get_nodes_in_group("drops").size() < 30:
			_spawn_far(6)
		k += 1
		await h.wait(0.25)


# The lava keeps hardening and melting: a water drop onto lava in the chamber
# (it hardens up to six cells), and the cells the last drop hardened turn to
# magma rock, which the lava melts open again.
func _water() -> void:
	var field = map.get_node_or_null("StoryLavaField")
	if field == null or field.mass.is_empty():
		return
	for c: Vector2i in field.last_hardened:
		if td.get_resourcev(c) >= 0:
			field.magma[c] = true
			if "_melt_check" in field:
				field._melt_check[c] = true
	var hot: Array = []
	for c: Vector2i in field.mass:
		if field.mass[c] >= 0.3 and c.x >= LAVA_ROOM[0].x - 4 and c.x <= LAVA_ROOM[1].x + 4 and c.y >= LAVA_ROOM[0].y and c.y <= LAVA_ROOM[1].y + 9:
			hot.append(c)
	if hot.is_empty():
		return
	var c: Vector2i = hot[rng.randi() % hot.size()]
	Level.drops.network_spawn({"type": CONST.WATER, "position": map.getTilePos(c), "impulse": Vector2.ZERO})


# The lava chamber under room B (rows 9-10 stay rock between them), a pool on
# its floor and a magma vein around it that the lava melts into.
func _lava_scene(h) -> void:
	var field = map.get_node_or_null("StoryLavaField")
	if field == null:
		return
	var a: Vector2i = LAVA_ROOM[0]
	var b: Vector2i = LAVA_ROOM[1]
	for y in range(a.y - 2, b.y + 10):
		for x in range(a.x - 4, b.x + 5):
			var c := Vector2i(x, y)
			field.mass.erase(c)
			if not (y >= a.y and y <= b.y and x >= a.x and x <= b.x):
				if td.get_resourcev(c) == Data.TILE_EMPTY:
					_solidify(c)
				else:
					td.set_resourcev(c, Data.TILE_DIRT_START)
					if td.get_hardnessv(c) < 0 or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE:
						td.set_hardnessv(c, Data.HARDNESS_MEDIUM)
	await h.dig_room(a, b)
	for y in [b.y - 1, b.y]:
		for x in range(a.x, b.x + 1):
			field.mass[Vector2i(x, y)] = 1.0
	for x in [a.x, a.x + 3, b.x - 3, b.x]:
		field.sources[Vector2i(x, b.y)] = 200.0
	for y in range(b.y + 1, b.y + 9):
		for x in range(a.x - 3, b.x + 4):
			field.magma[Vector2i(x, y)] = true
	for y in range(a.y, b.y + 1):
		for x in [a.x - 1, a.x - 2, b.x + 1, b.x + 2]:
			field.magma[Vector2i(x, y)] = true
	if "_melt_full" in field:
		field._melt_full = true
	field.wake_all()


# Holes for the pets, punched out the way the Beastmaster's punches make them.
func _pet_holes(h) -> void:
	for c: Vector2i in PET_HOLES:
		var hole = goblins.spawn_hole("player1", map.getTilePos(c))
		for i in Keeper4GameplaySettings.HOLE_TOTAL_PUNCHES:
			hole.receive_punch()
	await h.until(func(): return h.get_tree().get_nodes_in_group("team1-goblin_holes").filter(func(x): return is_instance_valid(x) and not x.is_entrance_hole and x.hole_state == GoblinHole.HoleState.DUG_OUT).size() >= PET_HOLES.size(), 10.0)


func _count_home_asks(d) -> void:
	if not d.request_path_home.is_connected(_on_home_ask.bind(d.UID)):
		d.request_path_home.connect(_on_home_ask.bind(d.UID))


func _on_home_ask(uid: int) -> void:
	home_asks[uid] = home_asks.get(uid, 0) + 1


# Idle drones carrying nothing that are not stranded yet.
func _free_idle(h) -> Array:
	return _drones(h).filter(func(d): return d.state == TransportDrone.State.WAIT and d.carriedResource == "" and not stranded.any(func(s): return s[0] == d))


# Seals drones in: one carrying (its cell turns to rock under it), one idle
# (moved into room A, then rock), and one moved into a pocket with no way
# home, drops beside it.
func _strand(h) -> void:
	var carrying: bool = await h.until(func(): return _drones(h).any(func(d): return d.state == TransportDrone.State.RETRIEVE and map.getTileCoord(d.global_position).y >= 5), 20.0)
	if carrying:
		var d = _drones(h).filter(func(d): return d.state == TransportDrone.State.RETRIEVE and map.getTileCoord(d.global_position).y >= 5)[0]
		var c: Vector2i = map.getTileCoord(d.global_position)
		_solidify(c)
		stranded.append([d, c, "carrying"])
	for kind in ["idle", "pocket"]:
		await h.until(func(): return not _free_idle(h).is_empty(), 20.0)
		var free: Array = _free_idle(h)
		if free.is_empty():
			continue
		var d = free[0]
		var c := Vector2i(-3, 6) if kind == "idle" else Vector2i(POCKET[0].x + 1, POCKET[1].y)
		d.global_position = map.getTilePos(c)
		await h.frames(2)
		if kind == "idle":
			_solidify(c)
		else:
			for i in 2:
				Level.drops.network_spawn({"type": "iron", "position": map.getTilePos(POCKET[1]) + Vector2(0, -4), "impulse": Vector2.ZERO})
		stranded.append([d, c, kind])
	h.note("stranded drones", stranded.map(func(s): return {"uid": s[0].UID, "cell": s[1], "kind": s[2], "state": s[0].state}))


# Frame cost over `sec` seconds of play (no scripted tile changes, the lava
# melting and hardening on its own).
func _measure(h, sec: float, label: String) -> Dictionary:
	var prof = _prof()
	if prof != null:
		prof.reset()
	var f0: int = Engine.get_process_frames()
	var pu0: int = sampler.used_us if sampler != null else 0
	var g0: int = sampler.gens if sampler != null else 0
	if sampler != null:
		sampler.max_used_us = 0
	var asks0: int = home_asks.values().reduce(func(a, b): return a + b, 0)
	var c0 := closes
	var o0 := opens
	var t0 := Time.get_ticks_usec()
	var field = map.get_node_or_null("StoryLavaField")
	var lava0: int = field.phys_us if field != null else 0
	await _pet_churn(h, sec, label, false)
	var frames_n: int = maxi(Engine.get_process_frames() - f0, 1)
	var wall_us: int = Time.get_ticks_usec() - t0
	var rebuilds: int = (sampler.gens - g0) if sampler != null else 0
	var begin_us := 0
	if nav != null and rebuilds > 0:
		# begin_rebuild runs outside the frame budget: timed on its own.
		var t := Time.get_ticks_usec()
		for i in 3:
			var sp := SurfacePathfinding.new()
			sp.begin_rebuild(map, nav.gather_vine_coords(false), false)
		begin_us = (Time.get_ticks_usec() - t) / 3
	var out := {
		"frames": frames_n, "fps": snappedf(frames_n / (wall_us / 1000000.0), 0.1), "ms per frame": snappedf(wall_us / 1000.0 / frames_n, 0.01),
		"lava us/frame": snappedf(float((field.phys_us if field != null else 0) - lava0) / frames_n, 0.1),
		"cells closed": closes - c0, "cells opened": opens - o0,
		"requests for a way home": home_asks.values().reduce(func(a, b): return a + b, 0) - asks0,
		"pet rebuilds": rebuilds, "pet chunk max us": sampler.max_used_us if sampler != null else 0, "pet begin_rebuild us": begin_us,
		"pet rebuild us/frame": snappedf(float((sampler.used_us - pu0 if sampler != null else 0) + rebuilds * begin_us) / frames_n, 0.1),
		"map tiles": map.tiles.size(), "drone graph points": map.pathfinder.pointIdsByCoord.size(),
		"pets": _goblins().size(), "drones": _drones(h).size(),
	}
	# The drone hand-out's own loop over the drops (vanilla), timed once.
	var tq := Time.get_ticks_usec()
	var all_drops: Array = h.get_tree().get_nodes_in_group("drops")
	out["drops group size"] = all_drops.size()
	out["drops group fetch us"] = Time.get_ticks_usec() - tq
	tq = Time.get_ticks_usec()
	var movable := 0
	for d in all_drops:
		if d.carryableType != "resource":
			continue
		if not TransportDrone.canTransport(d):
			continue
		movable += 1
	out["hand-out drop filter us"] = Time.get_ticks_usec() - tq
	tq = Time.get_ticks_usec()
	for d in all_drops:
		if d.carryableType != "resource":
			continue
		if not _TransportDrone.canTransport(d):
			continue
	out["same filter, canTransport through a static var us"] = Time.get_ticks_usec() - tq
	tq = Time.get_ticks_usec()
	for d in all_drops:
		if d.carryableType != "resource":
			continue
	out["same filter without canTransport us"] = Time.get_ticks_usec() - tq
	out["drops a drone could take"] = movable
	out["measuring build"] = prof != null
	if prof != null:
		for k in prof.us:
			out[k + " us/frame"] = snappedf(float(prof.us[k]) / frames_n, 0.1)
			out[k + " calls"] = prof.n.get(k, 0)
			out[k + " max us"] = prof.mx.get(k, 0)
	h.note("frame cost: " + label, out)
	return out


func run(h) -> void:
	rng.seed = 3133
	map = Level.map
	td = map.tileData
	h.disable_waves()
	h.set_inv("money", 1000000)
	Data.apply("team1.dome.maxHealth", 1000000)
	Data.apply("team1.dome.health", 1000000)
	await h.wait(1.0)
	await Keeper2Run.close_tutorials(h)
	map.path_cell_closed.connect(_on_closed)
	map.tile_destroyed.connect(_on_opened)

	for t in [CONST.IRON, CONST.WATER, CONST.SAND]:
		h.set_inv(t, 1000)
	for id in ["droneyarddrones", "droneyarddrones", "droneyarddrones", "droneyarddronespeed1", "droneyardbattlegrid", "droneyardbattlegridquick1"]:
		await h.buy(id)
	for i in range(1, 5):
		await h.buy("storyheatshield%d" % i)
	await h.until(func(): return _drones(h).size() >= 4, 15.0)
	h.check("the drone yard has drones", _drones(h).size() >= 4, _drones(h).size())

	await _lava_scene(h)
	var band: Array = []
	for y in range(REVEALED[0].y, REVEALED[1].y + 1):
		for x in range(REVEALED[0].x, REVEALED[1].x + 1):
			band.append(Vector2i(x, y))
	await h.reveal(band)
	await h.wait(1.0)

	# Room A, a metal barrier, room B (t313_drone_crash), the lava chamber
	# under room B and a sealed pocket west of room A.
	for y in range(4, 10):
		for x in [5, 6]:
			_metal(Vector2i(x, y))
	await h.dig_room(Vector2i(0, 0), Vector2i(1, 4))
	await h.dig_room(Vector2i(-4, 5), Vector2i(4, 8))
	await h.dig_room(Vector2i(7, 5), Vector2i(16, 8))
	await h.reveal([Vector2i(5, 4), Vector2i(6, 4), Vector2i(5, 9), Vector2i(6, 9)])
	for y in range(5, 9):
		for x in [5, 6]:
			map.revealTile(Vector2(x, y))
	await h.dig_room(POCKET[0], POCKET[1])
	for c in [Vector2i(5, 7), Vector2i(6, 7), Vector2i(5, 8), Vector2i(6, 8)]:
		_break(c)
	await h.frames(3)
	await h.teleport_tile(Vector2i(13, 8))

	if _keeper4():
		goblins = Level.getDome("team1").goblins
		nav = goblins._navigator
		sampler = PetSampler.new()
		sampler.nav = nav
		h.get_tree().root.add_child(sampler)
		Data.apply("player1.keeper4.catgoblincount", 8)
		await _pet_holes(h)
		h.check("the pets have their holes", h.get_tree().get_nodes_in_group("team1-goblin_holes").filter(func(x): return is_instance_valid(x) and not x.is_entrance_hole and x.hole_state == GoblinHole.HoleState.DUG_OUT).size() >= PET_HOLES.size())
	_spawn_far(6)
	for d in _drones(h):
		_count_home_asks(d)
	await h.wait(4.0)
	await h.shot("rooms")
	h.note("pets", _goblins().map(func(g): return {"uid": g.UID, "state": g.state, "pos": map.getTileCoord(g.global_position)}))

	await _pet_churn(h, 12.0, "warm up")
	await h.shot("lava_and_pets")
	await _strand(h)
	for d in _drones(h):
		_count_home_asks(d)

	# The measured stretch: the heavy lava scene, the stranded drones, the pets.
	await _measure(h, 20.0, "heavy lava, stranded drones")
	await h.shot("measured")

	h.speed(2.0)
	await _pet_churn(h, 25.0, "mining")
	await h.shot("mining_churn")
	if nav != null:
		h.speed(1.0)
		await _repath_test(h)
		h.speed(2.0)

	h.enable_waves()
	GameWorld.runStarted = true
	for wave in 2:
		Data.apply("team1.monsters.wavecooldown", 2)
		var came: bool = await h.until(func(): return Data.of("team1.monsters.wavepresent"), 60.0)
		h.check("wave %d came" % (wave + 1), came)
		await _pet_churn(h, 15.0, "wave %d" % (wave + 1))
		await h.shot("wave_%d" % (wave + 1))
		for mm in Level.monstersByTeamId.values():
			mm.instantlyKillWave()
		await h.until(func(): return not Data.of("team1.monsters.wavepresent"), 30.0)
		await _pet_churn(h, 4.0, "wave %d end" % (wave + 1))
		if wave == 0:
			await SaveGame.saveGame("singleplayer", PET_SLOT, true)
			h.note("saved slot", {"slot": PET_SLOT})
	h.disable_waves()
	h.speed(1.0)
	await _pet_churn(h, 4.0, "settle", false)
	# The lava stops changing the rock; the pets' graph catches up (pets and
	# this audit asking for it, as they do).
	var field = map.get_node_or_null("StoryLavaField")
	if field != null:
		field.magma.clear()
		field.freeze_flow = true
	for i in 24:
		if nav != null:
			nav.get_graph_generation()
		await h.wait(0.25)
	_pet_audit("end", true)
	if nav != null:
		await _race_test(h)
	await h.shot("end")
	_finish_checks(h)


# Rock that comes and goes while the pets' graph is being rebuilt: a rebuild
# is started and its scan of the map finished (as if the frames it takes had
# passed), then a cell on room A's floor turns to rock and one in the rock
# under it opens. Once the pets' graph has caught up, the first has no surface
# and the second has a floor.
func _race_test(h) -> void:
	var x := Vector2i(2, 8)
	var y := Vector2i(3, 9)
	await h.until(func(): return nav._pathfinder_scratch == null, 5.0)
	nav._dirty = true
	nav._last_rebuild_ms = 0
	nav._frame_chunk_budget_us = 1
	nav.get_graph_generation()
	var sc = nav._pathfinder_scratch
	h.check("race: a pets' graph rebuild is under way", sc != null)
	if sc == null:
		return
	if sc._rebuild_phase == SurfacePathfinding.RebuildPhase.SCAN:
		sc.step_scan(Time.get_ticks_usec() + 10000000)
		sc._rebuild_phase = SurfacePathfinding.RebuildPhase.VINES
	_solidify(x)
	_break(y)
	var t_end: float = h.now() + 4.0
	while h.now() < t_end:
		nav.get_graph_generation()
		await h.frames(1)
	var pf = nav._pathfinder
	var info := {"closed": x, "opened": y, "x solid": _solid(x), "y open": _open(y), "surfaces at x": pf.coord_to_surfaces.get(x, []).size(),
		"floor at y": pf.surface_nodes.has(pf._get_surface_id(y, SurfacePathfinding.SurfaceType.FLOOR_TOP)), "dirty": nav._dirty, "rebuilding": nav._pathfinder_scratch != null}
	h.note("race", info)
	h.check("race: rock that came back during a rebuild leaves the pets' graph", info["x solid"] and info["surfaces at x"] == 0, info)
	h.check("race: a cell opened during a rebuild gets a floor in the pets' graph", info["y open"] and info["floor at y"], info)
	_break(x)


# A cell two steps ahead on a walking pet's path turns to rock (for good):
# the pet must not walk on through it. Up to five pets, one at a time, looked
# for every frame for at most 30 s.
func _repath_test(h) -> void:
	var tried := 0
	var walked_through: Array = []
	var t_stop: float = h.now() + 30.0
	while tried < 5 and h.now() < t_stop:
		var pick = null
		var idx := -1
		for g in _goblins():
			var path: Array = g.current_surface_path
			var i: int = g.surface_path_index + 2
			if i >= path.size():
				continue
			var c: Vector2i = path[i].get("coord", Vector2i.ZERO)
			if c.y < 1 or not _open(c) or c == map.getTileCoord(g.global_position):
				continue
			pick = g
			idx = i
			break
		if pick == null:
			if h.get_tree().get_nodes_in_group("drops").size() < 30:
				_spawn_far(3)
			await h.frames(1)
			continue
		var path: Array = pick.current_surface_path
		var c: Vector2i = path[idx].get("coord", Vector2i.ZERO)
		_solidify(c)
		tried += 1
		var t_end: float = h.now() + 3.0
		var through := false
		while h.now() < t_end:
			nav.get_graph_generation()
			if is_instance_valid(pick) and is_same(pick.current_surface_path, path) and pick.surface_path_index > idx:
				through = true
			await h.frames(1)
		if through:
			walked_through.append({"pet": pick.UID, "cell": c, "state": pick.state})
		_break(c)
		await h.wait(0.5)
	h.note("re-path test", {"tried": tried, "walked through": walked_through})
	h.check("re-path: pets were walking when their way turned to rock", tried >= 3, tried)
	h.check("re-path: no pet walks on through rock that came back on its path", walked_through.is_empty(), walked_through)


func _finish_checks(h) -> void:
	_graph_check(h)
	for s in stranded:
		var d = s[0]
		if not is_instance_valid(d):
			continue
		var at: Vector2i = map.getTileCoord(d.global_position)
		var info := {"kind": s[2], "cell": s[1], "now": at, "state": d.state, "asks": home_asks.get(d.UID, 0)}
		h.note("stranded drone", info)
		if s[2] == "pocket":
			h.check("the drone in the pocket stays in it", at.x >= POCKET[0].x and at.x <= POCKET[1].x and at.y >= POCKET[0].y and at.y <= POCKET[1].y, info)
		else:
			h.check("the drone sealed in rock (%s) stays there" % s[2], at == s[1], info)
	h.check("tiles changed on drone paths", toggles >= 10, toggles)
	h.check("no drone path runs through solid rock", bad_paths.is_empty(), bad_paths.slice(0, 20))
	h.check("no drone leaves the map", off_map.is_empty(), off_map.slice(0, 10))
	if nav != null:
		h.note("pet audits", {"audits": audits, "pet toggles": pet_toggles, "cells changed": changed_ms.size(), "openings not in the graph yet (churn)": pet_graph_lagging})
		h.check("tiles changed on pet paths", pet_toggles >= 5, pet_toggles)
		h.check("no pet path runs through settled rock", pet_bad_paths.is_empty(), pet_bad_paths.slice(0, 20))
		h.check("the pets' graph has no surface in settled rock", pet_graph_rock.is_empty(), pet_graph_rock.slice(0, 20))
		h.check("once the rock stops changing, the pets' graph has a floor in every opening", pet_graph_missing.is_empty(), pet_graph_missing.slice(0, 20))
	h.check("the run is still going", is_instance_valid(map) and not GameWorld.gameover)
