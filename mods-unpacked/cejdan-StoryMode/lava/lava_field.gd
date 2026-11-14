extends Node2D

# Living lava. Hidden magma pockets sit in plain rock; breaking into one lets the
# lava out, and it flows through whatever tunnels the keeper has dug: down first,
# then sideways, and up when the pocket is still pushing. Standing in lava heats
# the suit; a suit at 100% heat triggers an emergency recall to the dome.
#
# One LavaField is a child of the run's Map node (added by lava_director.gd).
# Nothing here edits vanilla state except: destroying magma rock tiles that lava
# melts, and teleporting the keeper on a recall.
#
# Its tuning numbers are first-pass values, game-design calls for the user, and
# live in data/lava.gd.

const LavaData = preload("res://mods-unpacked/cejdan-StoryMode/data/lava.gd")
const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const SAVE_KEY := "story.lava"

const POCKET_MIN_DEPTH := LavaData.POCKET_MIN_DEPTH
const POCKET_CELLS_PER_POCKET := LavaData.POCKET_CELLS_PER_POCKET
const POCKET_SIZE_MIN := LavaData.POCKET_SIZE_MIN
const POCKET_SIZE_MAX := LavaData.POCKET_SIZE_MAX
const VOLUME_PER_MAGMA_CELL := LavaData.VOLUME_PER_MAGMA_CELL
const MELT_SECONDS := LavaData.MELT_SECONDS
const TICK := LavaData.TICK
const MAX_MASS := LavaData.MAX_MASS
const MAX_COMPRESS := LavaData.MAX_COMPRESS
const MIN_MASS := LavaData.MIN_MASS
const MIN_FLOW := LavaData.MIN_FLOW
const MAX_FLOW := LavaData.MAX_FLOW
const SIDE_FLOW_DIVISOR := LavaData.SIDE_FLOW_DIVISOR
const STICKY_MASS := LavaData.STICKY_MASS
const SOURCE_RATE := LavaData.SOURCE_RATE
const COOL_PER_SECOND := LavaData.COOL_PER_SECOND
const FILM_MASS := LavaData.FILM_MASS
const FILM_COOL_PER_SECOND := LavaData.FILM_COOL_PER_SECOND
const MIN_Y := LavaData.MIN_Y
const BURN_MASS := LavaData.BURN_MASS
const HEAT_PER_SECOND := LavaData.HEAT_PER_SECOND
const COOL_MINE_PER_SECOND := LavaData.COOL_MINE_PER_SECOND
const COOL_DOME_PER_SECOND := LavaData.COOL_DOME_PER_SECOND
const HEAT_MAX := LavaData.HEAT_MAX

const TILE := 24.0
const KEEPER_BOX := Vector2(10, 16)
const BURN_TOLERANCE := 1.5
const COL_CORE := Color("ffd23e")
const COL_HOT := Color("ff8a1c")
const COL_BODY := Color("e8430e")
const COL_DEEP := Color("9c1d0a")
const COL_CRUST := Color("3a0d0a")
# A stream is drawn in slices this tall (px).
const STREAM_SLICE := 2.0
# Goop (#135): blobs of lava ride down a stream, this far apart (px) and this
# fast (px a second). A thick stream only swells a little at each blob; a thin
# one necks down between them, and the thinnest breaks into separate drops.
const GOOP_LENGTH := 34.0
const GOOP_SPEED := 44.0
# Steam (#135): puffs that rise off cooling lava. Drawn only; never saved.
const PUFF_MAX := 260
const COL_STEAM := Color(0.93, 0.95, 1.0)
const COL_STEAM_LIT := Color(1.0, 0.84, 0.66)

var map
var mass: Dictionary = {}          # Vector2i -> float, cells holding lava
var shown: Dictionary = {}         # Vector2i -> float, smoothed mass for drawing
var magma: Dictionary = {}         # Vector2i -> true, magma rock still solid
var sources: Dictionary = {}       # Vector2i -> float, lava a breached cell still holds
var melt_timers: Dictionary = {}   # Vector2i -> seconds of lava contact
var heat := 0.0
var recalls := 0
var last_penalty := 0
var hardened := 0                 # lava cells water turned to rock this run
var last_hardened: Array = []     # the cells of the latest hardening
var _steam: Array = []            # [cell, seconds left] for the steam flash
var _puffs: Array = []            # steam puffs: [x, y, time born, seconds to live, 0..1 seed], this node's space
var _puff_rng := RandomNumberGenerator.new()
var _anchors: Dictionary = {}     # stream cell -> the side its lava comes from: -1 left, 1 right, 0 neither
var _stream_memo: Dictionary = {}  # stream cell -> _stream_params(), for one physics frame
var _housekeep := 0
var _view_c0 := Vector2i.ZERO      # the cells on screen at the last draw (steam only rises there)
var _view_c1 := Vector2i.ZERO
var breaches := 0
var recall_pos = null
var _acc := 0.0
var _time := 0.0
var _glow: Node2D
var _glow_tex: GradientTexture2D
var _barrier_glow_tex: GradientTexture2D
# Dev only: the old rule (every cell cools), for timing comparisons.
var legacy_cooling := false
# Dev only: hold the lava still (no flow or cooling) so a playtest can stand next to a fixed shape.
var freeze_flow := false
# Dev only: outline the keeper's lava-contact box.
var debug_boxes := false
var pools: Array = []              # Array of Array[Vector2i]: open pools filled at run start
var pools_skipped := 0             # pools left empty because something opened their wall
# Sleeping: only cells in _awake run the flow math. A cell wakes when its mass or
# a neighbour's changes, or a tile next to it is destroyed.
var _awake: Dictionary = {}
var _wake_all := true
var _shown_all := true            # every drawn cell needs smoothing (after a fill or load)
var _shown_dirty: Dictionary = {}  # cells whose drawn lava hasn't caught up yet
var _melt_check: Dictionary = {}   # magma cells that lava may be touching
var _melt_full := true             # scan all magma once (after a fill, load or direct edit)
const WAKE_EPS := 0.00005


func setup(p_map) -> void:
	map = p_map
	z_index = 6
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_glow = Node2D.new()
	_glow.name = "LavaGlow"
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	_glow.z_index = 1
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.42, 0.08, 1.0))
	grad.set_color(1, Color(1.0, 0.2, 0.0, 0.0))
	_glow_tex = GradientTexture2D.new()
	_glow_tex.gradient = grad
	_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_glow_tex.fill_from = Vector2(0.5, 0.5)
	_glow_tex.fill_to = Vector2(1.0, 0.5)
	_glow_tex.width = 64
	_glow_tex.height = 64
	var vgrad := Gradient.new()
	vgrad.set_color(0, Color(0.45, 0.38, 1.0, 1.0))
	vgrad.set_color(1, Color(0.3, 0.2, 1.0, 0.0))
	_barrier_glow_tex = GradientTexture2D.new()
	_barrier_glow_tex.gradient = vgrad
	_barrier_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_barrier_glow_tex.fill_from = Vector2(0.5, 0.5)
	_barrier_glow_tex.fill_to = Vector2(1.0, 0.5)
	_barrier_glow_tex.width = 64
	_barrier_glow_tex.height = 64
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	# Map facts the generator left (read once; they don't change during a run).
	_ocean = map.tileData.get_meta("story_ocean", {})
	var ch = map.tileData.get_meta("story_boss_chamber", null)
	_chamber = ch if ch is Rect2i else Rect2i()
	# A loaded run brings its lava back from the save; a new run places pockets.
	if not _restore(str(Data.ofOr(SAVE_KEY, ""))):
		_place_pockets()
		_fill_pools()
		_fill_ocean()
	map.tile_destroyed.connect(_on_tile_destroyed)
	add_to_group("saveable")


# --- pocket placement ----------------------------------------------------------

# Fills the open pools the map generator carved (map/story_gen.gd) brim-full.
# A pool whose wall something else opened (a cave placed at run start) is left
# empty rather than spilled.
func _fill_pools() -> void:
	var all = map.tileData.get_meta("story_pools", [])
	for pool in all:
		var set := {}
		for c in pool:
			set[Vector2i(c)] = true
		var sealed := true
		for c in set:
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = c + d
				if not set.has(n) and _is_open(n):
					sealed = false
		if not sealed or not _is_open(Vector2i(pool[0])):
			pools_skipped += 1
			continue
		# Brim-full and already settled: hydrostatic, a cell k rows below the
		# pool's top row holds 1 + MAX_COMPRESS x k. That is exactly where the
		# flow balances (a cell under another holds MAX_COMPRESS more; cells side
		# by side hold the same), so nothing moves, no top cell sinks under
		# FULL_MASS and cools, and the pool sleeps from the first step.
		var cells: Array = set.keys()
		var top: int = 1 << 20
		for c in cells:
			top = mini(top, c.y)
		_fill_hydrostatic(cells, top)
		pools.append(cells)
	wake_all()


# Fills `cells` brim-full and settled: a cell k rows below `top` holds
# 1 + MAX_COMPRESS x k, exactly where the flow balances.
func _fill_hydrostatic(cells: Array, top: int) -> void:
	for c in cells:
		var m: float = MAX_MASS + MAX_COMPRESS * float(c.y - top)
		mass[c] = m
		shown[c] = m


# The lava ocean the generator added (#43): every open cell in its rows, brim-full
# and hydrostatic like the pools, so it sits settled under its rock ceiling.
var ocean_cells := 0
var boss_chamber_reached := false
var _ocean: Dictionary = {}       # the generator's "story_ocean" meta (rows, columns, ceiling)
var _chamber: Rect2i = Rect2i()   # the boss chamber; lava never enters it


func _in_ocean(c: Vector2i) -> bool:
	if _ocean.is_empty():
		return false
	return c.y >= int(_ocean["top"]) and c.y <= int(_ocean["bottom"]) and c.x >= int(_ocean["x0"]) and c.x <= int(_ocean["x1"])


func _fill_ocean() -> void:
	if _ocean.is_empty():
		return
	var cells: Array = []
	for y in range(int(_ocean["top"]), int(_ocean["bottom"]) + 1):
		for x in range(int(_ocean["x0"]), int(_ocean["x1"]) + 1):
			if _is_open(Vector2i(x, y)):
				cells.append(Vector2i(x, y))
	_fill_hydrostatic(cells, int(_ocean["top"]))
	ocean_cells = cells.size()
	wake_all()


func ocean_mass() -> float:
	var t := 0.0
	for c in mass:
		if _in_ocean(c):
			t += mass[c]
	return t


func wake_all() -> void:
	_wake_all = true
	_shown_all = true
	_melt_full = true


func _wake(c: Vector2i) -> void:
	_awake[c] = true
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		_awake[c + d] = true


func _place_pockets() -> void:
	# Each plain rock cell decides for itself, from the level seed and its own
	# coordinates, whether it seeds a pocket. So the same seed gives the same
	# pockets however much of the mine has been dug (for example after a reload).
	var near_pool := {}
	for pool in map.tileData.get_meta("story_pools", []):
		for c in pool:
			for ox in range(-1, 2):
				for oy in range(-1, 2):
					near_pool[Vector2i(c) + Vector2i(ox, oy)] = true
	var rock_set := {}
	for c in map.tileData.get_resource_cells_by_id(Data.TILE_DIRT_START):
		# Nothing in the ocean's ceiling or below it: lava touches that rock.
		var by_ocean: bool = not _ocean.is_empty() and c.y >= int(_ocean["ceiling"])
		if c.y >= POCKET_MIN_DEPTH and map.tileData.get_hardnessv(c) < Data.HARDNESS_INDESTRUCTIBLE and not near_pool.has(c) and not by_ocean:
			rock_set[c] = true
	var rng := RandomNumberGenerator.new()
	for s in rock_set:
		if hash([Level.levelSeed, "lava", s.x, s.y]) % POCKET_CELLS_PER_POCKET != 0:
			continue
		rng.seed = hash([Level.levelSeed, "pocket", s.x, s.y])
		# Grow a blob by random walk; deeper pockets are bigger.
		var size := rng.randi_range(POCKET_SIZE_MIN, POCKET_SIZE_MAX) + int(s.y / 25.0)
		var cells := [s]
		var guard := 0
		while cells.size() < size and guard < 60:
			guard += 1
			var from: Vector2i = cells[rng.randi() % cells.size()]
			var n: Vector2i = from + [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN][rng.randi() % 4]
			if rock_set.has(n) and not cells.has(n):
				cells.append(n)
		for c in cells:
			magma[c] = true


func add_pocket(cells: Array) -> void:
	for c in cells:
		magma[Vector2i(c)] = true
	wake_all()


# --- breaching -----------------------------------------------------------------

func _on_tile_destroyed(world_pos: Vector2) -> void:
	var c: Vector2i = map.getTileCoord(world_pos)
	_wake(c)
	if not magma.has(c):
		return
	magma.erase(c)
	melt_timers.erase(c)
	sources[c] = sources.get(c, 0.0) + VOLUME_PER_MAGMA_CELL
	breaches += 1
	InputSystem.shake(6.0, 0.5, 20.0, world_pos)


# The boss chamber counts as closed for lava, so drilling into it from the
# ocean doesn't flood the arena; the lava rests on its ceiling (#43).
func _is_open(c: Vector2i) -> bool:
	return c.y >= MIN_Y and map.is_tile_empty(c) and not _chamber.has_point(c)


# --- simulation ----------------------------------------------------------------

# Time spent in this node's _physics_process (dev timing).
var phys_us := 0
var phys_frames := 0


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_stream_memo.clear()
	_physics_body(delta)
	phys_us += Time.get_ticks_usec() - t0
	phys_frames += 1


func _physics_body(delta: float) -> void:
	if map == null or GameWorld.paused:
		return
	_time += delta
	_acc += delta
	while _acc >= TICK:
		_acc -= TICK
		if not freeze_flow:
			_step()
	_melt(delta)
	_check_water()
	_update_heat(delta)
	if not _steam.is_empty():
		for e in _steam:
			e[1] -= delta
		_steam = _steam.filter(func(e): return e[1] > 0.0)
	_housekeep += 1
	if _housekeep >= 8:
		_housekeep = 0
		if not _puffs.is_empty():
			_puffs = _puffs.filter(func(q): return _time - q[2] < q[3])
		for c in _anchors.keys():
			if shown.get(c, 0.0) <= 0.02:
				_anchors.erase(c)
	# Smooth the drawn lava toward the simulated lava. Only cells that changed are
	# walked (a settled ocean costs nothing), unless something touched every cell.
	var k: float = min(1.0, delta * 9.0)
	if _shown_all:
		_shown_all = false
		for c in mass:
			_shown_dirty[c] = true
		for c in shown:
			_shown_dirty[c] = true
	for c in _shown_dirty.keys():
		var target: float = mass.get(c, 0.0)
		var v: float = lerp(shown.get(c, 0.0), target, k)
		if absf(v - target) < 0.002:
			_shown_dirty.erase(c)
			v = target
		if v < 0.01 and not mass.has(c):
			shown.erase(c)
		else:
			shown[c] = v
	queue_redraw()
	_glow.queue_redraw()


func _stable_split(total: float) -> float:
	# How much of `total` the lower of two stacked cells should hold.
	if total <= MAX_MASS:
		return MAX_MASS
	if total < 2.0 * MAX_MASS + MAX_COMPRESS:
		return (MAX_MASS * MAX_MASS + total * MAX_COMPRESS) / (MAX_MASS + MAX_COMPRESS)
	return (total + MAX_COMPRESS) / 2.0


func _step() -> void:
	# Breached magma cells push their lava out while they have any left.
	for c in sources.keys():
		var room: float = MAX_MASS + MAX_COMPRESS - mass.get(c, 0.0)
		var out: float = min(SOURCE_RATE, min(sources[c], room))
		if out > 0.0:
			mass[c] = mass.get(c, 0.0) + out
			sources[c] -= out
			_wake(c)
		if sources[c] <= 0.001:
			sources.erase(c)

	var all_awake: bool = _wake_all or legacy_cooling
	_wake_all = false
	# Nothing moving anywhere: a settled field costs nothing.
	if not all_awake and _awake.is_empty():
		return
	# Flows are worked out from this step's masses and collected as deltas, so a
	# step touches only the cells that move, not every lava cell on the map.
	var work: Array = mass.keys() if all_awake else _awake.keys().filter(func(c): return mass.has(c))
	var dm: Dictionary = {}
	for c in work:
		var m: float = mass[c]
		if m <= 0.0:
			continue
		var remaining := m
		var below: Vector2i = c + Vector2i.DOWN
		var below_open := _is_open(below)
		if below_open:
			var mb: float = mass.get(below, 0.0)
			var flow: float = _stable_split(remaining + mb) - mb
			if flow > MIN_FLOW:
				flow *= 0.6
			flow = clamp(flow, 0.0, min(MAX_FLOW, remaining))
			if flow > 0.0:
				dm[c] = dm.get(c, 0.0) - flow
				dm[below] = dm.get(below, 0.0) + flow
				remaining -= flow
		if remaining <= 0.0:
			continue
		# Sideways: only once the lava rests on something, and not as a thin film.
		var resting: bool = not below_open or mass.get(below, 0.0) >= MAX_MASS * 0.9
		if resting and remaining > STICKY_MASS:
			for side in [Vector2i.LEFT, Vector2i.RIGHT]:
				var sc: Vector2i = c + side
				if not _is_open(sc):
					continue
				var flow: float = (m - mass.get(sc, 0.0)) / SIDE_FLOW_DIVISOR
				flow = clamp(flow, 0.0, min(MAX_FLOW, remaining))
				if flow > MIN_FLOW:
					dm[c] = dm.get(c, 0.0) - flow
					dm[sc] = dm.get(sc, 0.0) + flow
					remaining -= flow
		if remaining <= MAX_MASS:
			continue
		# Up: only lava squeezed past a full cell rises.
		var above: Vector2i = c + Vector2i.UP
		if _is_open(above):
			var flow: float = remaining - _stable_split(remaining + mass.get(above, 0.0))
			flow = clamp(flow * 0.6, 0.0, min(MAX_FLOW, remaining))
			if flow > MIN_FLOW:
				dm[c] = dm.get(c, 0.0) - flow
				dm[above] = dm.get(above, 0.0) + flow

	# The cells that may change: those that flowed, and the awake ones (cooling).
	var nv: Dictionary = {}
	for c in work:
		nv[c] = mass[c] + dm.get(c, 0.0)
	for c in dm:
		if not nv.has(c):
			nv[c] = mass.get(c, 0.0) + dm[c]
	# Cooling is decided on the flowed masses, then applied.
	var cool: Array = []
	for c in nv:
		# A sleeping cell's neighbours didn't change, so neither did its cooling.
		if (all_awake or _awake.has(c)) and (legacy_cooling or _cools(c, nv[c], nv, mass)):
			cool.append(c)
	for c in cool:
		var film: bool = nv[c] < FILM_MASS
		nv[c] -= (FILM_COOL_PER_SECOND if film else COOL_PER_SECOND) * TICK
		# Steam off the cooling lava: thick off a thin film (it cools fast), a wisp
		# now and then off a deeper puddle, and a last hiss as a film hardens.
		if _on_screen(c):
			if nv[c] <= MIN_MASS:
				_puff(c, 3)
			elif _puff_rng.randf() < (0.3 if film else 0.035):
				_puff(c, 1)
	var woke: Dictionary = {}
	for c in nv:
		var m: float = nv[c]
		var had: bool = mass.has(c)
		var o: float = mass.get(c, 0.0)
		# MIN_MASS only prunes numerical dust.
		if m > MIN_MASS:
			mass[c] = m
		elif had:
			mass.erase(c)
		if absf(m - o) > WAKE_EPS or (m <= MIN_MASS and had):
			woke[c] = true
			_shown_dirty[c] = true
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP]:
				if magma.has(c + d):
					_melt_check[c + d] = true
	_awake = {}
	for c in woke:
		_wake(c)


# Lava cools only at a thin, open surface (#41): nothing below it, and its top
# open to air (open space above with no lava, or the cell itself not full). So
# a brim-full pool under rock keeps its lava for good; a thinned-out layer with
# air above it cools away.
func _cools(c: Vector2i, m: float, cells: Dictionary, base: Dictionary = {}) -> bool:
	# `cells` holds this step's new masses; `base` the rest (cells that didn't move).
	var below: Vector2i = c + Vector2i.DOWN
	if (cells[below] if cells.has(below) else base.get(below, 0.0)) >= LavaData.HOLDS_MASS:
		return false
	var above: Vector2i = c + Vector2i.UP
	if (cells[above] if cells.has(above) else base.get(above, 0.0)) >= LavaData.HOLDS_MASS:
		return false
	return _is_open(above) or m < LavaData.FULL_MASS


# The cells that would cool this step (for playtests).
func cooling_cells() -> Array:
	var out: Array = []
	for c in mass:
		if _cools(c, mass[c], mass):
			out.append(c)
	out.sort()
	return out


# --- save and load ---------------------------------------------------------------
# Vanilla saves every node in group "saveable" before it saves Data. This node's
# serialize() puts the lava into Data (SAVE_KEY), and vanilla's loader skips its
# own entry (an unknown kind). Data is cleared for every new run, so the key is
# only there when a saved run is loaded.

func serialize() -> Dictionary:
	var cells: Array = []
	for c in mass:
		cells.append([c.x, c.y, snappedf(mass[c], 0.0001)])
	var src: Array = []
	for c in sources:
		src.append([c.x, c.y, snappedf(sources[c], 0.0001)])
	var rock: Array = []
	for c in magma:
		rock.append([c.x, c.y])
	Data.apply(SAVE_KEY, JSON.stringify({"seed": Level.levelSeed, "mass": cells, "sources": src, "magma": rock,
		"heat": heat, "breaches": breaches, "recalls": recalls, "ocean_cells": ocean_cells, "boss_chamber_reached": boss_chamber_reached}))
	return {"meta.priority": 9000, "meta.kind": "storylava"}


func _restore(blob: String) -> bool:
	if blob == "":
		return false
	var d = JSON.parse_string(blob)
	if not d is Dictionary or int(d.get("seed", -1)) != Level.levelSeed:
		return false
	mass.clear()
	sources.clear()
	magma.clear()
	for e in d.get("mass", []):
		mass[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	for e in d.get("sources", []):
		sources[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	for e in d.get("magma", []):
		magma[Vector2i(int(e[0]), int(e[1]))] = true
	shown = mass.duplicate()
	wake_all()
	heat = float(d.get("heat", 0.0))
	breaches = int(d.get("breaches", 0))
	recalls = int(d.get("recalls", 0))
	ocean_cells = int(d.get("ocean_cells", 0))
	boss_chamber_reached = bool(d.get("boss_chamber_reached", false))
	ModLoaderLog.info("Lava restored from save: %d cells, %d magma" % [mass.size(), magma.size()], "cejdan-StoryMode")
	return true


func _melt(delta: float) -> void:
	# Lava resting against magma rock melts it, which releases that rock's lava too.
	if magma.is_empty() or mass.is_empty():
		_melt_check.clear()
		return
	# Only magma next to lava that moved can start touching it, so only those
	# cells are watched (_step adds them); after a fill or load, scan it all once.
	if _melt_full:
		_melt_full = false
		for m in magma:
			_melt_check[m] = true
	var touched := {}
	for m in _melt_check.keys():
		if not magma.has(m):
			_melt_check.erase(m)
			continue
		var hot := false
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP]:
			if mass.get(m + d, 0.0) >= 0.1:
				hot = true
				break
		if hot:
			touched[m] = true
		else:
			_melt_check.erase(m)
	for c in melt_timers.keys():
		if not touched.has(c):
			melt_timers.erase(c)
	for c in touched:
		melt_timers[c] = melt_timers.get(c, 0.0) + delta
		if melt_timers[c] >= MELT_SECONDS:
			var tile = map.getTile(Vector2(c))
			if tile != null and is_instance_valid(tile):
				map.destroyTile("team1", "", tile)   # fires tile_destroyed -> breach
			melt_timers.erase(c)


# --- water hardens lava (#47) ----------------------------------------------------

# Only water drops are checked, against the cell each one is in.
func _check_water() -> void:
	if mass.is_empty() or Level.drops == null:
		return
	for d in Level.drops.get_children():
		if not "type" in d or d.type != CONST.WATER or d.absorbed or not is_instance_valid(d):
			continue
		var c: Vector2i = map.getTileCoord(d.global_position)
		if not lava_overlaps(Rect2(d.global_position - Vector2(2, 2), Vector2(4, 4))):
			continue
		var cells := _harden_from(c, LavaData.WATER_HARDENS_CELLS)
		for k in Keepers.getAll():
			if k.carriedCarryables.has(d):
				k.dropCarry(d)
		d.remove()
		InputSystem.shake(6.0, 0.35, 20.0, d.global_position)
		ModLoaderLog.info("Water hardened %d lava cells" % cells.size(), "cejdan-StoryMode")


# Breadth-first from `start` through connected lava (>= BURN_MASS), nearest
# first, up to `limit` cells; each becomes plain rock. Returns the cells.
func _harden_from(start: Vector2i, limit: int) -> Array:
	var out: Array = []
	var seen := {start: true}
	var open: Array = [start]
	while not open.is_empty() and out.size() < limit:
		var c: Vector2i = open.pop_front()
		if mass.get(c, 0.0) < BURN_MASS:
			continue
		out.append(c)
		for d in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			var n: Vector2i = c + d
			if not seen.has(n):
				seen[n] = true
				open.append(n)
	for c in out:
		_harden(c)
	last_hardened = out
	hardened += out.size()
	return out


# One lava cell becomes an ordinary rock tile: no resource, drillable, the cell's
# own hardness (or medium in a dug cell that had none).
func _harden(c: Vector2i) -> void:
	mass.erase(c)
	shown.erase(c)
	_wake(c)
	var td = map.tileData
	if td.get_hardnessv(c) < 0 or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE:
		td.set_hardnessv(c, Data.HARDNESS_MEDIUM)
	td.set_resourcev(c, Data.TILE_DIRT_START)
	map.visibleTileCoords.erase(Vector2(c))
	map.revealTile(Vector2(c))
	if map.has_method("restoreTileVisually"):
		map.restoreTileVisually(Vector2(c))
	map.updateBorderSpriteOfTileCoord(Vector2(c))
	_steam.append([c, LavaData.STEAM_SECONDS])
	_puff(c, 6, true)


# --- suit heat -----------------------------------------------------------------

func lava_at(world_pos: Vector2) -> float:
	return mass.get(map.getTileCoord(world_pos), 0.0)


# Rows between which passive heat ramps from 0 to its full rate (cached).
var _heat_top := -1
var _heat_bottom := -1
var passive_rate := 0.0            # passive heat per second right now (after Heat Shielding)


func _heat_rows() -> void:
	_heat_top = 1 << 20
	_heat_bottom = -(1 << 20)
	for c in map.tileData.get_used_biome_cells():
		if map.tileData.get_resourcev(c) == Data.TILE_BORDER:
			continue
		_heat_bottom = maxi(_heat_bottom, c.y)
		if map.tileData.get_biomev(c) >= LavaData.PASSIVE_HEAT_START_BIOME:
			_heat_top = mini(_heat_top, c.y)
	if not _ocean.is_empty():
		_heat_bottom = int(_ocean["ceiling"])


# Passive heat per second at a tile, before Heat Shielding: 0 above B4.
func passive_rate_at(tile: Vector2i) -> float:
	if _heat_top < 0:
		_heat_rows()
	if map.tileData.get_biomev(tile) < LavaData.PASSIVE_HEAT_START_BIOME:
		return 0.0
	var f: float = clampf(float(tile.y - _heat_top) / maxf(1.0, float(_heat_bottom - _heat_top)), 0.0, 1.0)
	return LavaData.PASSIVE_HEAT_RATE_AT_BOTTOM * f


func _update_heat(delta: float) -> void:
	var keeper = Keepers.first()
	if keeper == null or not is_instance_valid(keeper) or keeper.killed:
		return
	if recall_pos == null and Level.stage is LevelStage and Level.stage.keeperInputStarted:
		recall_pos = keeper.global_position
	# Passive heat from depth (#46), out of the dome, scaled by Heat Shielding.
	passive_rate = 0.0
	var passive_zone := false
	# The sealed boss chamber keeps the depth's heat out while Velle fights (#160).
	var sealed: bool = str(Data.ofOr("team1.story.boss", "")) == "fight"
	if not keeper.isInsideDome and not keeper.disabled and not sealed:
		var raw: float = passive_rate_at(map.getTileCoord(keeper.global_position))
		passive_zone = raw > 0.0 or map.tileData.get_biomev(map.getTileCoord(keeper.global_position)) >= LavaData.PASSIVE_HEAT_START_BIOME
		passive_rate = raw * LavaData.passive_heat_mult(keeper.teamId)
	if keeper_in_lava(keeper) and not keeper.disabled:
		# Heat Shielding (#44) slows lava heat but never stops it.
		heat = min(HEAT_MAX, heat + (HEAT_PER_SECOND * LavaData.lava_heat_mult(keeper.teamId) + passive_rate) * delta)
	elif keeper.isInsideDome:
		heat = max(0.0, heat - COOL_DOME_PER_SECOND * delta)
	elif passive_zone and LavaData.passive_heat_mult(keeper.teamId) > 0.0:
		# Deep and out of lava: heat only rises.
		heat = min(HEAT_MAX, heat + passive_rate * delta)
	else:
		heat = max(0.0, heat - COOL_MINE_PER_SECOND * delta)
	if heat >= HEAT_MAX:
		# Velle jams the suit's recall through the boss sequence (#160):
		# overheating costs a heart there, not a trip home.
		var BossDirector = load("res://mods-unpacked/cejdan-StoryMode/boss/boss_director.gd")
		if BossDirector.jams_recall():
			heat = HEAT_MAX * load("res://mods-unpacked/cejdan-StoryMode/data/boss.gd").OVERHEAT_HEAT_AFTER
			BossDirector.overheated()
		else:
			_recall(keeper)
	if not boss_chamber_reached and _chamber.size != Vector2i.ZERO:
		if _chamber.has_point(map.getTileCoord(keeper.global_position)):
			boss_chamber_reached = true
			ModLoaderLog.info("boss chamber reached", "cejdan-StoryMode")
			# Breaking into the chamber wakes the horror (#95).
			if Story.is_story():
				load("res://mods-unpacked/cejdan-StoryMode/beats/awakening.gd").wake()


func _recall(keeper) -> void:
	# Placeholder for "the keeper dies in the mine": the suit dumps its cargo where
	# it stands and yanks the keeper back to the dome.
	recalls += 1
	heat = 0.0
	# The horror is tender about it (#26): its own beat for each of the first
	# five deaths in a run (#157); the 5th plays again on every death after.
	if Story.is_story():
		load("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd").trigger("lava_death:%d" % mini(recalls, 5))
	for c in keeper.carriedCarryables.duplicate():
		if is_instance_valid(c):
			keeper.dropCarry(c)
	InputSystem.shake(10.0, 0.4, 24.0)
	if recall_pos != null:
		keeper.teleport(recall_pos)
	# Dying in the deep costs half the money (#45). With $0 or $1 it stays free.
	last_penalty = 0
	if Story.is_story():
		var key: String = keeper.teamId + ".inventory.money"
		var loss: int = int(floor(int(Data.ofOr(key, 0)) / 2.0))
		if loss > 0:
			Data.changeByInt(key, -loss)
			last_penalty = loss
			_float_loss(keeper, loss)
		ModLoaderLog.info("Overheat recall: lost $%d" % loss, "cejdan-StoryMode")


# A short "-$X" rising over the keeper where it lands (placeholder look; the
# money HUD also flashes red on any loss).
func _float_loss(keeper, loss: int) -> void:
	var label := Label.new()
	label.text = "-$" + str(loss)
	label.add_theme_font_override("font", load("res://gui/fonts/FontHudPixelartMonospaced.tres"))
	label.add_theme_color_override("font_color", Color("ff4a3a"))
	label.add_theme_color_override("font_outline_color", Color("12121a"))
	label.add_theme_constant_override("outline_size", 6)
	label.scale = Vector2(1.25, 1.25)
	label.z_index = 50
	label.position = to_local(keeper.global_position) + Vector2(-40, -70)
	add_child(label)
	var tw := label.create_tween()
	tw.tween_property(label, "position:y", label.position.y - 30.0, 2.5)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 2.5).set_delay(1.0)
	tw.tween_callback(label.queue_free)


# --- drawing -------------------------------------------------------------------

func _cell_origin(c: Vector2i) -> Vector2:
	# Top-left corner of a tile, in this node's space (same space as the Map node).
	return to_local(map.getTilePos(Vector2(c))) - Vector2(TILE, TILE) * 0.5


func _noise(c: Vector2i, i: int) -> float:
	return fposmod(sin(float(c.x * 127 + c.y * 311 + i * 74)) * 43758.5453, 1.0)


# The lava cells on screen (plus a margin), so drawing costs the same however
# much lava the map holds. Falls back to every cell if the view can't be read.
var _vis_frame := -1
var _vis_cache: Array = []


# Both draw passes (lava and glow) share one list per frame.
func _visible_cells() -> Array:
	var f := Engine.get_process_frames()
	if f != _vis_frame:
		_vis_frame = f
		_vis_cache = _visible_cells_now()
	return _vis_cache


func _visible_cells_now() -> Array:
	var vp := get_viewport()
	if vp == null:
		return shown.keys()
	var inv: Transform2D = get_global_transform_with_canvas().affine_inverse()
	var vr: Rect2 = vp.get_visible_rect()
	var a: Vector2 = inv * vr.position
	var b: Vector2 = inv * vr.end
	var lo: Vector2 = Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi: Vector2 = Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var c0: Vector2i = map.getTileCoord(to_global(lo)) - Vector2i(2, 2)
	var c1: Vector2i = map.getTileCoord(to_global(hi)) + Vector2i(2, 2)
	_view_c0 = c0
	_view_c1 = c1
	if (c1.x - c0.x) * (c1.y - c0.y) > shown.size():
		return shown.keys()
	var out: Array = []
	for y in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			var c := Vector2i(x, y)
			if shown.has(c):
				out.append(c)
	return out


# Lava in a cell the player hasn't revealed yet (an unopened pool) stays hidden.
func _seen(c: Vector2i) -> bool:
	return map.visibleTileCoords.has(Vector2(c)) or map.visibleTileCoords.has(c)


# The lava in a cell as it is drawn, in this node's space: a pouring stream
# (a column) or a body (a rect at the cell's bottom, f x TILE tall, or the full
# cell under more lava). _draw() and the burn and water checks all use this, so
# what burns is what the player sees (#48). A stream's rect is its steady
# extent (without the goop's swelling); "ext" is the part of it that runs on
# into the cell below, down to the lava it lands on. _draw() draws it in
# slices along stream_edges() (#122).
func _lava_shape(c: Vector2i) -> Dictionary:
	var f := _fill_of(c)
	var o := _cell_origin(c)
	# Lava resting above (a body, not a stream pouring in) fills this cell to the top.
	var up: Vector2i = c + Vector2i.UP
	var above_has: bool = shown.get(up, 0.0) > 0.05 and not _is_stream(up)
	if f <= 0.02:
		return {"rect": Rect2(o, Vector2.ZERO), "stream": false, "above_has": above_has}
	if _is_stream(c):
		var p: Array = _stream_params(c)
		var e: Vector2 = _edges(p, c, 0.5, false)
		return {"rect": Rect2(o + Vector2(e.x, p[3]), Vector2(e.y - e.x, TILE - p[3])), "stream": true, "above_has": above_has,
			"ext": Rect2(o + Vector2(e.x, TILE), Vector2(e.y - e.x, p[4]))}
	var h: float = _body_height(c, above_has)
	return {"rect": Rect2(o + Vector2(0, TILE - h), Vector2(TILE, h)), "stream": false, "above_has": above_has}


# How tall a resting cell's lava is drawn (px).
func _body_height(c: Vector2i, above_has: bool) -> float:
	var f := _fill_of(c)
	return TILE if (above_has or f >= 0.98) else max(2.0, round(f * TILE))


# Falling lava (#122): the cell below is open and not yet full. It draws as a
# stream whether or not lava falls into it from above, so a long column is one
# stream all the way down. (It used to need an empty cell above, so a column's
# cells drew as stacked full-width pool blocks, and film cells near the 0.05
# threshold flickered between a thin stream and a full block.) A cell with
# resting lava on both sides is the bottom of a pool draining through a hole,
# and stays a body, as does a near-full cell. With resting lava on one side
# only it is the lip of a ledge: a stream that starts at that lava (#135).
func _is_stream(c: Vector2i) -> bool:
	var f := _fill_of(c)
	if f >= 0.9 or not _falling(c):
		return false
	return not (_pool_beside(c + Vector2i.LEFT) and _pool_beside(c + Vector2i.RIGHT))


func _pool_beside(n: Vector2i) -> bool:
	return shown.get(n, 0.0) > 0.2 and not _falling(n)


func _falling(c: Vector2i) -> bool:
	var below: Vector2i = c + Vector2i.DOWN
	return _is_open(below) and shown.get(below, 0.0) < 0.95


# Lava lying in a cell (not falling through it): what a stream can pour from.
func _rests(n: Vector2i) -> bool:
	return shown.get(n, 0.0) > 0.05 and not _falling(n)


# A stream's width: thicker with more lava, from the cell's fill averaged with
# the stream cells above and below it, so lava moving down the column in
# lumps (the simulation passes it on a tick at a time) doesn't pulse.
func _stream_width(c: Vector2i) -> float:
	var f := _fill_of(c)
	var up: Vector2i = c + Vector2i.UP
	var dn: Vector2i = c + Vector2i.DOWN
	var fa: float = _fill_of(up) if shown.get(up, 0.0) > 0.02 and _falling(up) else f
	var fb: float = _fill_of(dn) if shown.get(dn, 0.0) > 0.02 and _falling(dn) else f
	var fs: float = (fa + 2.0 * f + fb) / 4.0
	return clampf(6.0 + fs * 16.0, 4.0, TILE)


# The side a stream's lava comes from (#135): -1 when it pours off lava resting
# to its left, 1 to its right, 0 when it comes from straight above. The stream
# is drawn against that side of its cells, so it leaves its source's edge and
# runs down the rock face under it, instead of hanging in the middle of the
# tile. The whole column takes the side of its top cell, and keeps it when the
# source runs dry and the last of the stream falls away.
func _stream_anchor(c: Vector2i) -> float:
	var up: Vector2i = c + Vector2i.UP
	var a: float
	if shown.get(up, 0.0) > 0.02 and _is_stream(up):
		a = _anchors[up] if _anchors.has(up) else _stream_anchor(up)
	else:
		var l: bool = _rests(c + Vector2i.LEFT)
		var r: bool = _rests(c + Vector2i.RIGHT)
		if l != r:
			a = -1.0 if l else 1.0
		else:
			a = _anchors.get(c, 0.0)
	_anchors[c] = a
	return a


# What _draw() and the contact checks need to know about a stream cell, worked
# out once a physics frame:
# [0] the side it hangs on (_stream_anchor), [1] its width, [2] its width at
# the cell's bottom (the next stream cell's width), [3] where it starts, px
# from the cell's top (the lip of a ledge starts at its source's surface),
# [4] how far it runs on into the cell below (down to the lava it lands on),
# [5] its lower end: 0 another stream cell, 1 it lands on lava, 2 a free tip,
# [6] true when its top is a free end (nothing above, no source beside).
func _stream_params(c: Vector2i) -> Array:
	if _stream_memo.has(c):
		return _stream_memo[c]
	var a: float = _stream_anchor(c)
	var w0: float = _stream_width(c)
	var w1: float = w0
	var ext := 0.0
	var end := 2
	var dn: Vector2i = c + Vector2i.DOWN
	if shown.get(dn, 0.0) > 0.02:
		if _is_stream(dn):
			end = 0
			w1 = _stream_width(dn)
		else:
			end = 1
			ext = TILE - _body_height(dn, false)
	var top := 0.0
	var free_top := false
	if shown.get(c + Vector2i.UP, 0.0) <= 0.02:
		var n: Vector2i = c + (Vector2i.LEFT if a < 0.0 else Vector2i.RIGHT)
		if a != 0.0 and _rests(n):
			var n_up: Vector2i = n + Vector2i.UP
			top = TILE - _body_height(n, shown.get(n_up, 0.0) > 0.05 and not _is_stream(n_up))
		else:
			free_top = true
	var p: Array = [a, w0, w1, top, ext, end, free_top]
	_stream_memo[c] = p
	return p


# A stream's left and right edge (x from the cell's left side) at `t` of the
# way down the cell (0 top, 1 bottom; past 1 where it runs on into the cell
# below). The width blends into the next stream cell's, and the goop and the
# wobble follow world height, so the column has no steps at cell borders.
func stream_edges(c: Vector2i, t: float) -> Vector2:
	return _edges(_stream_params(c), c, t, true)


func _edges(p: Array, c: Vector2i, t: float, goop: bool) -> Vector2:
	var w: float = lerpf(p[1], p[2], clampf(t, 0.0, 1.0))
	var y_px: float = (float(c.y) + t) * TILE
	if goop:
		# Blobs ride down the stream; each is a teardrop, fat at its lower end.
		# (u runs 0..1 down one blob: a tail that widens slowly, a round end.)
		var thin: float = 1.0 - smoothstep(6.4, 7.6, w)
		var u: float = fposmod((y_px - _time * GOOP_SPEED) / GOOP_LENGTH + _noise(Vector2i(c.x, 0), 3), 1.0)
		w = maxf(0.0, lerpf(w * (0.78 - 1.9 * thin), maxf(w * 1.18, 6.5), 3.079 * u * sqrt(u * (1.0 - u))))
	var a: float = p[0]
	var lo: float
	if a < 0.0:
		lo = 0.0
	elif a > 0.0:
		lo = TILE - w
	else:
		lo = TILE * 0.5 + sin(_time * 5.0 - y_px * 0.054) * 1.5 - w * 0.5
	return Vector2(clampf(round(lo), 0.0, TILE), clampf(round(lo + w), 0.0, TILE))


# Does a rect (world space) overlap drawn lava that is deep enough to burn
# (BURN_MASS)? BURN_TOLERANCE px of overlap are forgiven, so skimming the
# surface doesn't flicker.
func lava_overlaps(world_rect: Rect2) -> bool:
	var a: Vector2i = map.getTileCoord(world_rect.position)
	var b: Vector2i = map.getTileCoord(world_rect.end)
	var local := Rect2(to_local(world_rect.position), world_rect.size)
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			var c := Vector2i(x, y)
			# A stream pouring in from the cell above runs on down to this cell's lava.
			var up: Vector2i = c + Vector2i.UP
			if mass.get(up, 0.0) >= BURN_MASS and shown.get(up, 0.0) > 0.02 and _is_stream(up):
				var ext: Rect2 = _lava_shape(up)["ext"].grow(-BURN_TOLERANCE)
				if ext.size.x > 0.0 and ext.size.y > 0.0 and ext.intersects(local):
					return true
			if mass.get(c, 0.0) < BURN_MASS:
				continue
			var r: Rect2 = _lava_shape(c)["rect"].grow(-BURN_TOLERANCE)
			if r.size.x > 0.0 and r.size.y > 0.0 and r.intersects(local):
				return true
	return false


# The keeper's body for lava contact: a fixed box around its position, from its
# collision shapes (a 5 px circle and two small squares 3.9 px above and below).
func keeper_rect(keeper) -> Rect2:
	return Rect2(keeper.global_position - KEEPER_BOX * 0.5, KEEPER_BOX)


func keeper_in_lava(keeper) -> bool:
	return lava_overlaps(keeper_rect(keeper))


func _fill_of(c: Vector2i) -> float:
	return clamp(shown.get(c, 0.0), 0.0, 1.0)


func _draw() -> void:
	# Magma rock the player can see: glowing cracks that pulse.
	for c in magma:
		if not map.tiles.has(Vector2(c)):
			continue
		var o := _cell_origin(c)
		var pulse: float = 0.55 + 0.45 * sin(_time * 3.0 + c.x * 1.7 + c.y * 0.9)
		for i in 5:
			var p := Vector2(3 + floor(_noise(c, i) * 17.0), 3 + floor(_noise(c, i + 9) * 17.0))
			var horizontal := _noise(c, i + 20) > 0.5
			var length: float = 3.0 + floor(_noise(c, i + 30) * 5.0)
			var size := Vector2(length, 1) if horizontal else Vector2(1, length)
			draw_rect(Rect2(o + p, size), Color(COL_HOT, 0.35 + 0.65 * pulse))
			draw_rect(Rect2(o + p, Vector2(1, 1)), Color(COL_CORE, pulse))

	for c in _visible_cells():
		var f := _fill_of(c)
		if f <= 0.02 or not _seen(c):
			continue
		var o := _cell_origin(c)
		var sh: Dictionary = _lava_shape(c)
		var above_has: bool = sh["above_has"]
		if sh["stream"]:
			_draw_stream(c, o)
			continue
		var h: float = sh["rect"].size.y
		var top: float = TILE - h
		# A thin film with nothing under it is cooling away (#41): it dulls from
		# bright to a dark crust as it goes.
		var warm: float = 1.0
		if f < FILM_MASS and not above_has and shown.get(c + Vector2i.DOWN, 0.0) < LavaData.HOLDS_MASS:
			warm = clampf(f / FILM_MASS, 0.0, 1.0)
		draw_rect(Rect2(o + Vector2(0, top), Vector2(TILE, h)), COL_CRUST.lerp(COL_BODY, warm))
		# Darker toward the bottom of a deep pool.
		if h > 10:
			draw_rect(Rect2(o + Vector2(0, TILE - floor(h * 0.35)), Vector2(TILE, floor(h * 0.35))), COL_DEEP)
		# Slow drifting crust plates and hot veins.
		for i in 4:
			var px: float = floor(fposmod(_noise(c, i) * TILE + _time * (2.0 + 3.0 * _noise(c, i + 5)), TILE - 4.0))
			var py: float = top + 3.0 + floor(_noise(c, i + 11) * max(1.0, h - 6.0))
			if py + 2.0 > TILE:
				continue
			var hot := i % 2 == 0
			draw_rect(Rect2(o + Vector2(px, py), Vector2(4 if hot else 3, 1 if hot else 2)), COL_HOT if hot else COL_CRUST)
		if not above_has:
			# Bright rippling surface.
			for x in range(0, int(TILE), 2):
				var ripple: float = round(sin(_time * 4.0 + (c.x * TILE + x) * 0.35))
				draw_rect(Rect2(o + Vector2(x, top + max(0.0, ripple)), Vector2(2, 2)), COL_DEEP.lerp(COL_CORE, warm))
			draw_rect(Rect2(o + Vector2(0, top + 2), Vector2(TILE, 1)), COL_CRUST.lerp(COL_HOT, warm))
			# Embers that pop off the surface.
			for i in (2 if warm > 0.6 else 0):
				var t: float = fposmod(_time * (0.5 + _noise(c, i + 40)) + _noise(c, i + 50), 1.0)
				var ex: float = floor(_noise(c, i + 60 + int(_time * 0.5)) * (TILE - 1.0))
				draw_rect(Rect2(o + Vector2(ex, top - t * 14.0), Vector2(1, 1)), Color(COL_CORE, 1.0 - t))

	# Steam where water just hardened lava: a white-grey flash that fades.
	for e in _steam:
		var a: float = clampf(e[1] / LavaData.STEAM_SECONDS, 0.0, 1.0)
		var o := _cell_origin(e[0])
		draw_rect(Rect2(o - Vector2(3, 6 + (1.0 - a) * 10.0), Vector2(TILE + 6, TILE + 6)), Color(0.92, 0.92, 0.95, 0.45 * a))
	_draw_puffs()
	_draw_barrier()
	_draw_heat_bar()
	if debug_boxes:
		var k = Keepers.first()
		if k != null and is_instance_valid(k):
			var r := keeper_rect(k)
			draw_rect(Rect2(to_local(r.position), r.size), Color(0.3, 1.0, 0.4, 0.9), false, 1.0)


# A pouring stream (#135): a ribbon of 2 px slices along stream_edges(), so it
# runs on unbroken from cell to cell (#122). It starts at the surface of the
# lava it pours from, with a rounded shoulder; runs on down to the lava it
# lands on, where it spreads into a foot and throws sparks; and ends in a
# rounded tip while it is still falling through empty space.
func _draw_stream(c: Vector2i, o: Vector2) -> void:
	var p: Array = _stream_params(c)
	var a: float = p[0]
	var top: float = p[3]
	var end: int = p[5]
	var bottom: float = TILE + p[4]
	var y: float = top
	var last_mid: float = TILE * 0.5
	while y < bottom:
		var hgt: float = minf(STREAM_SLICE, bottom - y)
		var e: Vector2 = _edges(p, c, (y + hgt * 0.5) / TILE, true)
		var w: float = e.y - e.x
		# Rounded ends.
		var k: float = 1.0
		if top > 0.0 and y - top < 6.0:
			k = sqrt(1.0 - pow(1.0 - (y - top + 2.0) / 8.0, 2.0))
		elif p[6] and y < 8.0:
			k = (y + 2.0) / 10.0
		if end == 2 and y >= TILE - 6.0:
			k *= sqrt(maxf(0.0, 1.0 - pow((y + hgt - (TILE - 6.0)) / 6.5, 2.0)))
		if k < 1.0:
			var nw: float = round(w * k)
			if a < 0.0:
				e.y = e.x + nw
			elif a > 0.0:
				e.x = e.y - nw
			else:
				e.x = round((e.x + e.y - nw) * 0.5)
				e.y = e.x + nw
		# The foot: the last few px spread out over the lava it lands on.
		if end == 1 and w > 0.0 and bottom - y <= 4.0:
			var spread: float = 1.0 if bottom - y > 2.0 else 2.0
			if a <= 0.0:
				e.y = minf(TILE, e.y + spread)
			if a >= 0.0:
				e.x = maxf(0.0, e.x - spread)
		w = e.y - e.x
		if w >= 1.0:
			last_mid = (e.x + e.y) * 0.5
			draw_rect(Rect2(o + Vector2(e.x, y), Vector2(w, hgt)), COL_BODY)
			if w > 2.0:
				# The dark rim is on the stream's free sides only.
				var l: float = e.x + (0.0 if a < 0.0 else 1.0)
				var r: float = e.y - (0.0 if a > 0.0 else 1.0)
				draw_rect(Rect2(o + Vector2(l, y), Vector2(r - l, hgt)), COL_HOT)
				if w > 5.0:
					var cw: float = maxf(2.0, round(w * 0.3))
					draw_rect(Rect2(o + Vector2(round((l + r - cw) * 0.5), y), Vector2(cw, hgt)), COL_CORE)
		y += STREAM_SLICE
	if end == 1:
		# Sparks thrown up where the stream lands.
		for i in 3:
			var ph: float = _time * (1.3 + _noise(c, i + 70)) + _noise(c, i + 75)
			var t: float = fposmod(ph, 1.0)
			var dx: float = (_noise(c, i + 80 + int(ph)) - 0.5) * 22.0 * t
			draw_rect(Rect2(o + Vector2(round(last_mid + dx), round(bottom - 1.0 - 28.0 * t * (1.0 - t))), Vector2(1, 1)), Color(COL_CORE, 1.0 - t * t))


# --- steam (#135) -------------------------------------------------------------

func _on_screen(c: Vector2i) -> bool:
	return c.x >= _view_c0.x and c.x <= _view_c1.x and c.y >= _view_c0.y and c.y <= _view_c1.y and _seen(c)


# `n` puffs of steam off the lava in cell `c` (`whole`: from anywhere in the
# cell, for lava that water just turned to rock).
func _puff(c: Vector2i, n: int, whole: bool = false) -> void:
	if _puffs.size() + n > PUFF_MAX:
		return
	var o := _cell_origin(c)
	var surface: float = TILE - max(2.0, round(_fill_of(c) * TILE))
	for i in n:
		var y: float = _puff_rng.randf_range(0.0, TILE) if whole else surface + 1.0
		_puffs.append([o.x + _puff_rng.randf_range(2.0, TILE - 2.0), o.y + y, _time - (0.0 if whole else _puff_rng.randf() * TICK), _puff_rng.randf_range(1.1, 2.0), _puff_rng.randf()])


# Each puff rises fast and slows, sways, swells and fades. It starts lit by
# the lava under it and pales to grey.
func _draw_puffs() -> void:
	for q in _puffs:
		var age: float = _time - q[2]
		var t: float = age / q[3]
		if t < 0.0 or t >= 1.0:
			continue
		var s: float = q[4]
		var x: float = round(q[0] + sin(age * 2.6 + s * TAU) * (1.0 + 3.0 * t) + (s - 0.5) * 8.0 * t)
		var y: float = round(q[1] - (20.0 + 12.0 * s) * (1.0 - (1.0 - t) * (1.0 - t)))
		var col := Color(COL_STEAM_LIT.lerp(COL_STEAM, minf(1.0, t * 2.5)), 0.42 * pow(1.0 - t, 1.3) * minf(1.0, age * 10.0))
		var r: float = 1.0 + floor(t * 2.6 + s * 0.9)
		# A soft round puff: stacked bars, so its middle is denser than its rim.
		draw_rect(Rect2(x - r, y - 1.0, r * 2.0, 2.0), col)
		if r > 1.0:
			draw_rect(Rect2(x - r + 1.0, y - r + 1.0, r * 2.0 - 2.0, r * 2.0 - 2.0), col)
			draw_rect(Rect2(x - 1.0, y - r, 2.0, r * 2.0), col)


# --- the boss chamber's energy barrier (#82) ------------------------------------
# Lava never enters the boss chamber. Where the crust over it is broken, a
# violet-blue membrane across the chamber's top edge shows what holds the lava
# back. It only stops lava; the keeper passes through. Violet-blue, so it reads
# apart from the bright purple unobtainium in the ocean above.
const COL_BARRIER_DEEP := Color("2e1f8f")
const COL_BARRIER_MID := Color("6b5cff")
const COL_BARRIER_LIGHT := Color("b8b0ff")
const COL_BARRIER_SPARK := Color("eeeaff")


# The chamber columns whose crust is gone (the barrier shows there).
func barrier_columns() -> Array:
	var out: Array = []
	if _chamber.size == Vector2i.ZERO:
		return out
	for x in range(_chamber.position.x, _chamber.end.x):
		if map.is_tile_empty(Vector2i(x, _chamber.position.y - 1)):
			out.append(x)
	return out


func _draw_barrier() -> void:
	for x in barrier_columns():
		var cell := Vector2i(x, _chamber.position.y)
		if not (_seen(cell) or _seen(cell + Vector2i.UP)):
			continue
		var o := _cell_origin(cell)
		var pulse: float = 0.75 + 0.25 * sin(_time * 3.2 + x * 0.6)
		# Haze above and below the membrane.
		draw_rect(Rect2(o + Vector2(0, -6), Vector2(TILE, 14)), Color(COL_BARRIER_MID, 0.16 * pulse))
		draw_rect(Rect2(o + Vector2(0, -4), Vector2(TILE, 10)), Color(COL_BARRIER_MID, 0.16 * pulse))
		# The membrane: a deep band with a bright core line.
		draw_rect(Rect2(o + Vector2(0, -3), Vector2(TILE, 6)), Color(COL_BARRIER_DEEP, 0.92))
		draw_rect(Rect2(o + Vector2(0, -2), Vector2(TILE, 3)), Color(COL_BARRIER_MID, pulse))
		# A light ripple running along it, and sparks drifting across.
		for px in range(0, int(TILE), 2):
			var w: float = sin(_time * 5.0 + (x * TILE + px) * 0.45)
			if w > 0.55:
				draw_rect(Rect2(o + Vector2(px, -1 + round(w)), Vector2(2, 1)), Color(COL_BARRIER_LIGHT, pulse))
		for i in 2:
			var sx: float = fposmod(_time * (9.0 + 5.0 * _noise(cell, i)) + _noise(cell, i + 7) * TILE, TILE)
			draw_rect(Rect2(o + Vector2(floor(sx), -1), Vector2(1, 1)), COL_BARRIER_SPARK)


func _draw_heat_bar() -> void:
	# Shown whenever there is heat, and while passive heat is building.
	if heat <= 0.5 and passive_rate <= 0.0:
		return
	var keeper = Keepers.first()
	if keeper == null or not is_instance_valid(keeper):
		return
	var p: Vector2 = to_local(keeper.global_position) + Vector2(-9, -20)
	p = p.round()
	draw_rect(Rect2(p - Vector2(1, 1), Vector2(20, 5)), Color(0, 0, 0, 0.8))
	var frac: float = heat / HEAT_MAX
	var col: Color = COL_CORE.lerp(Color("ff2a1a"), frac)
	if frac > 0.7 and fposmod(_time * 8.0, 1.0) < 0.5:
		col = Color.WHITE
	draw_rect(Rect2(p, Vector2(round(18.0 * frac), 3)), col)


func _draw_glow() -> void:
	# Soft additive light around lava and around magma rock the player can see.
	for c in _visible_cells():
		var f := _fill_of(c)
		if f <= 0.05 or not _seen(c):
			continue
		var center := _cell_origin(c) + Vector2(TILE, TILE) * 0.5
		var flick: float = 0.85 + 0.15 * sin(_time * 6.0 + c.x * 2.1 + c.y)
		var r: float = 30.0 + 18.0 * f
		_glow.draw_texture_rect(_glow_tex, Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1, 1, 1, 0.22 * flick * (0.4 + 0.6 * f)))
	for c in magma:
		if map.tiles.has(Vector2(c)):
			var center := _cell_origin(c) + Vector2(TILE, TILE) * 0.5
			var pulse: float = 0.5 + 0.5 * sin(_time * 3.0 + c.x * 1.7 + c.y * 0.9)
			_glow.draw_texture_rect(_glow_tex, Rect2(center - Vector2(22, 22), Vector2(44, 44)), false, Color(1, 1, 1, 0.10 + 0.14 * pulse))
	# The chamber barrier's violet glow.
	for x in barrier_columns():
		var cell := Vector2i(x, _chamber.position.y)
		if not (_seen(cell) or _seen(cell + Vector2i.UP)):
			continue
		var p := _cell_origin(cell) + Vector2(TILE * 0.5, 0)
		var pulse: float = 0.75 + 0.25 * sin(_time * 3.2 + x * 0.6)
		_glow.draw_texture_rect(_barrier_glow_tex, Rect2(p - Vector2(30, 24), Vector2(60, 48)), false, Color(1, 1, 1, 0.55 * pulse))


func stats() -> Dictionary:
	var total := 0.0
	for c in mass:
		total += mass[c]
	var pool_cells := 0
	for p in pools:
		pool_cells += p.size()
	return {"cells": mass.size(), "total": total, "magma": magma.size(), "sources": sources.size(),
		"heat": heat, "recalls": recalls, "breaches": breaches, "pools": pools.size(), "pool_cells": pool_cells,
		"pools_skipped": pools_skipped, "awake": _awake.size(), "ocean_cells": ocean_cells}
