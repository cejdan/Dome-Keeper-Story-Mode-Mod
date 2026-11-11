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
const COL_CORE := Color("ffd23e")
const COL_HOT := Color("ff8a1c")
const COL_BODY := Color("e8430e")
const COL_DEEP := Color("9c1d0a")
const COL_CRUST := Color("3a0d0a")

var map
var mass: Dictionary = {}          # Vector2i -> float, cells holding lava
var shown: Dictionary = {}         # Vector2i -> float, smoothed mass for drawing
var magma: Dictionary = {}         # Vector2i -> true, magma rock still solid
var sources: Dictionary = {}       # Vector2i -> float, lava a breached cell still holds
var melt_timers: Dictionary = {}   # Vector2i -> seconds of lava contact
var heat := 0.0
var recalls := 0
var breaches := 0
var recall_pos = null
var _acc := 0.0
var _time := 0.0
var _glow: Node2D
var _glow_tex: GradientTexture2D
# Dev only: the old rule (every cell cools), for timing comparisons.
var legacy_cooling := false
var pools: Array = []              # Array of Array[Vector2i]: open pools filled at run start
var pools_skipped := 0             # pools left empty because something opened their wall
# Sleeping: only cells in _awake run the flow math. A cell wakes when its mass or
# a neighbour's changes, or a tile next to it is destroyed.
var _awake: Dictionary = {}
var _wake_all := true
var _shown_settled := false
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
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	# A loaded run brings its lava back from the save; a new run places pockets.
	if not _restore(str(Data.ofOr(SAVE_KEY, ""))):
		_place_pockets()
		_fill_pools()
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
		for c in cells:
			var m: float = MAX_MASS + MAX_COMPRESS * float(c.y - top)
			mass[c] = m
			shown[c] = m
		pools.append(cells)
	wake_all()


func wake_all() -> void:
	_wake_all = true
	_shown_settled = false


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
		if c.y >= POCKET_MIN_DEPTH and map.tileData.get_hardnessv(c) < Data.HARDNESS_INDESTRUCTIBLE and not near_pool.has(c):
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


func _is_open(c: Vector2i) -> bool:
	return c.y >= MIN_Y and map.is_tile_empty(c)


# --- simulation ----------------------------------------------------------------

# Time spent in this node's _physics_process (dev timing).
var phys_us := 0
var phys_frames := 0


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
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
		_step()
	_melt(delta)
	_update_heat(delta)
	# Smooth the drawn lava toward the simulated lava; once it has caught up and
	# nothing is moving, skip the loop (a settled pool costs nothing).
	if not _shown_settled or not _awake.is_empty() or _wake_all:
		var gap := 0.0
		for c in mass:
			var v: float = lerp(shown.get(c, 0.0), mass[c], min(1.0, delta * 9.0))
			gap = maxf(gap, absf(v - mass[c]))
			shown[c] = v
		for c in shown.keys():
			if not mass.has(c):
				shown[c] = lerp(shown[c], 0.0, min(1.0, delta * 9.0))
				gap = maxf(gap, shown[c])
				if shown[c] < 0.01:
					shown.erase(c)
		_shown_settled = gap < 0.002 and _awake.is_empty()
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
	var next: Dictionary = mass.duplicate()
	for c in mass:
		if not all_awake and not _awake.has(c):
			continue
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
				next[c] -= flow
				next[below] = next.get(below, 0.0) + flow
				remaining -= flow
		if remaining <= 0.0:
			continue
		# Sideways: only once the lava rests on something, and not as a thin film.
		var resting: bool = not below_open or mass.get(below, 0.0) >= MAX_MASS * 0.9
		if resting and remaining > STICKY_MASS:
			for side in [Vector2i.LEFT, Vector2i.RIGHT]:
				var s: Vector2i = c + side
				if not _is_open(s):
					continue
				var flow: float = (m - mass.get(s, 0.0)) / SIDE_FLOW_DIVISOR
				flow = clamp(flow, 0.0, min(MAX_FLOW, remaining))
				if flow > MIN_FLOW:
					next[c] -= flow
					next[s] = next.get(s, 0.0) + flow
					remaining -= flow
		if remaining <= MAX_MASS:
			continue
		# Up: only lava squeezed past a full cell rises.
		var above: Vector2i = c + Vector2i.UP
		if _is_open(above):
			var flow: float = remaining - _stable_split(remaining + mass.get(above, 0.0))
			flow = clamp(flow * 0.6, 0.0, min(MAX_FLOW, remaining))
			if flow > MIN_FLOW:
				next[c] -= flow
				next[above] = next.get(above, 0.0) + flow

	var old: Dictionary = mass
	mass = {}
	var woke: Dictionary = {}
	for c in next:
		var m: float = next[c]
		# A sleeping cell's neighbours didn't change, so neither did its cooling.
		if (all_awake or _awake.has(c)) and (legacy_cooling or _cools(c, m, next)):
			m -= (FILM_COOL_PER_SECOND if m < FILM_MASS else COOL_PER_SECOND) * TICK
		# MIN_MASS only prunes numerical dust.
		if m > MIN_MASS:
			mass[c] = m
		if absf(m - old.get(c, 0.0)) > WAKE_EPS or (m <= MIN_MASS and old.has(c)):
			woke[c] = true
	_awake = {}
	for c in woke:
		_wake(c)


# Lava cools only at a thin, open surface (#41): nothing below it, and its top
# open to air (open space above with no lava, or the cell itself not full). So
# a brim-full pool under rock keeps its lava for good; a thinned-out layer with
# air above it cools away.
func _cools(c: Vector2i, m: float, cells: Dictionary) -> bool:
	if cells.get(c + Vector2i.DOWN, 0.0) >= LavaData.HOLDS_MASS:
		return false
	var above: Vector2i = c + Vector2i.UP
	if cells.get(above, 0.0) >= LavaData.HOLDS_MASS:
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
		"heat": heat, "breaches": breaches, "recalls": recalls}))
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
	ModLoaderLog.info("Lava restored from save: %d cells, %d magma" % [mass.size(), magma.size()], "cejdan-StoryMode")
	return true


func _melt(delta: float) -> void:
	# Lava resting against magma rock melts it, which releases that rock's lava too.
	if magma.is_empty() or mass.is_empty():
		return
	var touched := {}
	for c in mass:
		if mass[c] < 0.1:
			continue
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP]:
			if magma.has(c + d):
				touched[c + d] = true
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


# --- suit heat -----------------------------------------------------------------

func lava_at(world_pos: Vector2) -> float:
	return mass.get(map.getTileCoord(world_pos), 0.0)


func _update_heat(delta: float) -> void:
	var keeper = Keepers.first()
	if keeper == null or not is_instance_valid(keeper) or keeper.killed:
		return
	if recall_pos == null and Level.stage != null and Level.stage.keeperInputStarted:
		recall_pos = keeper.global_position
	if lava_at(keeper.global_position) >= BURN_MASS and not keeper.disabled:
		heat = min(HEAT_MAX, heat + HEAT_PER_SECOND * delta)
		if heat >= HEAT_MAX:
			_recall(keeper)
	elif keeper.isInsideDome:
		heat = max(0.0, heat - COOL_DOME_PER_SECOND * delta)
	else:
		heat = max(0.0, heat - COOL_MINE_PER_SECOND * delta)


func _recall(keeper) -> void:
	# Placeholder for "the keeper dies in the mine": the suit dumps its cargo where
	# it stands and yanks the keeper back to the dome.
	recalls += 1
	heat = 0.0
	for c in keeper.carriedCarryables.duplicate():
		if is_instance_valid(c):
			keeper.dropCarry(c)
	InputSystem.shake(10.0, 0.4, 24.0)
	if recall_pos != null:
		keeper.teleport(recall_pos)


# --- drawing -------------------------------------------------------------------

func _cell_origin(c: Vector2i) -> Vector2:
	# Top-left corner of a tile, in this node's space (same space as the Map node).
	return to_local(map.getTilePos(Vector2(c))) - Vector2(TILE, TILE) * 0.5


func _noise(c: Vector2i, i: int) -> float:
	return fposmod(sin(float(c.x * 127 + c.y * 311 + i * 74)) * 43758.5453, 1.0)


# Lava in a cell the player hasn't revealed yet (an unopened pool) stays hidden.
func _seen(c: Vector2i) -> bool:
	return map.visibleTileCoords.has(Vector2(c)) or map.visibleTileCoords.has(c)


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

	for c in shown:
		var f := _fill_of(c)
		if f <= 0.02 or not _seen(c):
			continue
		var o := _cell_origin(c)
		var above_has: bool = shown.get(c + Vector2i.UP, 0.0) > 0.05
		var below: Vector2i = c + Vector2i.DOWN
		var falling: bool = _is_open(below) and shown.get(below, 0.0) < 0.95
		if falling and not above_has and f < 0.9:
			# A pouring stream: a column that wobbles, thicker with more lava.
			var w: float = clamp(round(6.0 + f * 16.0), 4.0, TILE)
			var wob: float = round(sin(_time * 5.0 + c.y * 1.3) * 1.5)
			var x: float = round((TILE - w) * 0.5) + wob
			draw_rect(Rect2(o + Vector2(x, 0), Vector2(w, TILE)), COL_BODY)
			draw_rect(Rect2(o + Vector2(x + 1, 0), Vector2(max(1.0, w - 2), TILE)), COL_HOT)
			if w > 6:
				draw_rect(Rect2(o + Vector2(x + round(w * 0.5) - 1, 0), Vector2(2, TILE)), COL_CORE)
			continue
		var h: float = TILE if (above_has or f >= 0.98) else max(2.0, round(f * TILE))
		var top: float = TILE - h
		draw_rect(Rect2(o + Vector2(0, top), Vector2(TILE, h)), COL_BODY)
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
				draw_rect(Rect2(o + Vector2(x, top + max(0.0, ripple)), Vector2(2, 2)), COL_CORE)
			draw_rect(Rect2(o + Vector2(0, top + 2), Vector2(TILE, 1)), COL_HOT)
			# Embers that pop off the surface.
			for i in 2:
				var t: float = fposmod(_time * (0.5 + _noise(c, i + 40)) + _noise(c, i + 50), 1.0)
				var ex: float = floor(_noise(c, i + 60 + int(_time * 0.5)) * (TILE - 1.0))
				draw_rect(Rect2(o + Vector2(ex, top - t * 14.0), Vector2(1, 1)), Color(COL_CORE, 1.0 - t))

	_draw_heat_bar()


func _draw_heat_bar() -> void:
	if heat <= 0.5:
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
	for c in shown:
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


func stats() -> Dictionary:
	var total := 0.0
	for c in mass:
		total += mass[c]
	var pool_cells := 0
	for p in pools:
		pool_cells += p.size()
	return {"cells": mass.size(), "total": total, "magma": magma.size(), "sources": sources.size(),
		"heat": heat, "recalls": recalls, "breaches": breaches, "pools": pools.size(), "pool_cells": pool_cells,
		"pools_skipped": pools_skipped, "awake": _awake.size()}
