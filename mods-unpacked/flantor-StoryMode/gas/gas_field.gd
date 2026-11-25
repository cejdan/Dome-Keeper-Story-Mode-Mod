extends Node2D

# Noxious gas (#198). Lava upside down, and a gas: hidden pockets of gas rock
# sit in plain rock; breaking into one lets the gas out under pressure, and it
# climbs whatever the keeper has dug: up first, then along ceilings, and down
# only when squeezed. An upward dead end holds it for good; a way to the
# surface lets it out of the mine.
#
# One GasField is a child of the run's Map node (added by gas_director.gd),
# beside the lava field. Nothing here edits vanilla state.
#
# Its tuning numbers are starting values, game-design calls for the user, and
# live in data/gas.gd.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const GasData = preload("res://mods-unpacked/flantor-StoryMode/data/gas.gd")
static var _GasData = GasData  # calls go through this: lazy_preload makes const-preload calls slow
const GasSfx = preload("res://mods-unpacked/flantor-StoryMode/gas/gas_sfx.gd")
static var _GasSfx = GasSfx  # calls go through this: lazy_preload makes const-preload calls slow
const StoryNet = preload("res://mods-unpacked/flantor-StoryMode/net/story_net.gd")
static var _StoryNet = StoryNet  # calls go through this: lazy_preload makes const-preload calls slow
const FieldUtil = preload("res://mods-unpacked/flantor-StoryMode/util/field_util.gd")
static var _FieldUtil = FieldUtil  # calls go through this: lazy_preload makes const-preload calls slow
const SAVE_KEY := "story.gas"
const LAVA_FIELD := "StoryLavaField"
const TILE := 24.0
const WAKE_EPS := 0.00005
const DIRS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

const COL_ROCK_SEEP := Color("9be04a")
const COL_ROCK_CORE := Color("e6ff8a")

var map
var mass: Dictionary = {}          # Vector2i -> float, cells holding gas
var rock: Dictionary = {}          # Vector2i -> true, gas rock still solid
var sources: Dictionary = {}       # Vector2i -> float, gas a breached cell still holds
var breaches := 0
var caverns: Array = []            # Array of Array[Vector2i]: sealed caverns filled at run start (#201)
var caverns_skipped := 0           # caverns left empty because something opened their wall
# The toxin bar, 0..TOXIN_MAX (#202), per local keeper (#231): playerId -> toxin.
# `toxin` is the first local keeper's, as before.
var toxins: Dictionary = {}
var toxin: float:
	get:
		return toxins.get(_Story.local_pid(), 0.0)
	set(v):
		toxins[_Story.local_pid()] = v
var breaths: Dictionary = {}       # playerId -> the densest gas that keeper is in right now
var breathing: float:
	get:
		return breaths.get(_Story.local_pid(), 0.0)
var gassed := 0                    # times the bar filled this run
var fx = null                      # the ToxinFx child: bar, vignette, muffled sound
var _cracks: Dictionary = {}       # gas rock about to burst -> seconds left
var vented := 0.0                  # gas that left through the surface this run
var faded := 0.0                   # gas that thinned away this run
var vent_marks: Dictionary = {}    # top-row cell -> the time gas last left through it
var flux: Dictionary = {}          # cell -> [Vector2 gas moved through it lately, the time it last moved] (for the look)
var look = null                    # the first GasLook (the first local keeper's view) (#203)
var looks: Dictionary = {}         # playerId -> the GasLook drawing that keeper's split view (#231)
var dome = null                    # the DomeGas child: gas vented into the dome (#213)
var revision := 0                  # goes up whenever any cell's gas changes (for the look)
# Dev only: hold the gas still.
var freeze_flow := false
# Dev only: hold the toxin bar where it is.
var freeze_toxin := false
var phys_us := 0
var phys_frames := 0

var _acc := 0.0
var _time := 0.0
var prev_mass: Dictionary = {}     # the gas before the last step: the look blends from it (#211)
var moving := false                # the last step (or host packet) changed some gas: the look glides
var rise: Dictionary = {}          # cell -> momentum of its gas, in tiles climbed (#217); not saved
var drift: Dictionary = {}         # cell -> which way that momentum runs along a ceiling, -1 left .. 1 right
var _awake: Dictionary = {}
var _wake_all := true
var _chamber: Rect2i = Rect2i()
var _ocean: Dictionary = {}
var _lava = null

# Online multiplayer (#228), as the lava field does it (#227): the host alone
# moves the gas (flow, sources, bursts, ignition, fire, venting) and after
# every step sends clients the cells that changed (absolute mass, and the flux
# through them for the look), fire lit and gone out, cells that vented and the
# dome's gas. A client draws what it is sent, gliding from one packet to the
# next as the host glides between steps. The toxin bar stays with each
# player's own instance (their keeper); a gassing's penalty and beat are the
# host's (through the lava field's recall).
var net_client := false            # this instance draws the host's gas
var net_packets := 0               # client: packets applied (playtests)
var _net_dirty: Dictionary = {}    # host: cells whose gas or flux changed since the last send
var _net_all := true               # host: send everything next (after a fill or load)
var _net_fire_on: Dictionary = {}  # host: cells lit since the last send
var _net_fire_off: Dictionary = {} # host: fires gone since the last send
var _net_vents: Dictionary = {}    # host: top-row cells that vented since the last send
var _net_dome := -1.0              # host: the dome gas clients last got


func setup(p_map) -> void:
	map = p_map
	z_index = 7
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ocean = map.tileData.get_meta("story_ocean", {})
	var ch = map.tileData.get_meta("story_boss_chamber", null)
	_chamber = ch if ch is Rect2i else Rect2i()
	_lava = map.get_node_or_null(LAVA_FIELD)
	# The gas that has gone up into the dome (#213), restored with the rest.
	dome = load("res://mods-unpacked/flantor-StoryMode/gas/dome_gas.gd").new()
	dome.name = "DomeGas"
	add_child(dome)
	dome.setup(self)
	net_client = Network.is_client()
	if net_client:
		# Pockets, caverns and what has leaked so far all come from the host.
		_StoryNet.gas_full_request()
	elif not _restore(str(Data.ofOr(SAVE_KEY, ""))):
		_place_pockets()
		_fill_caverns()
	map.tile_destroyed.connect(_on_tile_destroyed)
	add_to_group("saveable")
	if DisplayServer.get_name() != "headless":
		_sync_looks()
		fx = load("res://mods-unpacked/flantor-StoryMode/gas/toxin_fx.gd").new()
		fx.name = "ToxinFx"
		add_child(fx)
		fx.setup(self)


# --- pockets -------------------------------------------------------------------

# Each plain rock cell decides for itself, from the level seed and its own
# coordinates, whether it seeds a pocket (as magma pockets do), so the same
# seed gives the same pockets however much of the mine has been dug, and
# nothing else the generator placed moves.
func _place_pockets() -> void:
	var td = map.tileData
	var taken := {}
	if _lava != null:
		for c in _lava.magma:
			taken[c] = true
	for pool in td.get_meta("story_pools", []):
		for c in pool:
			for ox in range(-1, 2):
				for oy in range(-1, 2):
					taken[Vector2i(c) + Vector2i(ox, oy)] = true
	var rock_set := {}
	for c in td.get_resource_cells_by_id(Data.TILE_DIRT_START):
		if taken.has(c) or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE:
			continue
		if td.get_biomev(c) < GasData.POCKET_START_BIOME:
			continue
		if not _ocean.is_empty() and c.y >= int(_ocean["ceiling"]) - 1:
			continue
		rock_set[c] = true
	var rng := RandomNumberGenerator.new()
	for s in rock_set:
		var per: int = int(_GasData.pocket_rock_per_pocket(td.get_biomev(s)))
		if hash([Level.levelSeed, "gas", s.x, s.y]) % per != 0:
			continue
		rng.seed = hash([Level.levelSeed, "gaspocket", s.x, s.y])
		var size: int = rng.randi_range(GasData.POCKET_SIZE[0], GasData.POCKET_SIZE[1]) + int(s.y / GasData.POCKET_GROW_ROWS)
		var cells := [s]
		var guard := 0
		while cells.size() < size and guard < 80:
			guard += 1
			var from: Vector2i = cells[rng.randi() % cells.size()]
			var n: Vector2i = from + DIRS[rng.randi() % 4]
			if rock_set.has(n) and not cells.has(n):
				cells.append(n)
		for c in cells:
			rock[c] = true


# Fills the sealed caverns the map generator carved (#201) with gas, already
# at rest: a cell k rows above its cavern's lowest row holds 1 + COMPRESS x k,
# exactly where the flow balances (the upper of two stacked cells holds
# COMPRESS more; cells side by side hold the same), so nothing moves and the
# cavern sleeps from the first step. A cavern something else opened (a cave
# placed at run start) is left empty.
func _fill_caverns() -> void:
	for cavern in map.tileData.get_meta("story_gas_caverns", []):
		var set := {}
		for c in cavern:
			set[Vector2i(c)] = true
		var sealed := true
		var bottom: int = -(1 << 20)
		for c in set:
			bottom = maxi(bottom, c.y)
			if not _is_open(c):
				sealed = false
			for d in DIRS:
				if not set.has(c + d) and map.is_tile_empty(c + d):
					sealed = false
		if not sealed:
			caverns_skipped += 1
			continue
		for c in set:
			mass[c] = 1.0 + GasData.COMPRESS * float(bottom - c.y)
		caverns.append(set.keys())
	wake_all()


func add_pocket(cells: Array) -> void:
	for c in cells:
		rock[Vector2i(c)] = true


# Puts gas straight into open cells (playtests, and sealed caverns: #201).
func fill(cells: Array, density: float) -> void:
	for c in cells:
		mass[Vector2i(c)] = density
	wake_all()


func wake_all() -> void:
	_wake_all = true
	_net_all = true
	revision += 1


func _wake(c: Vector2i) -> void:
	_awake[c] = true
	for d in DIRS:
		_awake[c + d] = true


func _on_tile_destroyed(world_pos: Vector2) -> void:
	var c: Vector2i = map.getTileCoord(world_pos)
	_wake(c)
	revision += 1
	if not rock.has(c):
		return
	rock.erase(c)
	InputSystem.shake(4.0, 0.4, 20.0, world_pos)
	_GasSfx.play("burst", -3.0, 0.5)
	if net_client:
		return                         # the gas it lets out, and the rest bursting, are the host's
	sources[c] = sources.get(c, 0.0) + GasData.VOLUME_PER_ROCK_CELL
	breaches += 1
	_cracks.erase(c)
	# The pocket was under pressure: the rest of it bursts, cell by cell.
	for d in DIRS:
		if rock.has(c + d) and not _cracks.has(c + d):
			_cracks[c + d] = GasData.CRACK_SECONDS


# Open to gas: an empty cell inside the mine, outside the boss chamber, and not
# full of lava.
func _is_open(c: Vector2i) -> bool:
	if c.y < GasData.MIN_Y or not map.is_tile_empty(c) or _chamber.has_point(c):
		return false
	return _lava == null or _lava.mass.get(c, 0.0) < 0.9


# Open sky over the mine's top row: nothing there at all.
func _is_sky(c: Vector2i) -> bool:
	return c.y < GasData.MIN_Y and map.tileData.get_resourcev(c) == -1


# A top-row cell whose gas leaves into the dome rather than the open air (#213).
func under_dome(c: Vector2i) -> bool:
	var d = Level.domesByTeamId.get("team1") if "domesByTeamId" in Level else null
	if d == null or not is_instance_valid(d):
		return false
	return absf(map.getTilePos(Vector2(c)).x - d.global_position.x) <= GasData.DOME_HALF_WIDTH


# --- simulation ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if map == null or GameWorld.paused:
		return
	var t0 := Time.get_ticks_usec()
	_time += delta
	_acc += delta
	if not net_client:
		_burst(delta)
		while _acc >= GasData.TICK:
			_acc -= GasData.TICK
			moving = false
			if not freeze_flow:
				prev_mass = mass.duplicate()
				_step()
			_net_send()
	_update_fire(delta)
	_update_toxin(delta)
	_update_puffs(delta)
	if fx != null:
		_sync_looks()
	phys_us += Time.get_ticks_usec() - t0
	phys_frames += 1
	queue_redraw()


func _burst(delta: float) -> void:
	for c in _cracks.keys():
		_cracks[c] -= delta
		if _cracks[c] > 0.0:
			continue
		_cracks.erase(c)
		if not rock.has(c):
			continue
		var tile = map.getTile(Vector2(c))
		if tile != null and is_instance_valid(tile):
			_StoryNet.tile_break(map, c)
			map.destroyTile("team1", "", tile)   # fires tile_destroyed -> breach
		else:
			rock.erase(c)


# The gas steps a few times a second (#211); the look shows it gliding from
# one step to the next, a step behind. 0..1: how far into that glide it is.
func step_blend() -> float:
	return clampf(_acc / GasData.TICK, 0.0, 1.0)


# A cell's gas as drawn: between its last two steps.
func shown_mass(c: Vector2i) -> float:
	var now: float = mass.get(c, 0.0)
	if freeze_flow:
		return now
	return lerpf(prev_mass.get(c, now), now, step_blend())


# How much of `total` the upper of two stacked cells should hold.
func _split(total: float) -> float:
	var k: float = GasData.COMPRESS
	if total <= 1.0:
		return 1.0
	if total < 2.0 + k:
		return (1.0 + total * k) / (1.0 + k)
	return (total + k) / 2.0


func _step() -> void:
	# Breached gas rock lets its gas out under pressure.
	for c in sources.keys():
		var room: float = GasData.SOURCE_PRESSURE - mass.get(c, 0.0)
		var out: float = minf(GasData.SOURCE_RATE, minf(sources[c], room))
		if out > 0.0:
			mass[c] = mass.get(c, 0.0) + out
			sources[c] -= out
			_net_dirty[c] = true
			moving = true
			_wake(c)
			revision += 1
		if sources[c] <= 0.001:
			sources.erase(c)

	var all_awake: bool = _wake_all
	_wake_all = false
	if not all_awake and _awake.is_empty():
		return
	var work: Array = mass.keys() if all_awake else _awake.keys().filter(func(c): return mass.has(c))
	var max_flow: float = GasData.MAX_FLOW
	var dm: Dictionary = {}
	var inm: Dictionary = {}           # gas flowing into a cell this step
	var rin: Dictionary = {}           # ... times the momentum it brings (#217)
	var din: Dictionary = {}           # ... times the way it is going along a ceiling
	for c in work:
		var m: float = mass[c]
		if m <= 0.0:
			continue
		var rem := m
		var r: float = rise.get(c, 0.0)
		var up: Vector2i = c + Vector2i.UP
		# The surface: gas in the mine's top row with sky above it is gone.
		if _is_sky(up):
			var out: float = minf(rem, GasData.VENT_PER_STEP)
			dm[c] = dm.get(c, 0.0) - out
			vented += out
			vent_marks[c] = _time
			_net_vents[c] = true
			if dome != null and under_dome(c):
				dome.add(out)
			rem -= out
			if rem <= 0.0:
				continue
		var up_open := _is_open(up)
		var mu: float = mass.get(up, 0.0)
		if up_open:
			var flow: float = clampf((_split(rem + mu) - mu) * GasData.RISE_SHARE, 0.0, minf(max_flow, rem))
			if flow > 0.0:
				dm[c] = dm.get(c, 0.0) - flow
				dm[up] = dm.get(up, 0.0) + flow
				_carry(inm, rin, din, up, flow, minf(r + 1.0, GasData.RISE_MAX), 0.0)
				_flux(c, up, flow)
				rem -= flow
		if rem <= 0.0:
			continue
		# Sideways: freely once the gas rests against a ceiling or full gas, a
		# slow drift while it is still rising.
		var resting: bool = not up_open or mu >= 0.9
		var div: float = GasData.SIDE_DIVISOR if resting else GasData.DRIFT_DIVISOR
		# Gas under rock clings to it (#212): it keeps CLING_MASS, and only what
		# is more than that moves on along the ceiling. So a low ceiling or a
		# bend holds some of the gas, and only a pocket with more than that to
		# give lets any out, slowly. Not toward an opening that leads up, and
		# not while the gas still has momentum from climbing (#217).
		var ceiling: bool = not up_open and not _is_sky(up)
		if ceiling and r >= 1.0:
			rem = _splash(c, rem, r, dm, inm, rin, din)
		var cling := 0.0
		if ceiling:
			cling = GasData.CLING_MASS * clampf(1.0 - r, 0.0, 1.0)
		for side in ([] if ceiling and r >= 1.0 else [Vector2i.LEFT, Vector2i.RIGHT]):
			var sc: Vector2i = c + side
			if not _is_open(sc):
				continue
			var su: Vector2i = sc + Vector2i.UP
			var free: float = rem if _is_open(su) or _is_sky(su) else rem - cling
			if free <= 0.0:
				continue
			var ms: float = mass.get(sc, 0.0)
			var flow: float = clampf((m - ms) / div, 0.0, minf(max_flow, free))
			# No slivers into empty cells: they would be dropped as too thin.
			if ms <= 0.0 and flow < GasData.MIN_PACKET:
				continue
			if flow > GasData.MIN_FLOW:
				dm[c] = dm.get(c, 0.0) - flow
				dm[sc] = dm.get(sc, 0.0) + flow
				_carry(inm, rin, din, sc, flow, maxf(r - 1.0, 0.0), float(side.x))
				_flux(c, sc, flow)
				rem -= flow
		# Down: only gas squeezed past a full cell.
		if rem > 1.0:
			var down: Vector2i = c + Vector2i.DOWN
			if _is_open(down):
				var flow: float = clampf((rem - _split(rem + mass.get(down, 0.0))) * GasData.RISE_SHARE, 0.0, minf(max_flow, rem))
				if flow > GasData.MIN_FLOW:
					dm[c] = dm.get(c, 0.0) - flow
					dm[down] = dm.get(down, 0.0) + flow
					_carry(inm, rin, din, down, flow, 0.0, 0.0)
					_flux(c, down, flow)

	var woke: Dictionary = {}
	for c in dm:
		var o: float = mass.get(c, 0.0)
		var m: float = o + dm[c]
		_set_mass(c, o, m, woke)
	_update_rise(inm, rin, din)
	# Thin gas that has stopped moving fades (only awake cells are looked at;
	# fading keeps a cell awake). Thin gas on its way somewhere is left alone.
	for c in work:
		if not mass.has(c) or dm.has(c):
			continue
		var o: float = mass[c]
		if o < GasData.THIN_MASS:
			var lost: float = minf(o, GasData.DECAY_PER_SECOND * GasData.TICK)
			faded += lost
			_set_mass(c, o, o - lost, woke)
	if not woke.is_empty():
		revision += 1
	_awake = {}
	for c in woke:
		_wake(c)


# Gas with momentum under a ceiling (#217) runs along it: SPLASH_SHARE of it
# is pushed out to the open sides, split evenly where it has just hit, then
# all one way once it is going that way (back the other way off a wall).
# Returns what is left in the cell.
func _splash(c: Vector2i, rem: float, r: float, dm: Dictionary, inm: Dictionary, rin: Dictionary, din: Dictionary) -> float:
	var d: float = drift.get(c, 0.0)
	var w := {}
	var wsum := 0.0
	for side in [Vector2i.LEFT, Vector2i.RIGHT]:
		if _is_open(c + side):
			w[side] = (1.0 + float(side.x) * d) * 0.5
			wsum += w[side]
	if w.is_empty():
		return rem
	if wsum < 0.01:
		for side in w:
			w[side] = 1.0
		wsum = float(w.size())
	var push: float = rem * GasData.SPLASH_SHARE
	for side in w:
		var flow: float = minf(push * w[side] / wsum, GasData.MAX_FLOW)
		var sc: Vector2i = c + side
		if flow < GasData.MIN_PACKET and mass.get(sc, 0.0) <= 0.0:
			continue
		dm[c] = dm.get(c, 0.0) - flow
		dm[sc] = dm.get(sc, 0.0) + flow
		_carry(inm, rin, din, sc, flow, r - 1.0, float(side.x))
		_flux(c, sc, flow)
		rem -= flow
	return rem


func _carry(inm: Dictionary, rin: Dictionary, din: Dictionary, n: Vector2i, flow: float, r: float, d: float) -> void:
	inm[n] = inm.get(n, 0.0) + flow
	if r > 0.0:
		rin[n] = rin.get(n, 0.0) + flow * r
		din[n] = din.get(n, 0.0) + flow * r * d


# Each cell's momentum after a step (#217): what stayed keeps its own, less
# RISE_DECAY; what flowed in brings its own; the cell's gas averages them.
# The way it runs is averaged the same way, weighted by momentum.
func _update_rise(inm: Dictionary, rin: Dictionary, din: Dictionary) -> void:
	var cells: Dictionary = rin.duplicate()
	for c in rise:
		cells[c] = true
	for c in cells:
		var m: float = mass.get(c, 0.0)
		if m <= 0.0:
			rise.erase(c)
			drift.erase(c)
			continue
		var stayed: float = maxf(m - inm.get(c, 0.0), 0.0)
		var kept: float = stayed * maxf(rise.get(c, 0.0) - GasData.RISE_DECAY, 0.0)
		var sum: float = kept + rin.get(c, 0.0)
		var r: float = sum / m
		if r < 0.01:
			rise.erase(c)
			drift.erase(c)
		else:
			rise[c] = minf(r, GasData.RISE_MAX)
			drift[c] = clampf((kept * drift.get(c, 0.0) + din.get(c, 0.0)) / sum, -1.0, 1.0)


# Notes gas moving from `c` to `n`, for the look: a running sum that halves
# about every FLUX_HALF_LIFE seconds.
const FLUX_HALF_LIFE := 0.3              # (0.12 before #211's slower clock)


func _flux(c: Vector2i, n: Vector2i, flow: float) -> void:
	var dir := Vector2(n - c) * flow
	for k in [c, n]:
		_net_dirty[k] = true
		var e = flux.get(k)
		if e == null:
			flux[k] = [dir, _time]
		else:
			e[0] = e[0] * pow(0.5, (_time - e[1]) / FLUX_HALF_LIFE) + dir
			e[1] = _time


# The flux through a cell right now (zero once it is stale).
func flux_at(c: Vector2i) -> Vector2:
	var e = flux.get(c)
	if e == null:
		return Vector2.ZERO
	var age: float = _time - e[1]
	if age > 1.0:
		flux.erase(c)
		return Vector2.ZERO
	return e[0] * pow(0.5, age / FLUX_HALF_LIFE)


func _set_mass(c: Vector2i, o: float, m: float, woke: Dictionary) -> void:
	if m != o:
		_net_dirty[c] = true
		moving = true
	if m > GasData.MIN_MASS:
		mass[c] = m
	else:
		if m > 0.0:
			faded += m
		mass.erase(c)
	if absf(m - o) > WAKE_EPS or (m <= GasData.MIN_MASS and o > 0.0):
		woke[c] = true


# --- fire (#204) ------------------------------------------------------------------
# Lava lights gas. A burning cell uses its gas up, lights the gas cells around
# it (all eight) a moment later, and glows on for a moment once empty. The
# keeper's suit heats in it (through the lava field's heat, scaled by Heat
# Shielding); burning gas is not breathed. Nothing else changes: no rock
# breaks, the lava stays as it is.

const DIRS8 := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]

var fire: Dictionary = {}          # burning cell -> [seconds burning, seconds to the next spread, seconds since it ran out of gas]
var burned := 0.0                  # gas burnt this run
var ignitions := 0                 # times lava lit gas this run
var in_fire := false               # the keeper is in a burning cell right now
var _ignite_t := 0.0
var _roar_t := 0.0


func ignite(c: Vector2i) -> void:
	if fire.has(c):
		return
	var thick: float = clampf(mass.get(c, 0.0), 0.0, 1.0)
	fire[c] = [0.0, lerpf(GasData.FIRE_SPREAD_SECONDS[0], GasData.FIRE_SPREAD_SECONDS[1], thick), 0.0]
	_net_fire_off.erase(c)
	_net_fire_on[c] = true
	revision += 1


# 0..1: how hot a cell burns right now (for the look).
func fire_at(c: Vector2i) -> float:
	var e = fire.get(c)
	if e == null:
		return 0.0
	if e[2] > 0.0:
		return clampf(1.0 - e[2] / GasData.FIRE_EMBER_SECONDS, 0.0, 1.0)
	return minf(1.0, 0.35 + e[0] * 8.0)


func _update_fire(delta: float) -> void:
	# Gas beside lava catches (looked for a few times a second, from whichever
	# of the two there is less of).
	_ignite_t -= delta
	if not net_client and _ignite_t <= 0.0 and _lava != null and not mass.is_empty() and not _lava.mass.is_empty():
		_ignite_t = 0.12
		var lit := 0
		if mass.size() <= _lava.mass.size():
			for c in mass:
				if mass[c] < GasData.IGNITE_MASS or fire.has(c):
					continue
				for d in DIRS:
					if _lava.mass.get(c + d, 0.0) >= GasData.LAVA_IGNITES_MASS:
						ignite(c)
						lit += 1
						break
		else:
			for lc in _lava.mass:
				if _lava.mass[lc] < GasData.LAVA_IGNITES_MASS:
					continue
				for d in DIRS:
					var n: Vector2i = lc + d
					if mass.get(n, 0.0) >= GasData.IGNITE_MASS and not fire.has(n):
						ignite(n)
						lit += 1
		if lit > 0:
			ignitions += 1
	in_fire = false
	if fire.is_empty():
		return
	revision += 1
	var burning := 0
	for c in fire.keys():
		var e: Array = fire[c]
		e[0] += delta
		var m: float = mass.get(c, 0.0)
		if m > 0.0 and not net_client:
			_net_dirty[c] = true
			var use: float = minf(m, GasData.FIRE_BURN_PER_SECOND * delta)
			burned += use
			m -= use
			if m > GasData.MIN_MASS:
				mass[c] = m
			else:
				burned += m
				m = 0.0
				mass.erase(c)
			_wake(c)
		if m > 0.0:
			burning += 1
			e[2] = 0.0
			if _on_screen_cell(c) and _puff_rng.randf() < delta * 5.0:
				_ember(c)
		else:
			e[2] += delta
			if net_client:
				continue                   # the host says when it is out
			if e[2] >= GasData.FIRE_EMBER_SECONDS:
				fire.erase(c)
				if not _net_fire_on.erase(c):
					_net_fire_off[c] = true
				continue
		if net_client:
			continue                       # the host spreads it
		# It keeps lighting whatever gas is, or arrives, around it.
		e[1] -= delta
		if e[1] <= 0.0:
			e[1] = GasData.FIRE_SPREAD_SECONDS[1]
			for d in DIRS8:
				var n: Vector2i = c + d
				if not fire.has(n) and mass.get(n, 0.0) >= GasData.IGNITE_MASS and _is_open(n):
					ignite(n)
	# A roar that grows with the fire, and a shake.
	_roar_t -= delta
	if burning > 0 and _roar_t <= 0.0:
		_roar_t = 0.35
		_GasSfx.play("ignite", clampf(-10.0 + burning * 0.6, -10.0, 2.0))
		InputSystem.shake(minf(2.0 + burning * 0.25, 9.0), 0.3, 22.0)
	# A keeper in the fire: suit heat, as lava gives it (every local keeper, #231).
	if _lava == null:
		return
	for keeper in _Story.local_keepers():
		if keeper.killed or keeper.disabled:
			continue
		var r: Rect2 = _FieldUtil.keeper_rect(keeper)
		var a: Vector2i = map.getTileCoord(r.position)
		var b: Vector2i = map.getTileCoord(r.end)
		var burning_here := false
		for y in range(a.y, b.y + 1):
			for x in range(a.x, b.x + 1):
				if fire.has(Vector2i(x, y)):
					burning_here = true
		if burning_here:
			in_fire = true
			var LavaData = _lava.LavaData
			_lava.set_heat_of(keeper, minf(LavaData.HEAT_MAX, _lava.heat_of(keeper) + GasData.FIRE_HEAT_PER_SECOND * LavaData.lava_heat_mult(keeper) * delta))


func _on_screen_cell(c: Vector2i) -> bool:
	if not _FieldUtil.seen(map, c):
		return false
	for l in looks.values():
		if is_instance_valid(l) and c.x >= l.c0.x and c.y >= l.c0.y and c.x < l.c0.x + l.WIN.x and c.y < l.c0.y + l.WIN.y:
			return true
	return false


func _ember(c: Vector2i) -> void:
	if _puffs.size() >= PUFF_MAX:
		return
	var p: Vector2 = _cell_origin(c) + Vector2(_puff_rng.randf_range(2.0, TILE - 2.0), _puff_rng.randf_range(2.0, TILE - 2.0))
	_puffs.append([p.x, p.y, _time, _puff_rng.randf_range(0.5, 1.1), _puff_rng.randf(), _puff_rng.randf_range(14.0, 40.0), 1.0, EMBER])


# --- toxin (#202) ----------------------------------------------------------------

func _update_toxin(delta: float) -> void:
	# Every keeper this instance plays breathes on its own (#231).
	for keeper in _Story.local_keepers():
		_update_keeper_toxin(keeper, delta)


func toxin_of(keeper) -> float:
	return toxins.get(keeper.playerId, 0.0)


func set_toxin_of(keeper, v: float) -> void:
	toxins[keeper.playerId] = v


func _update_keeper_toxin(keeper, delta: float) -> void:
	if keeper.killed or freeze_toxin:
		return
	var pid: String = keeper.playerId
	breaths[pid] = 0.0
	var t: float = toxins.get(pid, 0.0)
	if keeper.isInsideDome:
		var rate_in: float = dome.toxin_rate() if dome != null else 0.0
		if rate_in <= 0.0:
			# Clean dome air clears the suit at once.
			toxins[pid] = 0.0
			return
		# Gas vented into the dome (#213): the bar fills slowly while the keeper
		# is inside, fighting or not, and never clears there.
		toxins[pid] = minf(GasData.TOXIN_MAX, t + rate_in * delta)
		if toxins[pid] >= GasData.TOXIN_MAX:
			_gassed_in_dome(keeper)
		return
	if keeper.disabled:
		return
	breaths[pid] = gas_in(_FieldUtil.keeper_rect(keeper), true)
	var rate: float = _GasData.toxin_share(breaths[pid])
	if rate > 0.0:
		t = minf(GasData.TOXIN_MAX, t + GasData.TOXIN_PER_SECOND * rate * delta)
	else:
		t = maxf(0.0, t - GasData.CLEAR_PER_SECOND * delta)
	toxins[pid] = t
	if t < GasData.TOXIN_MAX:
		return
	gassed += 1
	_gassed(keeper)
	ModLoaderLog.info("Gassed (%s): death %d" % [pid, gassed], "flantor-StoryMode")


# A full bar in the dome (#213): a gas death like one in the mine, but the
# keeper is already home, so no trip.
func _gassed_in_dome(keeper) -> void:
	gassed += 1
	_gassed(keeper, false)
	ModLoaderLog.info("Gassed in the dome: death %d" % gassed, "flantor-StoryMode")


# The same death as an overheat in lava (cargo dropped, half the money), or a
# heart in the boss sequence; but its own count and beat (#357).
func _gassed(keeper, teleport: bool = true) -> void:
	var jammed: bool = _lava != null and _lava.overheat(keeper, teleport, "gas")
	toxins[keeper.playerId] = GasData.TOXIN_MAX * _lava.OVERHEAT_AFTER if jammed else 0.0


# One GasLook per local keeper's split view (#231): a look simulates a window
# of tiles around one camera, so each view gets its own, shown in that view
# only. With one local keeper there is one, shown everywhere, as before.
var _looks_for := -1


func _sync_looks() -> void:
	var ks: Array = _Story.local_keepers()
	var want: Dictionary = {}
	for k in ks:
		want[k.playerId] = k
	if ks.is_empty():
		if not looks.is_empty():
			return
		want["player1"] = null
	var changed := false
	for pid in looks.keys():
		if not want.has(pid) or not is_instance_valid(looks[pid]):
			if is_instance_valid(looks[pid]):
				looks[pid].queue_free()
			looks.erase(pid)
			changed = true
	for pid in want:
		if not looks.has(pid):
			var l = load("res://mods-unpacked/flantor-StoryMode/gas/gas_look.gd").new()
			l.name = "GasLook" if looks.is_empty() else "GasLook_" + pid
			add_child(l)
			l.setup(self)
			looks[pid] = l
			changed = true
		looks[pid].keeper = want[pid]
	var first = _Story.local_keeper()
	look = looks.get(first.playerId, null) if first != null and is_instance_valid(first) else null
	if look == null and not looks.is_empty():
		look = looks.values()[0]
	if changed or ks.size() != _looks_for:
		_looks_for = ks.size()
		for pid in looks:
			looks[pid].show_in_view_of(want[pid] if ks.size() > 1 else null)


# The keeper's body for gas contact: the same box the lava uses.
# The densest gas in the cells a rect (world space) touches.
func gas_in(world_rect: Rect2, not_burning: bool = false) -> float:
	var a: Vector2i = map.getTileCoord(world_rect.position)
	var b: Vector2i = map.getTileCoord(world_rect.end)
	var best := 0.0
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			if not_burning and fire.has(Vector2i(x, y)):
				continue
			best = maxf(best, mass.get(Vector2i(x, y), 0.0))
	return best


func gas_at(world_pos: Vector2) -> float:
	return mass.get(map.getTileCoord(world_pos), 0.0)


# --- save and load ---------------------------------------------------------------
# As the lava field does: serialize() puts the gas into Data (SAVE_KEY), which
# vanilla writes into the save; vanilla's loader skips this node's own entry.

func serialize() -> Dictionary:
	if net_client:
		return {"meta.priority": 9001, "meta.kind": "storygas"}   # the run's gas is the host's to save
	var cells: Array = []
	for c in mass:
		cells.append([c.x, c.y, snappedf(mass[c], 0.0001)])
	var src: Array = []
	for c in sources:
		src.append([c.x, c.y, snappedf(sources[c], 0.0001)])
	var rocks: Array = []
	for c in rock:
		rocks.append([c.x, c.y])
	_StoryNet.save_blob(SAVE_KEY, JSON.stringify(_save_extra({"seed": Level.levelSeed, "mass": cells, "sources": src, "rock": rocks,
		"breaches": breaches, "vented": vented, "faded": faded, "caverns": caverns.size(), "burned": burned, "ignitions": ignitions})))
	return {"meta.priority": 9001, "meta.kind": "storygas"}


func _save_extra(d: Dictionary) -> Dictionary:
	d["toxin"] = toxin
	d["toxins"] = toxins
	d["gassed"] = gassed
	if dome != null:
		d["dome"] = dome.amount
		d["dome_vents"] = dome.vents
	return d


func _restore(blob: String) -> bool:
	if blob == "":
		return false
	var d = JSON.parse_string(blob)
	if not d is Dictionary or int(d.get("seed", -1)) != Level.levelSeed:
		return false
	mass.clear()
	rise.clear()
	drift.clear()
	sources.clear()
	rock.clear()
	for e in d.get("mass", []):
		mass[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	for e in d.get("sources", []):
		sources[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	for e in d.get("rock", []):
		rock[Vector2i(int(e[0]), int(e[1]))] = true
	breaches = int(d.get("breaches", 0))
	vented = float(d.get("vented", 0.0))
	faded = float(d.get("faded", 0.0))
	burned = float(d.get("burned", 0.0))
	ignitions = int(d.get("ignitions", 0))
	_restore_extra(d)
	wake_all()
	ModLoaderLog.info("Gas restored from save: %d cells, %d gas rock" % [mass.size(), rock.size()], "flantor-StoryMode")
	return true


func _restore_extra(d: Dictionary) -> void:
	toxins = _FieldUtil.per_player(d, "toxins", "toxin")
	gassed = int(d.get("gassed", 0))
	if dome != null:
		dome.amount = float(d.get("dome", 0.0))
		dome.vents = int(d.get("dome_vents", 0))


# --- online multiplayer (#228) -----------------------------------------------------
# A packet: [u32 n, n x (i16 x, i16 y, f32 mass, f32 flux x, f32 flux y)]
# [u16 n, n x cell] fires lit, [u16 n, n x cell] fires out, [u16 n, n x cell]
# cells that vented, [f32] the dome's gas, and in a full one [u32 n, n x cell]
# the gas rock still solid.

static func _put_cells(buf: StreamPeerBuffer, cells: Array, wide: bool = false) -> void:
	if wide:
		buf.put_u32(cells.size())
	else:
		buf.put_u16(cells.size())
	for c: Vector2i in cells:
		buf.put_16(c.x)
		buf.put_16(c.y)


static func _get_cells(buf: StreamPeerBuffer, wide: bool = false) -> Array:
	var out: Array = []
	for i in (buf.get_u32() if wide else buf.get_u16()):
		out.append(Vector2i(buf.get_16(), buf.get_16()))
	return out


func _net_pack(cells: Array, fire_on: Array, fire_off: Array, vents: Array, full: bool) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u32(cells.size())
	for c: Vector2i in cells:
		var f: Vector2 = flux_at(c)
		buf.put_16(c.x)
		buf.put_16(c.y)
		buf.put_float(mass.get(c, 0.0))
		buf.put_float(f.x)
		buf.put_float(f.y)
	_put_cells(buf, fire_on)
	_put_cells(buf, fire_off)
	_put_cells(buf, vents)
	buf.put_float(dome.amount if dome != null else 0.0)
	if full:
		_put_cells(buf, rock.keys(), true)
	return buf.data_array


# Host, after every step: what changed since the last send.
func _net_send() -> void:
	var amount: float = dome.amount if dome != null else 0.0
	if Network.is_offline_mode() or Network.clients.is_empty():
		_net_dirty.clear()
		_net_fire_on.clear()
		_net_fire_off.clear()
		_net_vents.clear()
		_net_all = false
		_net_dome = amount
		return
	if _net_all:
		_StoryNet.gas_cells(net_full(), true)
	elif not _net_dirty.is_empty() or not _net_fire_on.is_empty() or not _net_fire_off.is_empty() or not _net_vents.is_empty() or amount != _net_dome:
		_StoryNet.gas_cells(_net_pack(_net_dirty.keys(), _net_fire_on.keys(), _net_fire_off.keys(), _net_vents.keys(), false), false)
	_net_all = false
	_net_dome = amount
	_net_dirty.clear()
	_net_fire_on.clear()
	_net_fire_off.clear()
	_net_vents.clear()


# Host: all the gas, for a client whose field was just built (or after a fill).
func net_full() -> PackedByteArray:
	return _net_pack(mass.keys(), fire.keys(), [], [], true)


# Client: a packet from the host. `full` replaces everything.
func net_apply(data: PackedByteArray, full: bool) -> void:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	# The look glides from the gas before this packet to the gas after it.
	prev_mass = mass.duplicate()
	_acc = 0.0
	moving = true
	if full:
		mass.clear()
		flux.clear()
		fire.clear()
	for i in buf.get_u32():
		var c := Vector2i(buf.get_16(), buf.get_16())
		var m: float = buf.get_float()
		var f := Vector2(buf.get_float(), buf.get_float())
		if m > GasData.MIN_MASS:
			mass[c] = m
		else:
			mass.erase(c)
		if f != Vector2.ZERO:
			flux[c] = [f, _time]
		else:
			flux.erase(c)
	for c in _get_cells(buf):
		# Lit a moment ago; in a full packet, already burning.
		fire[c] = [1.0 if full else 0.0, 0.0, 0.0]
	for c in _get_cells(buf):
		fire.erase(c)
	for c in _get_cells(buf):
		vent_marks[c] = _time
	var amount: float = buf.get_float()
	if dome != null:
		dome.amount = amount
	if full:
		rock.clear()
		for c in _get_cells(buf, true):
			rock[c] = true
		prev_mass = mass.duplicate()
	net_packets += 1
	revision += 1


# --- drawing -------------------------------------------------------------------

func _cell_origin(c: Vector2i) -> Vector2:
	return to_local(map.getTilePos(Vector2(c))) - Vector2(TILE, TILE) * 0.5


func _noise(c: Vector2i, i: int) -> float:
	return fposmod(sin(float(c.x * 157 + c.y * 271 + i * 61)) * 43758.5453, 1.0)


func _draw() -> void:
	# Gas rock the player can see: green seeping cracks that breathe.
	for c in rock:
		if not map.tiles.has(Vector2(c)):
			continue
		var o := _cell_origin(c)
		var pulse: float = 0.5 + 0.5 * sin(_time * 2.2 + c.x * 1.3 + c.y * 0.7)
		for i in 5:
			var p := Vector2(3 + floor(_noise(c, i) * 17.0), 3 + floor(_noise(c, i + 9) * 17.0))
			var horizontal := _noise(c, i + 20) > 0.5
			var length: float = 3.0 + floor(_noise(c, i + 30) * 5.0)
			var size := Vector2(length, 1) if horizontal else Vector2(1, length)
			draw_rect(Rect2(o + p, size), Color(COL_ROCK_SEEP, 0.3 + 0.6 * pulse))
			draw_rect(Rect2(o + p, Vector2(1, 1)), Color(COL_ROCK_CORE, pulse))
	_draw_gas()
	_draw_puffs()


# Fallback look, a flat tint by density, when there is no GasLook (headless runs).
func _draw_gas() -> void:
	if look != null:
		return
	for c in mass:
		if not _FieldUtil.seen(map, c):
			continue
		var a: float = clampf(mass[c], 0.0, 1.5) / 1.5
		draw_rect(Rect2(_cell_origin(c), Vector2(TILE, TILE)), Color(0.45, 0.8, 0.2, 0.15 + 0.6 * a))


# --- puffs (#203) ---------------------------------------------------------------
# Small green puffs drawn here, outside the fluid field: the plume over a shaft
# mouth where gas is leaving the mine, and wisps seeping from gas rock the
# player can see. Drawn only; never saved.

const PUFF_MAX := 220
const COL_PUFF := Color("8fd13c")
const COL_PUFF_LIT := Color("e6ff8a")
const COL_EMBER := Color("fff2b0")
const COL_EMBER_OUT := Color("ff7a1c")
const SMOKE := 0                   # a puff's kind
const EMBER := 1                   # a spark off burning gas (#204)

var _puffs: Array = []             # [x, y, time born, seconds to live, 0..1 seed, rise px, size, kind]
var _puff_rng := RandomNumberGenerator.new()
var _seep_t := 0.0


func _puff(pos: Vector2, life: float, rise: float, size: float) -> void:
	if _puffs.size() >= PUFF_MAX:
		return
	_puffs.append([pos.x, pos.y, _time, life, _puff_rng.randf(), rise, size, SMOKE])


func _update_puffs(delta: float) -> void:
	# The plume: every top-row cell that vented in the last moment throws puffs up.
	for c in vent_marks.keys():
		var age: float = _time - vent_marks[c]
		if age > 0.6:
			vent_marks.erase(c)
			continue
		if not _FieldUtil.seen(map, c):
			continue
		# (The surface/dome vent hiss is off: too grating on repeat.)
		for i in 2:
			if _puff_rng.randf() < delta * 30.0:
				_puff(_cell_origin(c) + Vector2(_puff_rng.randf_range(3.0, TILE - 3.0), _puff_rng.randf_range(-4.0, 6.0)),
					_puff_rng.randf_range(1.2, 2.2), _puff_rng.randf_range(30.0, 75.0), _puff_rng.randf_range(2.0, 5.0))
	# Seeping: now and then a wisp leaves a visible gas rock cell into the open cell beside it.
	_seep_t -= delta
	if _seep_t <= 0.0 and not rock.is_empty():
		_seep_t = 0.12
		for c in rock:
			if _puff_rng.randf() > 0.3 or not map.tiles.has(Vector2(c)):
				continue
			var d := Vector2i.ZERO
			var first: int = _puff_rng.randi() % 4
			for k in 4:
				var cand: Vector2i = DIRS[(first + k) % 4]
				if map.is_tile_empty(c + cand) and _FieldUtil.seen(map, c + cand):
					d = cand
					break
			if d == Vector2i.ZERO:
				continue
			var edge: Vector2 = _cell_origin(c) + Vector2(TILE, TILE) * 0.5 + Vector2(d) * (TILE * 0.5 + 1.0)
			edge += Vector2(absf(d.y), absf(d.x)) * _puff_rng.randf_range(-8.0, 8.0)
			_puff(edge, _puff_rng.randf_range(0.9, 1.6), _puff_rng.randf_range(8.0, 16.0), 1.0)
	if not _puffs.is_empty():
		_puffs = _puffs.filter(func(q): return _time - q[2] < q[3])


# Each puff rises fast and slows, sways, swells and fades.
func _draw_puffs() -> void:
	for q in _puffs:
		var age: float = _time - q[2]
		var t: float = age / q[3]
		if t < 0.0 or t >= 1.0:
			continue
		var s: float = q[4]
		var x: float = round(q[0] + sin(age * 2.2 + s * TAU) * (1.0 + 5.0 * t) + (s - 0.5) * 14.0 * t)
		var y: float = round(q[1] - q[5] * (1.0 - (1.0 - t) * (1.0 - t)))
		var col: Color
		if q[7] == EMBER:
			col = Color(COL_EMBER.lerp(COL_EMBER_OUT, minf(1.0, t * 1.6)), 1.0 - t * t)
		else:
			col = Color(COL_PUFF_LIT.lerp(COL_PUFF, minf(1.0, t * 2.0)), 0.6 * pow(1.0 - t, 1.2) * minf(1.0, age * 12.0))
		var r: float = floor(q[6] * (0.6 + 1.2 * t))
		if r < 1.0:
			draw_rect(Rect2(x, y, 1.0, 1.0), col)
			continue
		draw_rect(Rect2(x - r, y - 1.0, r * 2.0, 2.0), col)
		if r > 1.0:
			draw_rect(Rect2(x - r + 1.0, y - r + 1.0, r * 2.0 - 2.0, r * 2.0 - 2.0), col)
			draw_rect(Rect2(x - 1.0, y - r, 2.0, r * 2.0), col)


func total() -> float:
	var t := 0.0
	for c in mass:
		t += mass[c]
	for c in sources:
		t += sources[c]
	return t


func stats() -> Dictionary:
	return {"cells": mass.size(), "total": total(), "rock": rock.size(), "sources": sources.size(), "breaches": breaches,
		"vented": vented, "faded": faded, "burned": burned, "ignitions": ignitions, "fire": fire.size(), "awake": _awake.size(), "toxin": toxin, "toxins": toxins.duplicate(), "gassed": gassed,
		"dome_pockets": dome.pockets() if dome != null else 0.0}
