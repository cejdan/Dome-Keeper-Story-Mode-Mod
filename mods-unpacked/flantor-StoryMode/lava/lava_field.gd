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

const LavaData = preload("res://mods-unpacked/flantor-StoryMode/data/lava.gd")
static var _LavaData = LavaData  # calls go through this: lazy_preload makes const-preload calls slow
const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const StoryNet = preload("res://mods-unpacked/flantor-StoryMode/net/story_net.gd")
static var _StoryNet = StoryNet  # calls go through this: lazy_preload makes const-preload calls slow
const FieldUtil = preload("res://mods-unpacked/flantor-StoryMode/util/field_util.gd")
static var _FieldUtil = FieldUtil  # calls go through this: lazy_preload makes const-preload calls slow
const DropNet = preload("res://mods-unpacked/flantor-StoryMode/util/drop_net.gd")
static var _DropNet = DropNet  # calls go through this: lazy_preload makes const-preload calls slow
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
const HOLDS_MASS := LavaData.HOLDS_MASS
const OVERHEAT_AFTER: float = preload("res://mods-unpacked/flantor-StoryMode/data/boss.gd").OVERHEAT_HEAT_AFTER

const TILE := 24.0
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
# Suit heat, per local keeper (#231): playerId -> heat. Each instance keeps its
# own keepers' (one in single player and online, one per device in
# splitscreen). `heat` is the first local keeper's, as before.
var heats: Dictionary = {}
var heat: float:
	get:
		return heats.get(_Story.local_pid(), 0.0)
	set(v):
		heats[_Story.local_pid()] = v
var recalls := 0
var gas_recalls := 0              # how many of the recalls were gas deaths (#357)
var last_penalty := 0
var hardened := 0                 # lava cells water turned to rock this run
var tiles_rev := 0                # goes up whenever lava turns a cell to rock (the gas look's open cells, #347)
var last_hardened: Array = []     # the cells of the latest hardening
var _steam: Array = []            # [cell, seconds left] for the steam flash
var _puffs: Array = []            # steam puffs: [x, y, time born, seconds to live, 0..1 seed], this node's space
var _puff_rng := RandomNumberGenerator.new()
var _anchors: Dictionary = {}     # stream cell -> the side its lava comes from: -1 left, 1 right, 0 neither
var _stream_memo: Dictionary = {}  # stream cell -> _stream_params(), for one physics frame
var _housekeep := 0
var _view_c0 := Vector2i.ZERO      # the cells on screen at the last draw (steam only rises there)
var _view_c1 := Vector2i.ZERO
var _view_boxes: Array = []      # [c0, c1] per split view at the last draw (#231)
var breaches := 0
# Where each local keeper's recall sends it: where it stood when the run's
# input started (playerId -> Vector2). `recall_pos` is the first keeper's.
var recall_spots: Dictionary = {}
var recall_pos:
	get:
		return recall_spots.get(_Story.local_pid(), null)
	set(v):
		if v == null:
			recall_spots.erase(_Story.local_pid())
		else:
			recall_spots[_Story.local_pid()] = v
var _acc := 0.0
var _time := 0.0
var _glow: Node2D
# The ocean's plain cells are drawn by one shader rect (#347; _setup_ocean_body()).
var _ob: Node2D = null
var _ob_mat: ShaderMaterial
var _og: Node2D = null              # ... and their glow (ocean_glow.gdshader)
var _og_mat: ShaderMaterial
var _ob_rect := Rect2i()           # the ocean's cells (its rows and columns)
var _ob_mask := PackedByteArray()  # per cell 255: the shader draws it
var _ob_mask_img: Image
var _ob_mask_tex: ImageTexture
var _ob_stamp := PackedInt32Array()  # per cell: the draw that last found it plain
var _ob_draw := 0
var _ob_origin = null              # the rect's top-left in this node's space, once known
# Dev only: draw the ocean's plain cells on the CPU as before (timing comparisons).
var no_ocean_shader := false
var _glow_tex: GradientTexture2D
var _barrier_glow_tex: GradientTexture2D
# Dev only: the old rule (every cell cools), for timing comparisons.
var legacy_cooling := false
# Dev only: hold the lava still (no flow or cooling) so a playtest can stand next to a fixed shape.
var freeze_flow := false
# Dev only: outline the keeper's lava-contact box.
var debug_boxes := false
# Dev only (#231): cull to the first split view only, as before #231 (lava
# popped in late on player 2's view); t231_split_lava -Extra "--oldcull".
var single_view_cull := false
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

# Online multiplayer (#227): the host alone moves the lava (flow, melting, water
# hardening) and sends clients the cells that changed, NET_EVERY seconds, as
# absolute masses; a client draws what it is sent. Suit heat stays with each
# player's own instance (their keeper); a death's penalty and beat are the host's.
const NET_EVERY := 0.1
const NET_EPS := 0.001
var net_client := false            # this instance draws the host's lava
var _net_dirty: Dictionary = {}    # host: cells whose mass may have changed since the last send
var _net_sent: Dictionary = {}     # host: the mass clients last got per cell
var _net_resync := false           # host: no clients lately; _net_sent is rebuilt when one comes
var _net_t := 0.0


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
	net_client = Network.is_client()
	# A loaded run brings its lava back from the save; a new run places pockets.
	if not _restore(str(Data.ofOr(SAVE_KEY, ""))):
		_place_pockets()
		_fill_pools()
		_fill_ocean()
	map.tile_destroyed.connect(_on_tile_destroyed)
	add_to_group("saveable")
	_setup_ocean_body()
	if net_client:
		_StoryNet.lava_full_request()
	else:
		_net_sent = mass.duplicate()


# --- the ocean's plain cells (#347) ----------------------------------------------
# A screen of ocean is a few hundred cells, each four crust plates and a share
# of a body rect: thousands of draw calls a redraw, a few ms of the frame. The
# cells that are full, bright and not falling ("plain") are drawn instead by
# one rect over the ocean with lava/ocean_body.gdshader, from each cell's
# crust noise worked out here once; _draw_body() marks which cells those are
# every redraw (the mask). The shader draws them as _draw_body() would, under
# the rest of the field's drawing (surface ripples, streams, puffs...), which
# draws into a plain cell only what it drew over it before.

const OCEAN_BODY_SHADER := "res://mods-unpacked/flantor-StoryMode/lava/ocean_body.gdshader"
const OCEAN_GLOW_SHADER := "res://mods-unpacked/flantor-StoryMode/lava/ocean_glow.gdshader"


func _setup_ocean_body() -> void:
	if _ocean.is_empty() or DisplayServer.get_name() == "headless":
		return
	var x0: int = int(_ocean["x0"])
	var top: int = int(_ocean["top"])
	_ob_rect = Rect2i(x0, top, int(_ocean["x1"]) - x0 + 1, int(_ocean["bottom"]) - top + 1)
	var w: int = _ob_rect.size.x
	var n: int = w * _ob_rect.size.y
	var xs := PackedFloat32Array()
	var vs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	xs.resize(n * 4)
	vs.resize(n * 4)
	ys.resize(n * 4)
	for i in n:
		var c := _ob_rect.position + Vector2i(i % w, i / w)
		for k in 4:
			xs[i * 4 + k] = _noise(c, k) * TILE
			vs[i * 4 + k] = 2.0 + 3.0 * _noise(c, k + 5)
			ys[i * 4 + k] = 3.0 + floorf(_noise(c, k + 11) * (TILE - 6.0))
	_ob_mask.resize(n)
	_ob_mask.fill(0)
	_ob_stamp.resize(n)
	_ob_stamp.fill(-1)
	_ob_mask_img = Image.create_from_data(w, _ob_rect.size.y, false, Image.FORMAT_R8, _ob_mask)
	_ob_mask_tex = ImageTexture.create_from_image(_ob_mask_img)
	_ob_mat = ShaderMaterial.new()
	_ob_mat.shader = load(OCEAN_BODY_SHADER)
	_ob_mat.set_shader_parameter("mask", _ob_mask_tex)
	for e in [["plate_x", xs], ["plate_v", vs], ["plate_y", ys]]:
		var img := Image.create_from_data(w, _ob_rect.size.y, false, Image.FORMAT_RGBAF, e[1].to_byte_array())
		_ob_mat.set_shader_parameter(e[0], ImageTexture.create_from_image(img))
	_ob_mat.set_shader_parameter("tile", TILE)
	_ob_mat.set_shader_parameter("col_body", COL_BODY)
	_ob_mat.set_shader_parameter("col_deep", COL_DEEP)
	_ob_mat.set_shader_parameter("col_hot", COL_HOT)
	_ob_mat.set_shader_parameter("col_crust", COL_CRUST)
	_ob = Node2D.new()
	_ob.name = "LavaOceanBody"
	_ob.material = _ob_mat
	_ob.show_behind_parent = true      # under everything this node draws
	_ob.draw.connect(_draw_ocean_rect)
	add_child(_ob)
	# Their glow: additive, over the lava like the glow pass, reaching two
	# cells past the ocean's edge.
	_og_mat = ShaderMaterial.new()
	_og_mat.shader = load(OCEAN_GLOW_SHADER)
	_og_mat.set_shader_parameter("mask", _ob_mask_tex)
	_og_mat.set_shader_parameter("glow_tex", _glow_tex)
	_og_mat.set_shader_parameter("tile", TILE)
	_og_mat.set_shader_parameter("first_cell", Vector2(_ob_rect.position))
	_og = Node2D.new()
	_og.name = "LavaOceanGlow"
	_og.material = _og_mat
	_og.z_index = _glow.z_index
	_og.draw.connect(_draw_ocean_glow_rect)
	add_child(_og)


func _draw_ocean_rect() -> void:
	if _ob_origin != null:
		_ob.draw_rect(Rect2(_ob_origin, Vector2(_ob_rect.size) * TILE), Color.WHITE)


func _draw_ocean_glow_rect() -> void:
	if _ob_origin != null:
		_og.draw_rect(Rect2(_ob_origin - Vector2(2, 2) * TILE, Vector2(_ob_rect.size + Vector2i(4, 4)) * TILE), Color.WHITE)


# After the cells are sorted: the mask over every view box says which cells
# this redraw handed to the shader (outside the boxes nothing is on screen).
func _ob_update(b0: Vector2) -> void:
	var o: Vector2 = b0 + Vector2(_ob_rect.position) * TILE
	if _ob_origin != o:
		_ob_origin = o
		_ob_mat.set_shader_parameter("origin", o)
		_og_mat.set_shader_parameter("origin", o)
		_ob.queue_redraw()
		_og.queue_redraw()
	_ob_mat.set_shader_parameter("time", _time)
	_og_mat.set_shader_parameter("time", _time)
	var w: int = _ob_rect.size.x
	var r0: Vector2i = _ob_rect.position
	var r1: Vector2i = _ob_rect.end - Vector2i.ONE
	var dirty := false
	for bx in _view_boxes:
		for y in range(maxi(bx[0].y, r0.y), mini(bx[1].y, r1.y) + 1):
			var row: int = (y - r0.y) * w - r0.x
			for x in range(maxi(bx[0].x, r0.x), mini(bx[1].x, r1.x) + 1):
				var want: int = 255 if _ob_stamp[row + x] == _ob_draw else 0
				if _ob_mask[row + x] != want:
					_ob_mask[row + x] = want
					dirty = true
	if dirty:
		_ob_mask_img.set_data(w, _ob_rect.size.y, false, Image.FORMAT_R8, _ob_mask)
		_ob_mask_tex.update(_ob_mask_img)


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
var boss_chamber_reached := false   # saved by older runs; the lair seal (#366) decides now
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
	if not net_client:
		_net_dirty[c] = true
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
	_open_cache.erase(c)
	_tile_events += 1
	_wake(c)
	# Under the flood line (#369): the new cell is lava at once (in the band,
	# a real cell; below it, implied). A magma cell there adds nothing.
	if fl_on and c.y >= _fl_top and c.y < fl_r1:
		_fl_dug(c)
		if magma.has(c):
			magma.erase(c)
			melt_timers.erase(c)
			breaches += 1
			InputSystem.shake(6.0, 0.5, 20.0, world_pos)
		return
	if not magma.has(c):
		return
	magma.erase(c)
	melt_timers.erase(c)
	sources[c] = sources.get(c, 0.0) + VOLUME_PER_MAGMA_CELL
	breaches += 1
	InputSystem.shake(6.0, 0.5, 20.0, world_pos)


# The boss chamber counts as closed for lava, so drilling into it from the
# ocean doesn't flood the arena; the lava rests on its ceiling (#43).
#
# Under the flood line's band (#369) every open cell is lava by the level
# alone (implied, not stored): the flow sees those rows as closed, so the
# band rests on them and nothing pours down into them.
func _is_open(c: Vector2i) -> bool:
	if c.y >= fl_r0 and c.y < fl_r1:
		return false
	var v = _open_cache.get(c)
	if v == null:
		v = c.y >= MIN_Y and map.is_tile_empty(c) and not _chamber.has_point(c)
		_open_cache[c] = v
	return v


# _is_open() without the flood line: is the cell dug out (or a cave)?
func _raw_open(c: Vector2i) -> bool:
	var v = _open_cache.get(c)
	if v == null:
		v = c.y >= MIN_Y and map.is_tile_empty(c) and not _chamber.has_point(c)
		_open_cache[c] = v
	return v


# _is_open() per cell, remembered (#347: the map's check is two calls into its
# tile layers, and the flow and the drawing ask several times a cell a step).
# A cell is forgotten when its tile breaks or lava hardens there, and all of
# them every OPEN_CACHE_SECONDS, in case something else changes a tile.
const OPEN_CACHE_SECONDS := 4.0
var _open_cache: Dictionary = {}
var _open_cache_t := 0.0


# --- simulation ----------------------------------------------------------------

# Time spent in this node's _physics_process (dev timing).
var phys_us := 0
var phys_frames := 0
# Time spent in this node's draw callbacks, lava and glow (dev timing, #347).
var draw_us := 0
var glow_us := 0


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
	_open_cache_t += delta
	if _open_cache_t >= OPEN_CACHE_SECONDS:
		_open_cache_t = 0.0
		_open_cache.clear()
	if not net_client:
		_acc += delta
		while _acc >= TICK:
			_acc -= TICK
			if not freeze_flow:
				_step()
		_melt(delta)
		_check_water()
		_net_send(delta)
	if fl_on:
		_fl_tick(delta)
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
	for c: Vector2i in _shown_dirty.keys():
		if not _view_dirty and _near_view(c):
			_view_dirty = true
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
	var band: Dictionary = _fl_band
	for c in work:
		var m: float = mass[c]
		if m <= 0.0:
			continue
		# The flood line's band (#369) is held at its level: it takes in what
		# pours onto it and gives nothing back.
		if fl_on and band.has(c):
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
		if fl_on and band.has(c):
			continue
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
	if fl_on:
		_fl_full_hold = true


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
	_StoryNet.save_blob(SAVE_KEY, JSON.stringify({"seed": Level.levelSeed, "mass": cells, "sources": src, "magma": rock,
		"heat": heat, "heats": heats, "breaches": breaches, "recalls": recalls, "gas_recalls": gas_recalls, "ocean_cells": ocean_cells, "boss_chamber_reached": boss_chamber_reached}))
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
	heats = _FieldUtil.per_player(d, "heats", "heat")
	breaches = int(d.get("breaches", 0))
	recalls = int(d.get("recalls", 0))
	gas_recalls = int(d.get("gas_recalls", 0))
	ocean_cells = int(d.get("ocean_cells", 0))
	boss_chamber_reached = bool(d.get("boss_chamber_reached", false))
	ModLoaderLog.info("Lava restored from save: %d cells, %d magma" % [mass.size(), magma.size()], "flantor-StoryMode")
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
				_StoryNet.tile_break(map, c)
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
		var touched: Vector2i = lava_touched(Rect2(d.global_position - Vector2(2, 2), Vector2(4, 4)))
		if touched == NO_CELL:
			continue
		# The lava it touches can be drawn in the next cell (beside it, a pool's
		# top just under it, a stream pouring past): harden from there (#296).
		var c: Vector2i = map.getTileCoord(d.global_position)
		var cells := _harden_from(c if mass.get(c, 0.0) >= BURN_MASS else touched, LavaData.WATER_HARDENS_CELLS)
		_DropNet.consume(d)   # gone on the clients too (#315)
		InputSystem.shake(6.0, 0.35, 20.0, d.global_position)
		ModLoaderLog.info("Water hardened %d lava cells" % cells.size(), "flantor-StoryMode")


# Breadth-first from `start` through connected lava (>= BURN_MASS), nearest
# first, up to `limit` cells; each becomes plain rock. Returns the cells.
# Lava under or beside a keeper's body stays lava, or the keeper would be
# sealed inside the rock (#348): the fill passes through those cells and
# hardens the next ones instead.
func _harden_from(start: Vector2i, limit: int) -> Array:
	var out: Array = []
	var kept := _keeper_cells()
	var seen := {start: true}
	var open: Array = [start]
	while not open.is_empty() and out.size() < limit:
		var c: Vector2i = open.pop_front()
		if mass.get(c, 0.0) < BURN_MASS:
			continue
		if not kept.has(c):
			out.append(c)
		for d in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			var n: Vector2i = c + d
			if not seen.has(n):
				seen[n] = true
				open.append(n)
	for c in out:
		_harden(c)
	if not out.is_empty():
		_StoryNet.lava_harden(PackedVector2Array(out.map(func(c): return Vector2(c))))
	last_hardened = out
	hardened += out.size()
	return out


# Cells overlapping any keeper's body, with a small margin: every keeper the
# host has (local, splitscreen and online clients' keepers, whose positions
# arrive a little late), so none is left inside a tile it can't leave (#348).
const KEEPER_CLEAR_MARGIN := 3.0


func _keeper_cells() -> Dictionary:
	var out := {}
	for k in Keepers.all.getAll():
		if k == null or not is_instance_valid(k) or not k.is_inside_tree():
			continue
		var r: Rect2 = _FieldUtil.keeper_rect(k).grow(KEEPER_CLEAR_MARGIN)
		var a: Vector2i = map.getTileCoord(r.position)
		var b: Vector2i = map.getTileCoord(r.end)
		for x in range(a.x, b.x + 1):
			for y in range(a.y, b.y + 1):
				out[Vector2i(x, y)] = true
	return out


# One lava cell becomes an ordinary rock tile: no resource, drillable, the cell's
# own hardness (or medium in a dug cell that had none).
func _harden(c: Vector2i) -> void:
	_open_cache.erase(c)
	_view_dirty = true
	tiles_rev += 1
	_tile_events += 1
	mass.erase(c)
	shown.erase(c)
	_fl_band_remove(c)   # rock now: the flood line passes it by (#369)
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


# Passive heat per second right now (after Heat Shielding), per local keeper
# (#231); `passive_rate` is the first keeper's.
var passive_rates: Dictionary = {}
var passive_rate: float:
	get:
		return passive_rates.get(_Story.local_pid(), 0.0)


func heat_of(keeper) -> float:
	return heats.get(keeper.playerId, 0.0)


func set_heat_of(keeper, v: float) -> void:
	heats[keeper.playerId] = v


func passive_rate_of(keeper) -> float:
	return passive_rates.get(keeper.playerId, 0.0)


# Passive heat per second at a tile for `who`'s suit (#187): by biome, the
# lava ocean counting as B8. `who`: a keeper or playerId (#265), null for the
# first local keeper.
func passive_rate_at(tile: Vector2i, who = null) -> float:
	var b: int = map.tileData.get_biomev(tile)
	if not _ocean.is_empty() and tile.y > int(_ocean["ceiling"]):
		b = LavaData.PASSIVE_HEAT_LAST_BIOME
	return _LavaData.passive_rate(b, who)


func _update_heat(delta: float) -> void:
	# Every keeper this instance plays heats on its own (#231).
	for keeper in _Story.local_keepers():
		_update_keeper_heat(keeper, delta)


func _update_keeper_heat(keeper, delta: float) -> void:
	if keeper.killed:
		return
	var pid: String = keeper.playerId
	if not recall_spots.has(pid) and Level.stage is LevelStage and Level.stage.keeperInputStarted:
		recall_spots[pid] = keeper.global_position
	# Passive heat from depth (#46), out of the dome, scaled by Heat Shielding.
	var rate := 0.0
	# The boss sequence keeps the depth's heat out (#160; #187: the chase and
	# finale play as they did when only Heat Shielding IV reached them).
	var BossDirector = load("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
	var sealed: bool = BossDirector.current() == "fight" or BossDirector.jams_recall()
	if not keeper.isInsideDome and not keeper.disabled and not sealed:
		rate = passive_rate_at(map.getTileCoord(keeper.global_position), keeper)
	passive_rates[pid] = rate
	var h: float = heats.get(pid, 0.0)
	if keeper_in_lava(keeper) and not keeper.disabled:
		# Heat Shielding (#44) slows lava heat but never stops it; deep enough,
		# the depth itself is hotter than the lava (#187).
		h = min(HEAT_MAX, h + maxf(HEAT_PER_SECOND * _LavaData.lava_heat_mult(keeper), rate) * delta)
	elif keeper.isInsideDome:
		h = max(0.0, h - COOL_DOME_PER_SECOND * delta)
	elif rate > 0.0:
		# Deep and out of lava: heat only rises.
		h = min(HEAT_MAX, h + rate * delta)
	else:
		h = max(0.0, h - COOL_MINE_PER_SECOND * delta)
	heats[pid] = h
	if h >= HEAT_MAX and overheat(keeper):
		heats[pid] = HEAT_MAX * OVERHEAT_AFTER
	# Entering the boss chamber is the lair seal's to see now (#366,
	# endgame/lair_seal.gd): through the opened seal, it wakes the horror.


# A full heat or toxin bar: a recall, the suit's death. Velle jams the recall
# through the boss sequence (#160): there it costs a heart instead, and this
# returns true (the bar drops to OVERHEAT_AFTER of full). `teleport` false: a
# death where the keeper stands (gassed in the dome, #213). `cause` "gas" plays
# the gas death beat instead of the lava one (#357).
func overheat(keeper, teleport: bool = true, cause: String = "lava") -> bool:
	var BossDirector = load("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
	if BossDirector.jams_recall():
		BossDirector.overheated(keeper)
		return true
	# After the last chain, until a keeper enters the lair (#369): no recall to
	# the dome (it would be a free ride to the ship). The run is lost.
	var RisingLava = load("res://mods-unpacked/flantor-StoryMode/endgame/rising_lava.gd")
	if RisingLava.ends_run():
		heats[keeper.playerId] = HEAT_MAX
		RisingLava.lost_in_lava(keeper, cause)
		return true
	_recall(keeper, teleport, cause)
	return false


func _recall(keeper, teleport: bool = true, cause: String = "lava") -> void:
	# Placeholder for "the keeper dies in the mine": the suit dumps its cargo where
	# it stands and yanks the keeper back to the dome. This runs on the keeper's
	# own instance (#227); the team's side (team_death) on the host.
	heats[keeper.playerId] = 0.0
	for c in keeper.carriedCarryables.duplicate():
		if is_instance_valid(c):
			keeper.dropCarry(c)
	InputSystem.shake(10.0, 0.4, 24.0)
	var spot = recall_spots.get(keeper.playerId, null)
	if teleport and spot != null:
		keeper.teleport(spot)
	if net_client:
		# The money is the host's to take; the loss shows here right away.
		if _Story.is_story():
			var loss: int = int(floor(int(Data.ofOr(keeper.teamId + ".inventory.money", 0)) / 2.0))
			if loss > 0:
				_float_loss(keeper, loss)
		_StoryNet.lava_died(keeper.playerId, cause)
		return
	team_death(keeper, cause)


# The team's side of a lava or gas death, on the host: the count, the beat
# and the money penalty. `keeper` died on its own instance (maybe a client's).
func team_death(keeper, cause: String = "lava") -> void:
	recalls += 1
	if cause == "gas":
		gas_recalls += 1
	# The horror is tender about it (#26): its own beat for each of the first
	# five deaths in a run (#157); the 5th plays again on every death after.
	# Lava and gas deaths count apart, each with its own beats (#357).
	if _Story.is_story():
		var n: int = gas_recalls if cause == "gas" else recalls - gas_recalls
		load("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd").trigger("%s_death:%d" % [cause, mini(n, 5)])
	# Dying in the deep costs half the money (#45). With $0 or $1 it stays free.
	last_penalty = 0
	if _Story.is_story():
		var key: String = keeper.teamId + ".inventory.money"
		var loss: int = int(floor(int(Data.ofOr(key, 0)) / 2.0))
		if loss > 0:
			Data.changeByInt(key, -loss)
			last_penalty = loss
			if keeper.peerId == multiplayer.get_unique_id():
				_float_loss(keeper, loss)
		ModLoaderLog.info("Overheat recall (%s): lost $%d" % [keeper.playerId, loss], "flantor-StoryMode")


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


# --- online multiplayer (#227) -----------------------------------------------------

# Host: the cells whose mass moved by more than NET_EPS since clients last got
# them, every NET_EVERY seconds.
func _net_send(delta: float) -> void:
	_net_t += delta
	if _net_t < NET_EVERY:
		return
	_net_t = 0.0
	if Network.is_offline_mode() or Network.clients.is_empty():
		_net_dirty.clear()
		_net_resync = true
		return
	if _net_resync:
		# A client has just come: it asks for all the lava (net_full) once its field is built.
		_net_resync = false
		_net_sent = mass.duplicate()
		_net_dirty.clear()
		return
	var buf := StreamPeerBuffer.new()
	var n := 0
	for c: Vector2i in _net_dirty:
		# Under the flood line clients fill their own band from the level (#369).
		if fl_on and c.y >= _fl_top and c.y < fl_r1:
			continue
		var m: float = mass.get(c, 0.0)
		if m > 0.0 and absf(m - _net_sent.get(c, 0.0)) <= NET_EPS:
			continue
		if m <= 0.0 and not _net_sent.has(c):
			continue
		buf.put_16(c.x)
		buf.put_16(c.y)
		buf.put_float(m)
		n += 1
		if m > 0.0:
			_net_sent[c] = m
		else:
			_net_sent.erase(c)
	_net_dirty.clear()
	if n > 0:
		_StoryNet.lava_cells(buf.data_array)


# Host: every lava cell, for a client whose field was just built.
func net_full() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	for c: Vector2i in mass:
		buf.put_16(c.x)
		buf.put_16(c.y)
		buf.put_float(mass[c])
	return buf.data_array


# Client: cells from the host. `full` replaces all the lava.
func net_apply(data: PackedByteArray, full: bool) -> void:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	if full:
		for c in mass:
			_shown_dirty[c] = true
		mass.clear()
	while buf.get_position() + 8 <= data.size():
		var c := Vector2i(buf.get_16(), buf.get_16())
		var m: float = buf.get_float()
		# Under the flood line this instance holds its own band (#369).
		if fl_on and c.y >= _fl_top and c.y < fl_r1:
			continue
		var o: float = mass.get(c, 0.0)
		if m > MIN_MASS:
			mass[c] = m
		else:
			mass.erase(c)
		_shown_dirty[c] = true
		# Steam off lava that cooled, as the host's _step puffs it (its odds are
		# per TICK; a send covers NET_EVERY).
		if not full and m < o and _on_screen(c) and _cools(c, m, mass):
			if m <= MIN_MASS:
				_puff(c, 3)
			elif _puff_rng.randf() < (0.3 if m < FILM_MASS else 0.035) * NET_EVERY / TICK:
				_puff(c, 1)
	if full and fl_on:
		_fl_full_hold = true


# Client: lava the host hardened into rock with water.
func net_harden(cells: PackedVector2Array) -> void:
	for v in cells:
		_harden(Vector2i(v))


# --- the flood line (#369) ----------------------------------------------------------
# After the last chain the lava rises from the ocean up through the mine
# (endgame/rising_lava.gd moves the level; it is one number, `fl_row`: the
# lava's surface in tile rows, smaller is higher). This field turns it into
# lava:
#   the band   the dug cells in the BAND_ROWS rows at the top of the flood are
#              real cells here: the top row as full as the level is into it,
#              the rest full. They burn, steam, light gas and melt magma like
#              any lava, and lava pouring onto them joins them; they never flow
#              or cool (the level holds them). Lava already in a band row's
#              cells when the line gets there is simply held at the level.
#   implied    every open cell below the band, down to the ocean's top row (the
#              ocean keeps its own cells), is lava by the level alone: not
#              stored, never simulated. The flow sees those rows as closed
#              (_is_open), a keeper in them is in lava (keeper_in_lava), and one
#              shader rect draws them (lava/flood_body.gdshader, with its glow
#              lava/flood_glow.gdshader) from a mask of the open cells the player
#              has seen. Nothing off screen costs anything to draw.
# Rock stays rock: only open cells fill. A cell dug under the line fills at
# once. So the cost is one thin strip of lava however deep the flood is.
# Online every peer runs this from its own copy of the level (the host sends
# it); the band and the implied rows never go over the lava stream.

const FloodData = preload("res://mods-unpacked/flantor-StoryMode/data/rising_lava.gd")
const FLOOD_BODY_SHADER := "res://mods-unpacked/flantor-StoryMode/lava/flood_body.gdshader"
const FLOOD_GLOW_SHADER := "res://mods-unpacked/flantor-StoryMode/lava/flood_glow.gdshader"
const FLOOD_RESCAN_S := 0.4

var fl_on := false                 # the flood line is in the mine (rising or held)
var fl_row: float = INF            # the lava's surface, in tile rows
var fl_r0 := 0                     # implied rows: fl_r0 ..
var fl_r1 := 0                     # .. fl_r1 (exclusive: the ocean's top row)
var _fl_top := 0                   # the band's top row (floor(fl_row)); band rows _fl_top .. fl_r0
var _fl_y0 := 0.0                  # world y of row fl_r0's top edge ...
var _fl_y1 := 0.0                  # ... and of fl_r1's
var _fl_band: Dictionary = {}      # band cell -> true
var _fl_rows: Dictionary = {}      # band row -> Array of its cells
var _fl_full_hold := false         # the whole band needs holding (after a flow step, a load ...)
var _fl_x0 := 0                    # the map's columns x0 ..
var _fl_x1 := 0                    # .. x1 (exclusive)
var _fl_my0 := 0                   # the mask's first row
var _fl_mask := PackedByteArray()  # per cell 255: implied lava the shader draws
var _fl_img: Image
var _fl_tex: ImageTexture
var _fl_mask_dirty := false
var _fl_scan_t := 0.0
var _fl_seen_n := -1
var _fb: Node2D = null             # the implied lava (flood_body.gdshader)
var _fb_mat: ShaderMaterial
var _fg: Node2D = null             # ... and its glow
var _fg_mat: ShaderMaterial
var _fl_origin := Vector2.INF      # the mask's cell (x0, my0) top-left, in this node's space
var fl_cells_implied := 0          # open cells under the band, for logs (counted at each move)


# The flood line's level (rows): the first call puts it in the mine, later
# ones move it up. It never moves down (a call below it is ignored).
func flood_set(row: float) -> void:
	if _ocean.is_empty() or map == null:
		return
	var end: int = int(_ocean["top"])
	row = clampf(row, float(FloodData.SURFACE_ROW), float(end))
	if not fl_on:
		_fl_start(row)
		return
	if row >= fl_row:
		return
	fl_row = row
	var top: int = int(floor(row))
	if top < _fl_top:
		_fl_move(top)


func flood_active() -> bool:
	return fl_on


# The world y of the lava's surface, or INF with no flood.
func flood_y() -> float:
	if not fl_on:
		return INF
	return map.getTilePos(Vector2(0, 0)).y - TILE * 0.5 + fl_row * TILE


# Is cell `c` lava by the flood line (in the band or under it)?
func flooded(c: Vector2i) -> bool:
	if not fl_on or c.y < _fl_top or c.y >= fl_r1:
		return false
	if c.y >= fl_r0:
		return _raw_open(c)
	return _fl_band.has(c) and (c.y > _fl_top or float(c.y + 1) - fl_row > MIN_MASS)


func _fl_start(row: float) -> void:
	fl_on = true
	fl_row = row
	var end: int = int(_ocean["top"])
	var used: Rect2i = map.tileData.get_used_rect()
	_fl_x0 = used.position.x
	_fl_x1 = used.end.x
	_fl_my0 = mini(used.position.y, FloodData.SURFACE_ROW)
	_fl_top = int(floor(row))
	fl_r1 = end
	fl_r0 = mini(_fl_top + FloodData.BAND_ROWS, end)
	# Lava stored under the band (pockets' lava, pools, streams) is the
	# level's now.
	for c: Vector2i in mass.keys():
		if c.y >= fl_r0 and c.y < fl_r1:
			mass.erase(c)
			_shown_dirty[c] = true
	for c: Vector2i in sources.keys():
		if c.y >= fl_r0 and c.y < fl_r1:
			sources.erase(c)
	_fl_band.clear()
	_fl_rows.clear()
	for r in range(maxi(_fl_top, MIN_Y), fl_r0):
		_fl_add_row(r)
	_fl_update_ys()
	_fl_setup_draw()
	fl_cells_implied = 0
	for r in range(fl_r0, fl_r1):
		_fl_mask_row(r)
	# Straight to the level (no lava pouring in from nothing).
	_fl_hold_rows(true, 0.0)
	for c in _fl_band:
		if mass.has(c):
			shown[c] = mass[c]
	_view_dirty = true
	ModLoaderLog.info("Flood line: in the mine at row %.2f (band rows %d..%d, implied %d..%d, %d band cells, %d implied cells seen)" % [row, _fl_top, fl_r0 - 1, fl_r0, fl_r1 - 1, _fl_band.size(), fl_cells_implied], "flantor-StoryMode")


func _fl_update_ys() -> void:
	var y00: float = map.getTilePos(Vector2(0, 0)).y - TILE * 0.5
	_fl_y0 = y00 + float(fl_r0) * TILE
	_fl_y1 = y00 + float(fl_r1) * TILE
	if _fb != null:
		_fb.visible = fl_r0 < fl_r1
		_fg.visible = _fb.visible
		_fb.queue_redraw()
		_fg.queue_redraw()


# The band moves up: its top row is now `top`.
func _fl_move(top: int) -> void:
	var old_top: int = _fl_top
	var old_r0: int = fl_r0
	_fl_top = top
	fl_r0 = mini(top + FloodData.BAND_ROWS, fl_r1)
	# The rows that leave the band at the bottom are implied from now on.
	for r in range(fl_r0, old_r0):
		for x in range(_fl_x0, _fl_x1):
			var c := Vector2i(x, r)
			if mass.has(c):
				mass.erase(c)
				_shown_dirty[c] = true
			if sources.has(c):
				sources.erase(c)
		for c in _fl_rows.get(r, []):
			_fl_band.erase(c)
		_fl_rows.erase(r)
		_fl_mask_row(r)
	# And new rows join it at the top.
	for r in range(maxi(top, MIN_Y), mini(old_top, fl_r0)):
		_fl_add_row(r)
	_fl_update_ys()
	_fl_full_hold = true
	_view_dirty = true


func _fl_add_row(r: int) -> void:
	for x in range(_fl_x0, _fl_x1):
		var c := Vector2i(x, r)
		if _raw_open(c):
			_fl_band_add(c)


func _fl_band_add(c: Vector2i) -> void:
	if _fl_band.has(c):
		return
	_fl_band[c] = true
	if not _fl_rows.has(c.y):
		_fl_rows[c.y] = []
	_fl_rows[c.y].append(c)


func _fl_band_remove(c: Vector2i) -> void:
	if not _fl_band.has(c):
		return
	_fl_band.erase(c)
	var row: Array = _fl_rows.get(c.y, [])
	row.erase(c)


# A cell dug (or melted) under the flood line: lava at once.
func _fl_dug(c: Vector2i) -> void:
	if not _raw_open(c):
		return
	if c.y >= fl_r0:
		if not _fl_known.is_empty() and c.x >= _fl_x0 and c.x < _fl_x1 and c.y >= _fl_my0:
			_fl_learn(c, (c.y - _fl_my0) * (_fl_x1 - _fl_x0) + c.x - _fl_x0)
		return
	if c.y >= MIN_Y:
		_fl_band_add(c)
		_fl_full_hold = true


# Every physics frame while the flood line is in the mine: the band's top row
# follows the level (the rest after a flow step or a move), steam off the
# rising surface, the reveal, the shaders' clock.
func _fl_tick(delta: float) -> void:
	_fl_hold_rows(_fl_full_hold, delta)
	_fl_full_hold = false
	_fl_scan_t += delta
	if _fl_scan_t >= FLOOD_RESCAN_S:
		_fl_scan_t = 0.0
		_fl_rescan()
		_fl_rescan_band()
	if _fl_mask_dirty and _fl_img != null:
		_fl_mask_dirty = false
		_fl_img.set_data(_fl_x1 - _fl_x0, fl_r1 - _fl_my0, false, Image.FORMAT_R8, _fl_mask)
		_fl_tex.update(_fl_img)
	if _fb != null and _fb.visible:
		var o: Vector2 = _origin_base() + Vector2(_fl_x0, _fl_my0) * TILE
		if o != _fl_origin:
			_fl_origin = o
			_fb_mat.set_shader_parameter("origin", o)
			_fg_mat.set_shader_parameter("origin", o)
			_fb.queue_redraw()
			_fg.queue_redraw()
		_fb_mat.set_shader_parameter("time", _time)
		_fg_mat.set_shader_parameter("time", _time)


# Sets the band's cells to the level: the top row as full as the level is into
# it, the rows under it full. Lava that poured onto the band is taken in.
func _fl_hold_rows(all: bool, delta: float) -> void:
	var rows: Array = range(_fl_top, fl_r0) if all else [_fl_top]
	var puff_p: float = FloodData.SURFACE_PUFFS_PER_S * delta
	for r: int in rows:
		var f: float = 1.0 if r > _fl_top else clampf(float(r + 1) - fl_row, 0.0, 1.0)
		for c: Vector2i in _fl_rows.get(r, []):
			var o: float = mass.get(c, 0.0)
			if f <= MIN_MASS:
				if o > 0.0:
					mass.erase(c)
					_shown_dirty[c] = true
				continue
			if absf(o - f) > 0.0005:
				mass[c] = f
				_shown_dirty[c] = true
				if o < 0.1 and f >= 0.1:
					# Magma rock beside it starts to melt (host).
					for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP]:
						if magma.has(c + d):
							_melt_check[c + d] = true
			if r == _fl_top and puff_p > 0.0 and f > 0.05 and _puff_rng.randf() < puff_p and _on_screen(c):
				_puff(c, 1)


# Implied cells the player sees now (a cave opened into, a reveal near the
# line, the tiles a loaded run reveals, a view that moved): open cells in the
# view boxes not yet known as seen, looked at again when the reveal count or
# the view boxes change. Each cell is worked out once (rock stays rock; an
# open cell nobody has seen waits for the next reveal).
func _fl_rescan() -> void:
	if fl_r0 >= fl_r1 or _fl_known.is_empty():
		return
	var n: int = map.visibleTileCoords.size()
	var reveal: bool = n != _fl_seen_n
	if not reveal and _view_boxes == _fl_scan_boxes:
		return
	_fl_seen_n = n
	_fl_scan_boxes = _view_boxes.duplicate()
	var w: int = _fl_x1 - _fl_x0
	for bx in _view_boxes:
		for y in range(maxi(bx[0].y, fl_r0), mini(bx[1].y, fl_r1 - 1) + 1):
			var row: int = (y - _fl_my0) * w - _fl_x0
			for x in range(maxi(bx[0].x, _fl_x0), mini(bx[1].x, _fl_x1 - 1) + 1):
				var kn: int = _fl_known[row + x]
				if kn == FL_ROCK or kn == FL_LAVA or (kn == FL_UNSEEN and not reveal):
					continue
				_fl_learn(Vector2i(x, y), row + x)


# Band cells a tile change missed (a client's tile breaks can come without the
# map's signal, and the open-cell cache may still hold the old answer): the
# band's rows are looked at again, straight from the map.
func _fl_rescan_band() -> void:
	var added := false
	for r in range(maxi(_fl_top, MIN_Y), fl_r0):
		for x in range(_fl_x0, _fl_x1):
			var c := Vector2i(x, r)
			if not _fl_band.has(c) and map.is_tile_empty(c) and not _chamber.has_point(c):
				_open_cache.erase(c)
				_fl_band_add(c)
				added = true
	if added:
		_fl_full_hold = true


const FL_UNKNOWN := 0
const FL_ROCK := 1
const FL_UNSEEN := 2               # open, not seen yet
const FL_LAVA := 3                 # open and seen: the shader draws it
var _fl_known := PackedByteArray()
var _fl_scan_boxes: Array = []


# Works out one implied cell: rock, open but unseen, or lava the shader draws.
func _fl_learn(c: Vector2i, i: int) -> bool:
	if not _raw_open(c):
		_fl_known[i] = FL_ROCK
		return false
	if not _FieldUtil.seen(map, c):
		_fl_known[i] = FL_UNSEEN
		return false
	_fl_known[i] = FL_LAVA
	if _fl_mask[i] != 255:
		_fl_mask[i] = 255
		_fl_mask_dirty = true
		fl_cells_implied += 1
	return true


# Marks the implied, seen open cells of row `r` for the shader.
func _fl_mask_row(r: int) -> void:
	if _fl_mask.is_empty() or r < _fl_my0 or r >= fl_r1:
		return
	var row: int = (r - _fl_my0) * (_fl_x1 - _fl_x0) - _fl_x0
	for x in range(_fl_x0, _fl_x1):
		_fl_learn(Vector2i(x, r), row + x)


func _fl_setup_draw() -> void:
	var w: int = _fl_x1 - _fl_x0
	var hgt: int = fl_r1 - _fl_my0
	if w <= 0 or hgt <= 0:
		return
	_fl_mask.resize(w * hgt)
	_fl_mask.fill(0)
	_fl_known.resize(w * hgt)
	_fl_known.fill(FL_UNKNOWN)
	_fl_scan_boxes = []
	_fl_seen_n = -1
	if DisplayServer.get_name() == "headless":
		return
	_fl_img = Image.create_from_data(w, hgt, false, Image.FORMAT_R8, _fl_mask)
	_fl_tex = ImageTexture.create_from_image(_fl_img)
	_fb_mat = ShaderMaterial.new()
	_fb_mat.shader = load(FLOOD_BODY_SHADER)
	_fb_mat.set_shader_parameter("mask", _fl_tex)
	_fb_mat.set_shader_parameter("first_cell", Vector2(_fl_x0, _fl_my0))
	_fb_mat.set_shader_parameter("tile", TILE)
	_fb_mat.set_shader_parameter("col_body", COL_BODY)
	_fb_mat.set_shader_parameter("col_deep", COL_DEEP)
	_fb_mat.set_shader_parameter("col_hot", COL_HOT)
	_fb_mat.set_shader_parameter("col_crust", COL_CRUST)
	_fb = Node2D.new()
	_fb.name = "LavaFloodBody"
	_fb.material = _fb_mat
	_fb.show_behind_parent = true
	_fb.draw.connect(_draw_flood_rect)
	add_child(_fb)
	_fg_mat = ShaderMaterial.new()
	_fg_mat.shader = load(FLOOD_GLOW_SHADER)
	_fg_mat.set_shader_parameter("mask", _fl_tex)
	_fg_mat.set_shader_parameter("glow_tex", _glow_tex)
	_fg_mat.set_shader_parameter("tile", TILE)
	_fg_mat.set_shader_parameter("first_cell", Vector2(_fl_x0, _fl_my0))
	_fg = Node2D.new()
	_fg.name = "LavaFloodGlow"
	_fg.material = _fg_mat
	_fg.z_index = _glow.z_index
	_fg.draw.connect(_draw_flood_glow_rect)
	add_child(_fg)
	_fl_origin = Vector2.INF
	_fb.visible = fl_r0 < fl_r1
	_fg.visible = _fb.visible


# The rect over the implied rows (the shader keeps to the masked cells).
func _draw_flood_rect() -> void:
	if _fl_origin == Vector2.INF or fl_r0 >= fl_r1:
		return
	var o: Vector2 = _fl_origin + Vector2(0, fl_r0 - _fl_my0) * TILE
	_fb.draw_rect(Rect2(o, Vector2(_fl_x1 - _fl_x0, fl_r1 - fl_r0) * TILE), Color.WHITE)


func _draw_flood_glow_rect() -> void:
	if _fl_origin == Vector2.INF or fl_r0 >= fl_r1:
		return
	var o: Vector2 = _fl_origin + Vector2(-2, fl_r0 - _fl_my0 - 2) * TILE
	_fg.draw_rect(Rect2(o, Vector2(_fl_x1 - _fl_x0 + 4, fl_r1 - fl_r0 + 2) * TILE), Color.WHITE)


func flood_stats() -> Dictionary:
	return {"on": fl_on, "row": snappedf(fl_row, 0.01) if fl_on else null, "band_top": _fl_top, "implied": [fl_r0, fl_r1], "band_cells": _fl_band.size(),
		"implied_seen": fl_cells_implied, "mass_cells": mass.size()}


# --- drawing -------------------------------------------------------------------

func _cell_origin(c: Vector2i) -> Vector2:
	# Top-left corner of a tile, in this node's space (same space as the Map node).
	return to_local(map.getTilePos(Vector2(c))) - Vector2(TILE, TILE) * 0.5


func _noise(c: Vector2i, i: int) -> float:
	return fposmod(sin(float(c.x * 127 + c.y * 311 + i * 74)) * 43758.5453, 1.0)


# A cell's fixed draw noise, worked out once (#347): _noise(c, i) for the crust
# plates (i 0..3, 5..8, 11..14) and the embers (40, 41, 50, 51).
var _noise_cache: Dictionary = {}


func _noises_of(c: Vector2i) -> PackedFloat64Array:
	var a = _noise_cache.get(c)
	if a != null:
		return a
	var out := PackedFloat64Array()
	out.resize(16)
	for i in 4:
		out[i] = _noise(c, i)
		out[4 + i] = _noise(c, i + 5)
		out[8 + i] = _noise(c, i + 11)
	for i in 2:
		out[12 + i] = _noise(c, i + 40)
		out[14 + i] = _noise(c, i + 50)
	_noise_cache[c] = out
	return out


# A magma cell's five cracks, worked out once (#347): x, y, w, h each.
var _crack_cache: Dictionary = {}


func _cracks_of(c: Vector2i) -> PackedFloat32Array:
	var a = _crack_cache.get(c)
	if a != null:
		return a
	var out := PackedFloat32Array()
	for i in 5:
		var horizontal := _noise(c, i + 20) > 0.5
		var length: float = 3.0 + floor(_noise(c, i + 30) * 5.0)
		out.append(3 + floor(_noise(c, i) * 17.0))
		out.append(3 + floor(_noise(c, i + 9) * 17.0))
		out.append(length if horizontal else 1.0)
		out.append(1.0 if horizontal else length)
	_crack_cache[c] = out
	return out


# The top-left corner of cell (0, 0) in this node's space; cell c's is this
# plus c x TILE (#347: _cell_origin() costs three calls into the map a cell).
func _origin_base() -> Vector2:
	return _cell_origin(Vector2i.ZERO)


# The lava cells on screen (plus a margin), so drawing costs the same however
# much lava the map holds. Falls back to every cell if the view can't be read.
var _vis_frame := -1
var _vis_cache: Array = []


# The cached sort (#347): the cell list and how _draw_body() sorted it stay
# while nothing changes near the view (_view_dirty: a cell's drawn lava, a
# tile, the reveal, the view boxes).
var _view_dirty := true
var sorts := 0                       # times the cells were sorted (dev timing)
var _vis_reused := false
var _cache_seen := -1
var _cache_tiles := -1
var _sort_kind := PackedByteArray()
var _sort_h := PackedFloat32Array()
var _sort_warm := PackedFloat32Array()
var _cpu_idx := PackedInt32Array()   # what the CPU draws: indices into the list
var _glow_cells: Array = []          # lava cells the CPU glow pass lights


# Could a change at `c` change how a cell in view is drawn? (Its neighbours
# up to two cells away decide its shape; the boxes already have a margin.)
func _near_view(c: Vector2i) -> bool:
	for bx in _view_boxes:
		if c.x >= bx[0].x - 2 and c.x <= bx[1].x + 2 and c.y >= bx[0].y - 2 and c.y <= bx[1].y + 2:
			return true
	return _view_boxes.is_empty()


# Both draw passes (lava and glow) share one list per frame.
func _visible_cells() -> Array:
	var f := Engine.get_process_frames()
	if f != _vis_frame:
		_vis_frame = f
		_vis_cache = _visible_cells_now()
	return _vis_cache


func _visible_cells_now() -> Array:
	# Every split view's cells (#231): this node draws once for all the views,
	# so a cell on player 2's screen must be in the list even when player 1's
	# camera is far away (it was culled to player 1's view only, so lava
	# popped in late on player 2's screen).
	var boxes: Array = []
	for r: Rect2 in (_Story.view_rects() if Keepers.local.getCount() > 1 and not single_view_cull else []):
		boxes.append([map.getTileCoord(r.position) - Vector2i(2, 2), map.getTileCoord(r.end) + Vector2i(2, 2)])
	if boxes.is_empty():
		var vp := get_viewport()
		if vp == null:
			return shown.keys()
		var inv: Transform2D = get_global_transform_with_canvas().affine_inverse()
		var vr: Rect2 = vp.get_visible_rect()
		var a: Vector2 = inv * vr.position
		var b: Vector2 = inv * vr.end
		var lo: Vector2 = Vector2(minf(a.x, b.x), minf(a.y, b.y))
		var hi: Vector2 = Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
		boxes.append([map.getTileCoord(to_global(lo)) - Vector2i(2, 2), map.getTileCoord(to_global(hi)) + Vector2i(2, 2)])
	# Nothing near the view changed since the last list (#347): the same cells,
	# and _draw_body() keeps how it sorted them.
	var seen_n: int = map.visibleTileCoords.size()
	if not _view_dirty and boxes == _view_boxes and seen_n == _cache_seen and _tile_events == _cache_tiles:
		_vis_reused = true
		return _vis_cache
	_vis_reused = false
	_view_dirty = false
	_cache_seen = seen_n
	_cache_tiles = _tile_events
	_view_boxes = boxes
	_view_c0 = boxes[0][0]
	_view_c1 = boxes[0][1]
	var area := 0
	for bx in boxes:
		area += (bx[1].x - bx[0].x) * (bx[1].y - bx[0].y)
	if area > shown.size():
		# A view wider than the lava (the zoomed-out surface battle): walk the lava
		# cells instead of the view's, but still keep only those on screen. It
		# used to hand back every cell, so a revealed lava ocean far below was
		# drawn in full every frame of the finale (#342).
		var near: Array = []
		for c in shown:
			if _in_boxes(c):
				near.append(c)
		return near
	var out: Array = []
	if boxes.size() == 1:
		# One view: no cell can come twice.
		var bx: Array = boxes[0]
		for y in range(bx[0].y, bx[1].y + 1):
			for x in range(bx[0].x, bx[1].x + 1):
				var c := Vector2i(x, y)
				if shown.has(c):
					out.append(c)
		return out
	var seen := {}
	for bx in boxes:
		for y in range(bx[0].y, bx[1].y + 1):
			for x in range(bx[0].x, bx[1].x + 1):
				var c := Vector2i(x, y)
				if shown.has(c) and not seen.has(c):
					seen[c] = true
					out.append(c)
	return out


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
	return lava_touched(world_rect) != NO_CELL


const NO_CELL := Vector2i(-1073741824, -1073741824)


# The first lava cell whose drawn lava `world_rect` touches, or NO_CELL. A
# stream running on into the cell below counts as the stream's own cell.
func lava_touched(world_rect: Rect2) -> Vector2i:
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
					return up
			if mass.get(c, 0.0) < BURN_MASS:
				continue
			var r: Rect2 = _lava_shape(c)["rect"].grow(-BURN_TOLERANCE)
			if r.size.x > 0.0 and r.size.y > 0.0 and r.intersects(local):
				return c
	return NO_CELL


# The keeper's body for lava contact: a fixed box around its position, from its
# collision shapes (a 5 px circle and two small squares 3.9 px above and below).
#
# Under the flood line's band (#369) the lava is the level's, not stored: a
# keeper whose body reaches below the band's bottom edge is in it.
func keeper_in_lava(keeper) -> bool:
	var r := _FieldUtil.keeper_rect(keeper)
	if fl_r0 < fl_r1 and r.end.y - BURN_TOLERANCE > _fl_y0 and r.position.y < _fl_y1:
		return true
	return lava_overlaps(r)


func _fill_of(c: Vector2i) -> float:
	return clamp(shown.get(c, 0.0), 0.0, 1.0)


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_body()
	draw_us += Time.get_ticks_usec() - t0


func _draw_body() -> void:
	# Magma rock the player can see: glowing cracks that pulse. (The view boxes
	# come from _visible_cells(), so it runs first.)
	var vis: Array = _visible_cells()
	var b0: Vector2 = _origin_base()
	var tiles: Dictionary = map.tiles
	for c: Vector2i in magma:
		if not _in_boxes(c) or not tiles.has(Vector2(c)):
			continue
		var o := b0 + Vector2(c.x * TILE, c.y * TILE)
		var pulse: float = 0.55 + 0.45 * sin(_time * 3.0 + c.x * 1.7 + c.y * 0.9)
		var hot_col := Color(COL_HOT, 0.35 + 0.65 * pulse)
		var core_col := Color(COL_CORE, pulse)
		var cr: PackedFloat32Array = _cracks_of(c)
		for i in 5:
			var p := Vector2(cr[i * 4], cr[i * 4 + 1])
			draw_rect(Rect2(o + p, Vector2(cr[i * 4 + 2], cr[i * 4 + 3])), hot_col)
			draw_rect(Rect2(o + p, Vector2(1, 1)), core_col)

	# The lava cells (#347): sorted in a first pass (kept while nothing near the
	# view changes), then drawn. A row of full, bright cells has its body and
	# dark bottom drawn as one rect each (nothing else draws into another cell
	# of the row in between, so the picture is the same), and the ocean's plain
	# cells are left to its shaders.
	if not _vis_reused or _sort_kind.size() != vis.size():
		_sort_cells(vis, b0)
	elif _ob != null:
		_ob_mat.set_shader_parameter("time", _time)
		_og_mat.set_shader_parameter("time", _time)
	var n: int = vis.size()
	var kind: PackedByteArray = _sort_kind
	var hs: PackedFloat32Array = _sort_h
	var warms: PackedFloat32Array = _sort_warm
	var drawn_to := 0                  # cells before this index have their body drawn
	var deep_h: float = floorf(TILE * 0.35)
	for idx in _cpu_idx:
		var k: int = kind[idx]
		var c: Vector2i = vis[idx]
		var o := b0 + Vector2(c.x * TILE, c.y * TILE)
		if k == 1:
			_draw_stream(c, o)
			continue
		var h: float = hs[idx]
		var warm: float = warms[idx]
		var top: float = TILE - h
		if k >= 4:
			# The ocean shader drew its body and crust; a surface's top is drawn here.
			if k == 4:
				_draw_surface(c, o, top, warm)
			continue
		if idx >= drawn_to:
			if h == TILE and warm == 1.0:
				# A run of full, bright cells side by side: one body, one bottom.
				var j: int = idx
				while j + 1 < n and (kind[j + 1] == 2 or kind[j + 1] == 3) and hs[j + 1] == TILE and warms[j + 1] == 1.0 and vis[j + 1] == vis[j] + Vector2i.RIGHT:
					j += 1
				var w: float = TILE * float(j - idx + 1)
				draw_rect(Rect2(o, Vector2(w, TILE)), COL_BODY)
				draw_rect(Rect2(o + Vector2(0, TILE - deep_h), Vector2(w, deep_h)), COL_DEEP)
				drawn_to = j + 1
			else:
				draw_rect(Rect2(o + Vector2(0, top), Vector2(TILE, h)), COL_CRUST.lerp(COL_BODY, warm))
				# Darker toward the bottom of a deep pool.
				if h > 10:
					draw_rect(Rect2(o + Vector2(0, TILE - floorf(h * 0.35)), Vector2(TILE, floorf(h * 0.35))), COL_DEEP)
				drawn_to = idx + 1
		# Slow drifting crust plates and hot veins.
		var nz: PackedFloat64Array = _noises_of(c)
		var span: float = maxf(1.0, h - 6.0)
		for i in 4:
			var py: float = top + 3.0 + floorf(nz[8 + i] * span)
			if py + 2.0 > TILE:
				continue
			var px: float = floorf(fposmod(nz[i] * TILE + _time * (2.0 + 3.0 * nz[4 + i]), TILE - 4.0))
			if i % 2 == 0:
				draw_rect(Rect2(o + Vector2(px, py), Vector2(4, 1)), COL_HOT)
			else:
				draw_rect(Rect2(o + Vector2(px, py), Vector2(3, 2)), COL_CRUST)
		if k == 2:
			_draw_surface(c, o, top, warm)

	# Steam where water just hardened lava: a white-grey flash that fades.
	for e in _steam:
		var a: float = clampf(e[1] / LavaData.STEAM_SECONDS, 0.0, 1.0)
		var o := _cell_origin(e[0])
		draw_rect(Rect2(o - Vector2(3, 6 + (1.0 - a) * 10.0), Vector2(TILE + 6, TILE + 6)), Color(0.92, 0.92, 0.95, 0.45 * a))
	_draw_puffs()
	# The chamber barrier is the lair seal's now (#366, endgame/lair_seal.gd).
	_draw_heat_bar()
	if debug_boxes:
		var k = _Story.local_keeper()
		if k != null and is_instance_valid(k):
			var r := _FieldUtil.keeper_rect(k)
			draw_rect(Rect2(to_local(r.position), r.size), Color(0.3, 1.0, 0.4, 0.9), false, 1.0)


# Sorts the cells in view for _draw_body() (#347): what each is (kind), how
# tall its lava is drawn and how bright, which the ocean's shaders take (the
# mask), which the CPU draws and which the CPU glow pass lights.
func _sort_cells(vis: Array, b0: Vector2) -> void:
	sorts += 1
	var n: int = vis.size()
	var seen: Dictionary = map.visibleTileCoords
	_ob_draw += 1
	var ob_on: bool = _ob != null and not no_ocean_shader
	var r0: Vector2i = _ob_rect.position
	var r1: Vector2i = _ob_rect.end
	var rw: int = _ob_rect.size.x
	# 0 not drawn, 1 stream, 2 surface, 3 under more lava; 4 and 5 the same
	# but plain and in the ocean, so the ocean shader draws their body.
	var kind := PackedByteArray()
	kind.resize(n)
	var hs := PackedFloat32Array()
	hs.resize(n)
	var warms := PackedFloat32Array()
	warms.resize(n)
	var cpu := PackedInt32Array()
	_glow_cells = []
	for idx in n:
		var c: Vector2i = vis[idx]
		var s: float = shown.get(c, 0.0)
		# (_fill_of() is shown clamped to 0..1.)
		if s <= 0.02 or not seen.has(Vector2(c)):
			continue
		var f: float = minf(s, 1.0)
		var up := Vector2i(c.x, c.y - 1)
		# Lava resting above (a body, not a stream pouring in) fills this cell to the top.
		# (_is_stream() is false for a cell 0.9 full or more: asked only below that.)
		var su: float = shown.get(up, 0.0)
		var above_has: bool = su > 0.05 and (su >= 0.9 or not _is_stream(up))
		# The ocean's top row under the flood line's implied lava (#369).
		if not above_has and c.y == fl_r1 and fl_r0 < fl_r1 and _raw_open(up):
			above_has = true
		if s < 0.9 and _is_stream(c):
			kind[idx] = 1
			continue
		kind[idx] = 3 if above_has else 2
		var h: float = TILE if (above_has or f >= 0.98) else maxf(2.0, roundf(f * TILE))
		hs[idx] = h
		# A thin film with nothing under it is cooling away (#41): it dulls from
		# bright to a dark crust as it goes.
		var warm: float = 1.0
		if f < FILM_MASS and not above_has and shown.get(Vector2i(c.x, c.y + 1), 0.0) < HOLDS_MASS:
			warm = clampf(f / FILM_MASS, 0.0, 1.0)
		warms[idx] = warm
		if h == TILE and warm == 1.0 and ob_on and c.x >= r0.x and c.y >= r0.y and c.x < r1.x and c.y < r1.y:
			_ob_stamp[(c.y - r0.y) * rw + c.x - r0.x] = _ob_draw
			kind[idx] += 2
	if _ob != null:
		_ob_update(b0)
	for idx in n:
		var k: int = kind[idx]
		if k != 0 and k != 5:
			cpu.append(idx)
		if k != 0 and k < 4:
			var c: Vector2i = vis[idx]
			if shown.get(c, 0.0) > 0.05:
				_glow_cells.append(c)
	_sort_kind = kind
	_sort_h = hs
	_sort_warm = warms
	_cpu_idx = cpu


# A resting cell's open top (`top` px down its cell): the bright rippling
# surface, its line, and embers popping off it.
func _draw_surface(c: Vector2i, o: Vector2, top: float, warm: float) -> void:
	# Bright rippling surface: 2 px steps, a step at the same height as the one
	# before it drawn as one rect with it.
	var rc: Color = COL_DEEP.lerp(COL_CORE, warm)
	var x0 := 0
	var y0 := -1.0
	for x in range(0, int(TILE), 2):
		var y: float = top + maxf(0.0, roundf(sin(_time * 4.0 + (c.x * TILE + x) * 0.35)))
		if y != y0:
			if x > x0:
				draw_rect(Rect2(o + Vector2(x0, y0), Vector2(x - x0, 2)), rc)
			x0 = x
			y0 = y
	draw_rect(Rect2(o + Vector2(x0, y0), Vector2(TILE - x0, 2)), rc)
	draw_rect(Rect2(o + Vector2(0, top + 2), Vector2(TILE, 1)), COL_CRUST.lerp(COL_HOT, warm))
	# Embers that pop off the surface.
	if warm > 0.6:
		var nz: PackedFloat64Array = _noises_of(c)
		for i in 2:
			var t: float = fposmod(_time * (0.5 + nz[12 + i]) + nz[14 + i], 1.0)
			var ex: float = floorf(_noise(c, i + 60 + int(_time * 0.5)) * (TILE - 1.0))
			draw_rect(Rect2(o + Vector2(ex, top - t * 14.0), Vector2(1, 1)), Color(COL_CORE, 1.0 - t))


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
	return _FieldUtil.seen(map, c) and _in_boxes(c)


# Is cell `c` in a view box of the last draw (_visible_cells_now)?
func _in_boxes(c: Vector2i) -> bool:
	for bx in _view_boxes:
		if c.x >= bx[0].x and c.x <= bx[1].x and c.y >= bx[0].y and c.y <= bx[1].y:
			return true
	return false


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
# Lava never enters the boss chamber. The energy over its entries is the lair
# seal's to draw since #366 (endgame/lair_seal.gd: blue and impassable before
# the last chain, the purple membrane after). These colours and
# barrier_columns() stay for t347_draw_same's copy of the old drawing.
const COL_BARRIER_DEEP := Color("2e1f8f")
const COL_BARRIER_MID := Color("6b5cff")
const COL_BARRIER_LIGHT := Color("b8b0ff")
const COL_BARRIER_SPARK := Color("eeeaff")


# The chamber columns whose crust is gone (the barrier shows there).
# Worked out again only when a tile has broken or hardened since (#347).
var _barrier_cols: Array = []
var _barrier_key := -1
var _tile_events := 0             # tiles broken or hardened so far


func barrier_columns() -> Array:
	if _barrier_key == _tile_events:
		return _barrier_cols
	var out: Array = []
	if _chamber.size != Vector2i.ZERO:
		for x in range(_chamber.position.x, _chamber.end.x):
			if map.is_tile_empty(Vector2i(x, _chamber.position.y - 1)):
				out.append(x)
	_barrier_cols = out
	_barrier_key = _tile_events
	return out


func _draw_heat_bar() -> void:
	# A bar over each local keeper (#231): shown whenever there is heat, and
	# while passive heat is building.
	for keeper in _Story.local_keepers():
		var h: float = heat_of(keeper)
		if h <= 0.5 and passive_rate_of(keeper) <= 0.0:
			continue
		# A keeper lost to the lava fades out (#369): its bar goes with it.
		if keeper.modulate.a < 0.6:
			continue
		var frac: float = h / HEAT_MAX
		_FieldUtil.draw_bar(self, (to_local(keeper.global_position) + Vector2(-9, -20)).round(), frac,
			COL_CORE.lerp(Color("ff2a1a"), frac), frac > 0.7 and fposmod(_time * 8.0, 1.0) < 0.5)


func _draw_glow() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_glow_body()
	glow_us += Time.get_ticks_usec() - t0


func _draw_glow_body() -> void:
	# Soft additive light around lava and around magma rock the player can see.
	var b0: Vector2 = _origin_base() + Vector2(TILE, TILE) * 0.5
	var seen: Dictionary = map.visibleTileCoords
	_visible_cells()
	for c: Vector2i in _glow_cells:
		var f: float = minf(shown.get(c, 0.0), 1.0)
		var center := b0 + Vector2(c.x * TILE, c.y * TILE)
		var flick: float = 0.85 + 0.15 * sin(_time * 6.0 + c.x * 2.1 + c.y)
		var r: float = 30.0 + 18.0 * f
		_glow.draw_texture_rect(_glow_tex, Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1, 1, 1, 0.22 * flick * (0.4 + 0.6 * f)))
	var tiles: Dictionary = map.tiles
	for c: Vector2i in magma:
		if _in_boxes(c) and tiles.has(Vector2(c)):
			var center := b0 + Vector2(c.x * TILE, c.y * TILE)
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
		"heat": heat, "heats": heats.duplicate(), "recalls": recalls, "breaches": breaches, "pools": pools.size(), "pool_cells": pool_cells,
		"pools_skipped": pools_skipped, "awake": _awake.size(), "ocean_cells": ocean_cells}
