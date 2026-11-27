extends Node2D

# The lair seal (#366, End game 2.0 map #363): the energy over the boss
# chamber's two entries (LavaData.BOSS_CHAMBER_ENTRY, the drillable crust in
# the chamber's living-stone roof, #361). Values in data/lair_seal.gd.
#
#   Before the last chain (#365): thick blue energy. Nothing passes:
#     - the entries' crust refuses every hit (drills, the Assessor's spheres,
#       kunai, claws, cats, bombs, blasts, gadgets: Tile.hit / remote_hit and
#       Map.destroyTile ask LairSeal.refuses(cell));
#     - a solid body fills each entry on the tile layers, so if the crust is
#       ever missing (an old save drilled open) keepers, drops, drones and
#       pets still stop on it;
#     - touching it or hitting its crust crackles, throws the keeper back and
#       plays a zap.
#   After it (EndGame.is_free(), or the horror awake): the smaller purple
#   energy, the old chamber barrier (#82): a membrane on the chamber's top
#   edge under each entry. Lava still stops there (the lava field never fills
#   the chamber); keepers drill the crust and pass. The change plays live
#   when the last chain breaks and the seal is on a view (else the first time
#   it comes on one); a load or a late join just shows purple.
#   Entering the lair: a keeper of this instance in the chamber with the seal
#   open is reported to the host (StoryNet.lair_entered on a client), which
#   records it (EndGame.record_lair_entered): that wakes the horror
#   (Awakening.wake -> the "boss_chamber" beat -> boss/boss_director.gd starts
#   the fight) and is the "keeper entered the lair" state the rising lava
#   (#369) reads: EndGame.is_lair_entered(), when_lair_entered(cb),
#   node().lair_entered(player_id).
#
# Every peer builds its own from the chamber's rect; the state is the host's
# (EndGame's Data), so collision and look follow it everywhere. A keeper is
# thrown back on its own instance (keepers move on their owner's); a touch's
# crackle reaches the other peers by StoryNet.seal_touch, a crust hit by
# vanilla's own tile hit messages.
#
# Dev routes that put a keeper in the chamber without passing the seal
# (`--boss`, playtests that teleport) set the horror awake themselves; `--boss`
# also breaks every chain quietly first (ChainAnchors.dev_free_all), so the
# run's end-game state matches.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const EndGame = preload("res://mods-unpacked/flantor-StoryMode/endgame/end_game.gd")
static var _EndGame = EndGame  # calls go through this: lazy_preload makes const-preload calls slow
const SealData = preload("res://mods-unpacked/flantor-StoryMode/data/lair_seal.gd")
const LavaData = preload("res://mods-unpacked/flantor-StoryMode/data/lava.gd")
const Sfx = preload("res://mods-unpacked/flantor-StoryMode/boss/sfx.gd")
static var _Sfx = Sfx  # calls go through this: lazy_preload makes const-preload calls slow
const StoryNet = preload("res://mods-unpacked/flantor-StoryMode/net/story_net.gd")
static var _StoryNet = StoryNet  # calls go through this: lazy_preload makes const-preload calls slow
const FieldUtil = preload("res://mods-unpacked/flantor-StoryMode/util/field_util.gd")
static var _FieldUtil = FieldUtil  # calls go through this: lazy_preload makes const-preload calls slow

const NAME := "StoryLairSeal"
const TILE := 24.0
const SHADER := "res://mods-unpacked/flantor-StoryMode/endgame/lair_seal.gdshader"
const HUM := "res://content/sounds/Locations/DomeShield/Damagefield_Loop.wav"
const AWAKE_KEY := "team1.story.awake"   # beats/awakening.gd AWAKE (not preloaded: it preloads EndGame)
const SEEN_EVERY := 0.5
const TILE_LAYERS := 32787       # vanilla's Tile.tscn collision_layer: everything that hits rock hits the seal
const QUAD_PAD := 8.0            # px of the plug's rect beyond the hole, each side
const QUAD_TOP := 6.0            # px over the dome's top
const QUAD_BOTTOM := 6.0         # px under the lip
const RIP_NAMES: Array[StringName] = [&"u_rip0", &"u_rip1", &"u_rip2", &"u_rip3"]

signal opened(live: bool)        # the look reached purple (live: the opening played)

# Playtests: what happened, newest last.
static var events: Array = []

var chamber: Rect2i = Rect2i()
var entries: Array = []          # {cols, x0, x1, plug, mat, body, shape, rips, hit_cd, arc_cd, seed}
var mode: String = "sealed"      # sealed, pending (live, waiting for a view), opening, open
var t_open: float = 0.0          # seconds into the opening (negative: its delay)
var blocking: bool = true        # the bodies are on
var seen: bool = false
var touches: int = 0             # local keepers thrown back (playtests)
var hits_refused: int = 0        # crust hits the seal took (playtests)
var passes: int = 0              # local keepers through the open membrane (playtests)
var remote_touches: int = 0      # other peers' keepers' touches played here (playtests)
var process_us: int = 0          # this node's own work, all frames (playtests)
var process_frames: int = 0

var _map = null
var _fx: Node2D
var _glow: Node2D
var _glow_tex: GradientTexture2D
var _white: ImageTexture
var _hum: AudioStreamPlayer
var _time: float = 0.0
var _seen_acc: float = 0.0
var _probe: Array = []
var _data_wait: float = 0.0
var _live_word: bool = false
var _touch_cd: Dictionary = {}   # playerId -> s until it can be thrown again
var _pass_cd: Dictionary = {}    # playerId -> s
var _prev_y: Dictionary = {}     # playerId -> local y last frame
var _reported: Dictionary = {}   # playerId -> true: told the host it entered
var _inside_sealed: Dictionary = {}   # playerId -> true: logged in a sealed lair
var _arcs: Array = []            # {pts, t, life, col}
var _sparks: Array = []          # {p, v, t, life, col}
var _shards: Array = []          # {p, v, rot, rv, t, size}
var _rings: Array = []           # {c, t, life, r0, r1, col, w}
var _circuit_wave: float = -1.0  # px the opening's wave has run along the circuit (-1: none)
var _bump: float = 0.0           # agitation from touches, decays
var _on_view: bool = false
var _vis: Dictionary = {"phase": 0.0, "tint": 0.0, "crack": 0.0, "flash": 0.0, "agitate": 0.0}
var _rng := RandomNumberGenerator.new()


static func find():
	if Level.map == null or not is_instance_valid(Level.map):
		return null
	return Level.map.get_node_or_null(NAME)


# --- the state (any peer) ----------------------------------------------------------

# The seal lets keepers through: the last chain has broken, or the horror is
# already awake (a run from before #366 that was in the lair, the dev routes).
static func is_open() -> bool:
	return _EndGame.is_free() or bool(Data.ofOr(AWAKE_KEY, false))


static var _rect_map_id := 0
static var _rect := Rect2i()


static func _chamber_rect() -> Rect2i:
	if Level.map == null or not is_instance_valid(Level.map) or Level.map.tileData == null:
		return Rect2i()
	var td = Level.map.tileData
	if td.get_instance_id() != _rect_map_id:
		var ch = td.get_meta("story_boss_chamber") if td.has_meta("story_boss_chamber") else null
		_rect = ch if ch is Rect2i else Rect2i()
		# A client gets the chamber a moment after its map (#225): cache a found one.
		if ch is Rect2i:
			_rect_map_id = td.get_instance_id()
	return _rect


# One of the entries' crust cells (the roof row, an entry column).
static func is_seal_cell(c: Vector2i) -> bool:
	var ch: Rect2i = _chamber_rect()
	if ch.size == Vector2i.ZERO or c.y != ch.position.y - 1:
		return false
	return (c.x - ch.position.x) in LavaData.BOSS_CHAMBER_ENTRY


# Tile.hit, Tile.remote_hit and Map.destroyTile ask this first: true = the
# blue seal takes the blow, the crust stays whole.
static func refuses(c: Vector2i) -> bool:
	return is_seal_cell(c) and not is_open() and _Story.is_story()


# A refused hit on crust cell `c` (`dir` the hit's direction; `local` false
# for a hit another peer made): the crackle, and a throw for a keeper of
# ours right at it.
static func crust_hit(c: Vector2i, dir: Vector2, local: bool) -> void:
	var n = find()
	if n != null:
		n._on_crust_hit(c, dir, local)


# --- setup --------------------------------------------------------------------------

func setup(map) -> bool:
	var td = map.tileData
	if not td.has_meta("story_boss_chamber"):
		return false
	chamber = td.get_meta("story_boss_chamber")
	_map = map
	name = NAME
	z_index = 7          # over the lava (6) and the crust tiles
	position = map.to_local(map.getTilePos(Vector2(chamber.position))) - Vector2(12, 12)
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unshaded
	_rng.seed = hash([chamber, "lairseal"])
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(img)
	# Group the entry columns into entries (runs of neighbours).
	var cols: Array = LavaData.BOSS_CHAMBER_ENTRY.duplicate()
	cols.sort()
	var runs: Array = []
	for col in cols:
		if not runs.is_empty() and int(runs[-1][-1]) == int(col) - 1:
			runs[-1].append(int(col))
		else:
			runs.append([int(col)])
	var shader: Shader = load(SHADER)
	for run in runs:
		var e := {"cols": run, "x0": float(run[0]) * TILE, "x1": float(run[-1] + 1) * TILE,
			"rips": [], "hit_cd": 0.0, "arc_cd": _rng.randf_range(0.2, 1.0), "seed": _rng.randf() * 10.0}
		_build_plug(e, shader)
		_build_body(e)
		entries.append(e)
	_fx = Node2D.new()
	_fx.name = "Fx"
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_glow = Node2D.new()
	_glow.name = "Glow"
	_glow.z_index = 1
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	_glow_tex = GradientTexture2D.new()
	_glow_tex.gradient = grad
	_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_glow_tex.fill_from = Vector2(0.5, 0.5)
	_glow_tex.fill_to = Vector2(1.0, 0.5)
	_glow_tex.width = 64
	_glow_tex.height = 64
	_hum = AudioStreamPlayer.new()
	_hum.bus = &"Monster"
	if ResourceLoader.exists(HUM):
		_hum.stream = load(HUM)
	_hum.finished.connect(func(): if _hum.volume_db > -60.0: _hum.play())
	add_child(_hum)
	# Seen once an entry, the lava over it or the chamber's top row is in sight.
	for e in entries:
		for col in e["cols"]:
			for dy in [-2, -1, 0]:
				_probe.append(Vector2(chamber.position.x + int(col), chamber.position.y + dy))
	for x in range(chamber.position.x, chamber.end.x):
		_probe.append(Vector2(x, chamber.position.y))
	# The state now: a loaded run after the last chain shows purple at once.
	if is_open():
		_set_open(false)
	else:
		_set_blocking(true)
		_EndGame.when_free(_on_free)
	visible = false
	_check_seen()
	ModLoaderLog.info("Lair seal: %d entries, %s" % [entries.size(), mode], _Story.LOG)
	return true


func _build_plug(e: Dictionary, shader: Shader) -> void:
	var plug := Node2D.new()
	plug.name = "Plug%d" % entries.size()
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var x0: float = e["x0"] - QUAD_PAD
	var y0: float = -TILE - SealData.CAP_PX - QUAD_TOP
	var size := Vector2(e["x1"] - e["x0"] + QUAD_PAD * 2.0, TILE + SealData.CAP_PX + QUAD_TOP + SealData.LIP_PX + QUAD_BOTTOM)
	e["quad"] = Rect2(Vector2(x0, y0), size)
	mat.set_shader_parameter("u_size", size)
	mat.set_shader_parameter("u_hole", Vector4(QUAD_PAD, size.x - QUAD_PAD, -TILE - y0, -y0))
	mat.set_shader_parameter("u_cap", SealData.CAP_PX)
	mat.set_shader_parameter("u_cap_edge", SealData.CAP_EDGE_PX)
	mat.set_shader_parameter("u_lip", SealData.LIP_PX)
	mat.set_shader_parameter("u_over", SealData.OVERHANG_PX)
	mat.set_shader_parameter("u_membrane", SealData.MEMBRANE_PX)
	mat.set_shader_parameter("u_seed", e["seed"])
	mat.set_shader_parameter("u_rip_life", SealData.RIPPLE_LIFE)
	mat.set_shader_parameter("deep_a", SealData.BLUE_DEEP)
	mat.set_shader_parameter("mid_a", SealData.BLUE)
	mat.set_shader_parameter("light_a", SealData.BLUE_LIGHT)
	mat.set_shader_parameter("spark_a", SealData.BLUE_SPARK)
	mat.set_shader_parameter("deep_b", SealData.PURPLE_DEEP)
	mat.set_shader_parameter("mid_b", SealData.PURPLE)
	mat.set_shader_parameter("light_b", SealData.PURPLE_LIGHT)
	mat.set_shader_parameter("spark_b", SealData.PURPLE_SPARK)
	plug.material = mat
	var quad: Rect2 = e["quad"]
	plug.draw.connect(func(): plug.draw_texture_rect(_white, quad, false))
	add_child(plug)
	e["plug"] = plug
	e["mat"] = mat


func _build_body(e: Dictionary) -> void:
	var body := StaticBody2D.new()
	body.name = "SealBody%d" % entries.size()
	body.collision_layer = TILE_LAYERS
	body.collision_mask = 0
	body.set_meta("story_lair_seal", true)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	var top: float = -TILE + SealData.BODY_TOP_INSET_PX
	var bottom: float = SealData.BODY_LIP_PX
	rect.size = Vector2(e["x1"] - e["x0"], bottom - top)
	shape.shape = rect
	shape.position = Vector2((e["x0"] + e["x1"]) * 0.5, (top + bottom) * 0.5)
	body.add_child(shape)
	add_child(body)
	e["body"] = body
	e["shape"] = shape


func _set_blocking(on: bool) -> void:
	blocking = on
	for e in entries:
		e["shape"].set_deferred("disabled", not on)


# --- the opening --------------------------------------------------------------------

func _on_free(live: bool) -> void:
	if mode != "sealed":
		return
	if live:
		_live_word = true
		_set_blocking(false)
		mode = "pending"
		t_open = -SealData.OPEN_DELAY_S
		events.append({"what": "free_live", "t": _time})
	else:
		_set_open(false)


func _set_open(live: bool) -> void:
	_set_blocking(false)
	mode = "open"
	_vis = {"phase": 1.0, "tint": 1.0, "crack": 0.0, "flash": 0.0, "agitate": 0.0}
	events.append({"what": "open", "live": live, "t": _time})
	ModLoaderLog.info("Lair seal: open (%s)" % ("played live" if live else "shown open"), _Story.LOG)
	opened.emit(live)


func _start_opening() -> void:
	mode = "opening"
	events.append({"what": "opening", "t": _time})
	ModLoaderLog.info("Lair seal: the opening plays", _Story.LOG)
	_sound_at("seal_strain", _centre_global(), -3.0, 0.9)


func _opening_step(delta: float) -> void:
	var before: float = t_open
	t_open += delta
	var t: float = t_open
	var v: Dictionary = {"phase": 0.0, "tint": 0.0, "crack": 0.0, "flash": 0.0, "agitate": 0.05}
	if t < 0.0:
		pass
	elif t < SealData.STRAIN_S:
		var s: float = t / SealData.STRAIN_S
		v["agitate"] = 0.05 + 0.95 * s
		v["crack"] = s * s
		v["flash"] = 0.15 * s * s
	elif t < SealData.COLLAPSE_END_S:
		var c: float = (t - SealData.STRAIN_S) / (SealData.COLLAPSE_END_S - SealData.STRAIN_S)
		v["phase"] = smoothstep(0.0, 1.0, c)
		v["tint"] = smoothstep(0.0, 0.75, c)
		v["crack"] = maxf(0.0, 1.0 - c * 1.6)
		v["agitate"] = 1.0 - 0.75 * c
		v["flash"] = maxf(0.0, 1.0 - (t - SealData.STRAIN_S) / 0.35)
	else:
		var u: float = clampf((t - SealData.COLLAPSE_END_S) / (SealData.SETTLE_END_S - SealData.COLLAPSE_END_S), 0.0, 1.0)
		v["phase"] = 1.0
		v["tint"] = 1.0
		v["agitate"] = 0.25 * (1.0 - u)
		v["flash"] = 0.25 * maxf(0.0, 1.0 - u * 3.0)
	_vis = v
	if before < 0.0 and t >= 0.0:
		_start_opening()
	if before < SealData.STRAIN_S and t >= SealData.STRAIN_S:
		_break_moment()
	if before < SealData.COLLAPSE_END_S and t >= SealData.COLLAPSE_END_S:
		_settle_moment()
	if t >= SealData.SETTLE_END_S:
		_set_open(true)


# The blue gives: a white flash, a shock ring, shards, the circuit's wave.
func _break_moment() -> void:
	events.append({"what": "break", "t": _time})
	var at: Vector2 = _centre_global()
	_sound_at("seal_break", at, 0.0, 1.0)
	_sound_at("seal_shatter", at, -4.0, 1.1)
	for e in entries:
		var c: Vector2 = Vector2((e["x0"] + e["x1"]) * 0.5, -TILE * 0.5)
		_rings.append({"c": c, "t": 0.0, "life": 0.7, "r0": 10.0, "r1": 120.0, "col": SealData.BLUE_SPARK, "w": 3.0})
		_rings.append({"c": c, "t": -0.08, "life": 0.9, "r0": 6.0, "r1": 80.0, "col": SealData.BLUE_LIGHT, "w": 2.0})
		for i in SealData.SHARDS:
			var ang: float = -PI * _rng.randf_range(0.05, 0.95) if i % 3 != 0 else _rng.randf() * TAU
			var p: Vector2 = c + Vector2(_rng.randf_range(-22.0, 22.0), _rng.randf_range(-14.0, 6.0))
			_shards.append({"p": p, "v": Vector2.from_angle(ang) * _rng.randf_range(80.0, 230.0), "rot": _rng.randf() * TAU,
				"rv": _rng.randf_range(-10.0, 10.0), "t": 0.0, "life": _rng.randf_range(0.8, 1.4), "size": _rng.randf_range(2.0, 4.5)})
		for i in 4:
			_add_arc(e, c, Vector2(_rng.randf_range(-60.0, 60.0), _rng.randf_range(-50.0, 10.0)) + c, SealData.BLUE_SPARK, 0.35)
	_circuit_wave = 0.0
	for k in _Story.local_keepers():
		if is_instance_valid(k) and k.global_position.distance_to(at) < SealData.SHAKE_RANGE:
			InputSystem.shake(SealData.SHAKE[0], SealData.SHAKE[1], SealData.SHAKE[2])
			break


func _settle_moment() -> void:
	events.append({"what": "settle", "t": _time})
	_sound_at("seal_settle", _centre_global(), -4.0, 0.85)
	for e in entries:
		var c: Vector2 = Vector2((e["x0"] + e["x1"]) * 0.5, 0.0)
		_rings.append({"c": c, "t": 0.0, "life": 1.1, "r0": 4.0, "r1": 70.0, "col": SealData.PURPLE_LIGHT, "w": 2.0})


# --- every frame ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var us0: int = Time.get_ticks_usec()
	if _map == null or not is_instance_valid(_map):
		return
	if not seen:
		_seen_acc += delta
		if _seen_acc >= SEEN_EVERY:
			_seen_acc = 0.0
			_check_seen()
	var open_now: bool = is_open()
	if blocking == open_now:
		_set_blocking(not open_now)
	match mode:
		"sealed":
			if open_now:
				# Open by Data alone: a live word may be on its way (a client).
				_data_wait += delta
				if _data_wait >= SealData.DATA_GRACE:
					_set_open(false)
			else:
				_data_wait = 0.0
		"pending":
			# Live, but nobody is looking yet (or play is frozen, a cutscene,
			# #367): it plays when a view first shows it.
			if seen and not GameWorld.paused and _seal_on_view(80.0):
				mode = "opening"
		"opening":
			if not GameWorld.paused:
				_opening_step(delta)
	if not GameWorld.paused:
		_keepers(delta, open_now)
	process_us += Time.get_ticks_usec() - us0


func _process(delta: float) -> void:
	if _map == null or not is_instance_valid(_map) or not seen:
		return
	var us0: int = Time.get_ticks_usec()
	process_frames += 1
	if not GameWorld.paused:
		_time += delta
		_step_fx(delta)
	_on_view = _seal_on_view(160.0)
	_update_hum()
	if not _on_view and _fx_empty():
		process_us += Time.get_ticks_usec() - us0
		return
	var fight: bool = str(Data.ofOr(_Story.BOSS_STATE, "")) == "fight"
	for e in entries:
		var mat: ShaderMaterial = e["mat"]
		var agitate: float = float(_vis["agitate"])
		if mode == "sealed" or mode == "pending":
			agitate = maxf(agitate, minf(1.0, _bump))
		elif mode == "open" and fight:
			agitate = 0.35
		mat.set_shader_parameter(&"u_time", _time)
		# The rest only when it changed: most frames nothing but the time does.
		var key := Vector4(float(_vis["phase"]), float(_vis["tint"]), float(_vis["crack"]) + 2.0 * float(_vis["flash"]), agitate)
		if key != e.get("last_key", Vector4(-1, -1, -1, -1)):
			e["last_key"] = key
			mat.set_shader_parameter(&"u_phase", key.x)
			mat.set_shader_parameter(&"u_tint", key.y)
			mat.set_shader_parameter(&"u_crack", _vis["crack"])
			mat.set_shader_parameter(&"u_flash", _vis["flash"])
			mat.set_shader_parameter(&"u_agitate", agitate)
		var rips: Array = e["rips"]
		var n_rips: int = rips.size()
		if n_rips > 0 or int(e.get("last_rips", 0)) > 0:
			var quad: Rect2 = e["quad"]
			for i in maxi(n_rips, int(e.get("last_rips", 0))):
				var r: Vector4 = Vector4.ZERO
				if i < n_rips:
					var q: Dictionary = rips[i]
					r = Vector4(q["p"].x - quad.position.x, q["p"].y - quad.position.y, q["t"], q["s"])
				mat.set_shader_parameter(RIP_NAMES[i], r)
			e["last_rips"] = n_rips
	queue_redraw()
	_fx.queue_redraw()
	_glow.queue_redraw()
	process_us += Time.get_ticks_usec() - us0


func _check_seen() -> void:
	var vis: Dictionary = _map.visibleTileCoords
	for c in _probe:
		if vis.has(c):
			seen = true
			visible = true
			return


func _centre_global() -> Vector2:
	return to_global(Vector2(chamber.size.x * TILE * 0.5, -TILE * 0.5))


func _seal_on_view(grow: float) -> bool:
	var rects: Array = _Story.view_rects(grow)
	if rects.is_empty():
		return true
	for e in entries:
		var p: Vector2 = to_global(Vector2((e["x0"] + e["x1"]) * 0.5, -TILE * 0.5))
		for r: Rect2 in rects:
			if r.has_point(p):
				return true
	return false


# Touches, passes and entries of this instance's keepers.
func _keepers(delta: float, open_now: bool) -> void:
	for pid in _touch_cd.keys():
		_touch_cd[pid] = float(_touch_cd[pid]) - delta
	for pid in _pass_cd.keys():
		_pass_cd[pid] = float(_pass_cd[pid]) - delta
	var room := Rect2(Vector2.ZERO, Vector2(chamber.size) * TILE).grow(-2.0)
	for k in _Story.local_keepers():
		if k == null or not is_instance_valid(k) or k.disabled:
			continue
		var pid: String = k.playerId
		var p: Vector2 = to_local(k.global_position)
		var box := Rect2(p - _FieldUtil.KEEPER_BOX * 0.5, _FieldUtil.KEEPER_BOX)
		if blocking:
			for e in entries:
				# The slab's skin, as high as the dome stands at the keeper's x.
				var mid: float = (e["x0"] + e["x1"]) * 0.5
				var half: float = (e["x1"] - e["x0"]) * 0.5 + SealData.OVERHANG_PX
				var dx: float = clampf((p.x - mid) / half, -1.0, 1.0)
				var dome_top: float = -TILE - SealData.CAP_EDGE_PX - (SealData.CAP_PX - SealData.CAP_EDGE_PX) * sqrt(maxf(0.0, 1.0 - dx * dx))
				var skin := Rect2(Vector2(mid - half, dome_top), Vector2(half * 2.0, SealData.LIP_PX - dome_top))
				if box.grow(SealData.TOUCH_PX).intersects(skin) and float(_touch_cd.get(pid, 0.0)) <= 0.0:
					_touch(k, e, p, true)
		elif open_now:
			# Through the membrane, either way: a burst of purple.
			if _prev_y.has(pid) and float(_pass_cd.get(pid, 0.0)) <= 0.0:
				var y0: float = float(_prev_y[pid])
				if (y0 < 0.0) != (p.y < 0.0):
					for e in entries:
						if p.x >= e["x0"] - 4.0 and p.x <= e["x1"] + 4.0:
							_pass(k, e, p)
							break
		_prev_y[pid] = p.y
		if room.has_point(p):
			if open_now:
				if not _reported.has(pid):
					_reported[pid] = true
					events.append({"what": "entered", "pid": pid, "t": _time})
					ModLoaderLog.info("Lair seal: %s entered the lair" % pid, _Story.LOG)
					if Network.is_client():
						_StoryNet.lair_entered(pid)
					else:
						_EndGame.record_lair_entered(pid)
			elif not _inside_sealed.has(pid):
				# Only a dev route or a playtest gets here (a teleport).
				_inside_sealed[pid] = true
				ModLoaderLog.info("Lair seal: %s is inside the sealed lair (not by the seal); nothing starts" % pid, _Story.LOG)


# A keeper of ours touched the blue seal at local `p`.
func _touch(k, e: Dictionary, p: Vector2, tell: bool) -> void:
	var pid: String = k.playerId
	_touch_cd[pid] = SealData.TOUCH_EVERY
	touches += 1
	var mid := Vector2((e["x0"] + e["x1"]) * 0.5, -TILE * 0.5)
	var away: Vector2 = (p - mid).normalized() if p.distance_to(mid) > 0.5 else Vector2.UP
	var vert := Vector2.UP if p.y < -TILE * 0.5 else Vector2.DOWN
	var dir: Vector2 = (away * (1.0 - SealData.PUSH_UP) + vert * SealData.PUSH_UP).normalized()
	_push(k, dir * SealData.PUSH_SPEED)
	var at := Vector2(clampf(p.x, e["x0"], e["x1"]), clampf(p.y, -TILE - SealData.CAP_PX, SealData.LIP_PX))
	_crackle(e, at, 1.0, true)
	if tell:
		_StoryNet.seal_touch(entries.find(e), at)
	if touches == 1 or touches % 20 == 0:
		ModLoaderLog.info("Lair seal: threw %s back (%d)" % [pid, touches], _Story.LOG)


func _push(k, v: Vector2) -> void:
	if k.has_method("apply_forced_movement"):
		k.velocity = v
		k.apply_forced_movement(v * 4.0)
		return
	if "velocity" in k:
		k.velocity = v
	if "move" in k:
		k.move = v


func _pass(k, e: Dictionary, p: Vector2) -> void:
	_pass_cd[k.playerId] = SealData.PASS_EVERY
	passes += 1
	events.append({"what": "pass", "pid": k.playerId, "t": _time})
	var at := Vector2(clampf(p.x, e["x0"], e["x1"]), 0.0)
	_ripple(e, at, 1.0)
	for i in 16:
		var ang: float = _rng.randf() * TAU
		_sparks.append({"p": at + Vector2(_rng.randf_range(-6.0, 6.0), 0.0), "v": Vector2.from_angle(ang) * _rng.randf_range(30.0, 110.0),
			"t": 0.0, "life": _rng.randf_range(0.4, 0.8), "col": SealData.PURPLE_SPARK if i % 2 == 0 else SealData.PURPLE_LIGHT})
	_rings.append({"c": at, "t": 0.0, "life": 0.6, "r0": 4.0, "r1": 40.0, "col": SealData.PURPLE_LIGHT, "w": 1.0})
	_sound_at("seal_pass", to_global(at), -6.0, 1.0)


# Another peer's keeper touched the seal: the crackle, no throw.
func remote_touch(i: int, at: Vector2) -> void:
	if i < 0 or i >= entries.size():
		return
	remote_touches += 1
	if seen:
		_crackle(entries[i], at, 0.8, true)


func _on_crust_hit(c: Vector2i, dir: Vector2, local: bool) -> void:
	var col: int = c.x - chamber.position.x
	var e = null
	for x in entries:
		if col in x["cols"]:
			e = x
			break
	if e == null:
		return
	hits_refused += 1
	if hits_refused == 1:
		events.append({"what": "hit_refused", "t": _time})
		ModLoaderLog.info("Lair seal: a hit on the crust refused", _Story.LOG)
	if float(e["hit_cd"]) > 0.0:
		return
	e["hit_cd"] = SealData.HIT_FX_EVERY
	var centre := Vector2((float(col) + 0.5) * TILE, -TILE * 0.5)
	var d: Vector2 = dir.normalized() if dir.length() > 0.01 else Vector2.DOWN
	var at: Vector2 = centre - d * TILE * 0.5
	_crackle(e, at, 0.9, true)
	if not local:
		return
	# The keeper of ours that struck it (a drill, a punch, a sphere close by) is thrown back.
	var g: Vector2 = to_global(centre)
	for k in _Story.local_keepers():
		if k == null or not is_instance_valid(k) or k.disabled:
			continue
		if k.global_position.distance_to(g) < 46.0 and float(_touch_cd.get(k.playerId, 0.0)) <= 0.0:
			_touch(k, e, to_local(k.global_position), true)
			break


# --- feedback ------------------------------------------------------------------------

func _crackle(e: Dictionary, at: Vector2, strength: float, sound: bool) -> void:
	_bump = minf(1.0, _bump + 0.45 * strength)
	_ripple(e, at, strength)
	var mid := Vector2((e["x0"] + e["x1"]) * 0.5, -TILE * 0.4)
	for i in 3:
		var to: Vector2 = mid + Vector2(_rng.randf_range(-30.0, 30.0), _rng.randf_range(-22.0, 10.0))
		_add_arc(e, at, to, SealData.BLUE_SPARK if i == 0 else SealData.BLUE_LIGHT, SealData.ARC_LIFE)
	# One arc out to the toucher.
	_add_arc(e, at, at + (at - mid).normalized() * _rng.randf_range(10.0, 18.0) + Vector2(0, -4), SealData.BLUE_SPARK, SealData.ARC_LIFE)
	for i in 8:
		var ang: float = _rng.randf() * TAU
		_sparks.append({"p": at, "v": Vector2.from_angle(ang) * _rng.randf_range(40.0, 150.0) + Vector2(0, -30),
			"t": 0.0, "life": _rng.randf_range(0.25, 0.5), "col": SealData.BLUE_SPARK if i % 2 == 0 else SealData.BLUE_LIGHT})
	if sound:
		_sound_at("seal_zap", to_global(at), -5.0, _rng.randf_range(0.9, 1.15))


func _ripple(e: Dictionary, at: Vector2, s: float) -> void:
	var rips: Array = e["rips"]
	rips.push_front({"p": at, "t": 0.0, "s": s})
	while rips.size() > 4:
		rips.pop_back()


# A jagged arc of crackle from `a` to `b` (local).
func _add_arc(_e: Dictionary, a: Vector2, b: Vector2, col: Color, life: float) -> void:
	var pts := PackedVector2Array([a])
	var n: int = 5
	var normal: Vector2 = (b - a).orthogonal().normalized()
	for i in range(1, n):
		var t: float = float(i) / float(n)
		pts.append((a.lerp(b, t) + normal * _rng.randf_range(-5.0, 5.0)).round())
	pts.append(b.round())
	_arcs.append({"pts": pts, "t": 0.0, "life": life, "col": col})


func _step_fx(dt: float) -> void:
	_bump = maxf(0.0, _bump - dt * 2.5)
	for e in entries:
		e["hit_cd"] = float(e["hit_cd"]) - dt
		var rips: Array = e["rips"]
		for r in rips:
			r["t"] += dt
		while not rips.is_empty() and float(rips[-1]["t"]) > SealData.RIPPLE_LIFE:
			rips.pop_back()
		# Idle crackle over the blue slab.
		if (mode == "sealed" or mode == "pending") and _on_view:
			e["arc_cd"] = float(e["arc_cd"]) - dt
			if float(e["arc_cd"]) <= 0.0:
				e["arc_cd"] = _rng.randf_range(0.4, 1.6) * SealData.AMBIENT_ARC_EVERY
				var y: float = -TILE - _rng.randf_range(0.0, SealData.CAP_PX * 0.7)
				_add_arc(e, Vector2(e["x0"] + _rng.randf_range(0.0, 16.0), y), Vector2(e["x1"] - _rng.randf_range(0.0, 16.0), y + _rng.randf_range(-6.0, 6.0)), SealData.BLUE_LIGHT, 0.14)
				# And a spark drifting up off the dome.
				_sparks.append({"p": Vector2(lerpf(e["x0"], e["x1"], _rng.randf()), -TILE - SealData.CAP_PX * 0.6), "v": Vector2(_rng.randf_range(-8.0, 8.0), -_rng.randf_range(14.0, 30.0)),
					"t": 0.0, "life": _rng.randf_range(0.8, 1.4), "col": SealData.BLUE_LIGHT})
		elif mode == "opening" and _on_view and t_open < SealData.STRAIN_S:
			# The strain: arcs come thick and fast.
			e["arc_cd"] = float(e["arc_cd"]) - dt
			if float(e["arc_cd"]) <= 0.0:
				e["arc_cd"] = _rng.randf_range(0.03, 0.09)
				var c := Vector2((e["x0"] + e["x1"]) * 0.5, -TILE * 0.6)
				_add_arc(e, c + Vector2(_rng.randf_range(-24.0, 24.0), _rng.randf_range(-16.0, 6.0)), c + Vector2(_rng.randf_range(-50.0, 50.0), _rng.randf_range(-40.0, 12.0)), SealData.BLUE_SPARK, 0.12)
		elif mode == "open" and _on_view:
			e["arc_cd"] = float(e["arc_cd"]) - dt
			if float(e["arc_cd"]) <= 0.0:
				e["arc_cd"] = _rng.randf_range(0.5, 1.2)
				_sparks.append({"p": Vector2(lerpf(e["x0"], e["x1"], _rng.randf()), -1.0), "v": Vector2(_rng.randf_range(-6.0, 6.0), -_rng.randf_range(6.0, 16.0)),
					"t": 0.0, "life": _rng.randf_range(0.6, 1.0), "col": SealData.PURPLE_LIGHT})
	var i := 0
	while i < _arcs.size():
		_arcs[i]["t"] += dt
		if float(_arcs[i]["t"]) >= float(_arcs[i]["life"]):
			_arcs.remove_at(i)
		else:
			i += 1
	i = 0
	while i < _sparks.size():
		var s: Dictionary = _sparks[i]
		s["t"] += dt
		s["v"] *= 1.0 - 2.0 * dt
		s["p"] += s["v"] * dt
		if float(s["t"]) >= float(s["life"]):
			_sparks.remove_at(i)
		else:
			i += 1
	i = 0
	while i < _shards.size():
		var s: Dictionary = _shards[i]
		s["t"] += dt
		s["v"] += Vector2(0, 260.0) * dt
		s["v"] *= 1.0 - 1.2 * dt
		s["p"] += s["v"] * dt
		s["rot"] += s["rv"] * dt
		if float(s["t"]) >= float(s["life"]):
			_shards.remove_at(i)
		else:
			i += 1
	i = 0
	while i < _rings.size():
		_rings[i]["t"] += dt
		if float(_rings[i]["t"]) >= float(_rings[i]["life"]):
			_rings.remove_at(i)
		else:
			i += 1
	if _circuit_wave >= 0.0:
		_circuit_wave += dt * 260.0
		if _circuit_wave > chamber.size.x * TILE:
			_circuit_wave = -1.0


func _fx_empty() -> bool:
	return _arcs.is_empty() and _sparks.is_empty() and _shards.is_empty() and _rings.is_empty()


# Plays `name` if a keeper of ours is within earshot of `at` (global).
func _sound_at(sname: String, at: Vector2, db: float, pitch: float) -> void:
	var best: float = INF
	for k in _Story.local_keepers():
		if is_instance_valid(k):
			best = minf(best, k.global_position.distance_to(at))
	if best > SealData.HEAR_PX:
		return
	_Sfx.play(sname, db - 14.0 * (best / SealData.HEAR_PX), pitch)


func _update_hum() -> void:
	if _hum.stream == null:
		return
	var best: float = INF
	if mode == "sealed" and not GameWorld.paused:
		for k in _Story.local_keepers():
			if is_instance_valid(k):
				best = minf(best, k.global_position.distance_to(_centre_global()))
	if best > SealData.HUM_PX:
		if _hum.playing:
			_hum.volume_db = -80.0
			_hum.stop()
		return
	_hum.volume_db = SealData.HUM_DB - 18.0 * (best / SealData.HUM_PX)
	if not _hum.playing:
		_hum.play()


# --- drawing -------------------------------------------------------------------------

func _circuit_colour(x: float) -> Color:
	var open_share: float = float(_vis["tint"])
	if _circuit_wave >= 0.0:
		# The opening's wave runs out from the entries: violet behind it.
		var d: float = INF
		for e in entries:
			d = minf(d, absf(x - (e["x0"] + e["x1"]) * 0.5))
		open_share = 1.0 if d < _circuit_wave else 0.0
	return SealData.BLUE.lerp(SealData.PURPLE_DEEP, open_share)


# The circuit: a line of light along the roof, runes on it, pulses running out.
func _draw() -> void:
	var x_from: float = -SealData.CIRCUIT_TILES * TILE
	var x_to: float = (chamber.size.x + SealData.CIRCUIT_TILES) * TILE
	var y: float = -TILE - 1.0
	var dim: float = lerpf(1.0, 0.35, float(_vis["tint"]))
	# The line, in runs between the entries, a tile at a time (each its own
	# shade of the slow pulse, and its colour during the opening's wave).
	var x: float = x_from
	while x < x_to:
		var x1: float = minf(x + TILE, x_to)
		for e in entries:
			var a0: float = e["x0"] - SealData.OVERHANG_PX
			var a1: float = e["x1"] + SealData.OVERHANG_PX
			if x < a0 and x1 > a0:
				x1 = a0
			elif x >= a0 and x < a1:
				x1 = -1.0
				x = a1
				break
		if x1 > x:
			var pulse: float = 0.55 + 0.25 * sin(_time * 2.4 - x * 0.05)
			draw_rect(Rect2(Vector2(x, y), Vector2(x1 - x, 1)), Color(_circuit_colour(x + (x1 - x) * 0.5), pulse * dim))
			x = x1
	# Runes every few tiles.
	var step: float = SealData.CIRCUIT_RUNE_EVERY * TILE
	var rx: float = x_from + TILE * 0.5
	var i: int = 0
	while rx < x_to:
		var skip := false
		for e in entries:
			if rx >= e["x0"] - 6.0 and rx <= e["x1"] + 6.0:
				skip = true
		if not skip:
			var c: Color = _circuit_colour(rx).lerp(SealData.BLUE_LIGHT if _vis["tint"] < 0.5 else SealData.PURPLE, 0.5)
			var a: float = (0.55 + 0.45 * sin(_time * 1.7 + float(i) * 1.3)) * dim
			var o := Vector2(round(rx), y)
			draw_rect(Rect2(o + Vector2(-1, -3), Vector2(3, 1)), Color(c, a))
			draw_rect(Rect2(o + Vector2(0, -4), Vector2(1, 3)), Color(c, a))
			draw_rect(Rect2(o + Vector2(-2, -1), Vector2(1, 1)), Color(c, a * 0.7))
			draw_rect(Rect2(o + Vector2(2, -1), Vector2(1, 1)), Color(c, a * 0.7))
		rx += step
		i += 1
	# Pulses running out from the entries along it (sealed only).
	if mode == "sealed" or mode == "pending":
		for e in entries:
			for side in [-1.0, 1.0]:
				var start: float = e["x0"] - 4.0 if side < 0.0 else e["x1"] + 4.0
				var run: float = fposmod(_time * 46.0 + float(e["seed"]) * 30.0, 140.0)
				var px: float = start + side * run
				if px > x_from and px < x_to:
					draw_rect(Rect2(Vector2(round(px) - 2.0, y - 1.0), Vector2(4, 2)), Color(SealData.BLUE_SPARK, 0.8 * (1.0 - run / 140.0)))
	if _circuit_wave >= 0.0:
		for e in entries:
			for side in [-1.0, 1.0]:
				var px: float = (e["x0"] + e["x1"]) * 0.5 + side * _circuit_wave
				draw_rect(Rect2(Vector2(round(px) - 3.0, y - 2.0), Vector2(6, 3)), Color(SealData.PURPLE_SPARK, 0.9))


func _draw_fx() -> void:
	for a in _arcs:
		var k: float = 1.0 - float(a["t"]) / float(a["life"])
		var pts: PackedVector2Array = a["pts"]
		var col: Color = a["col"]
		if mode == "open":
			col = SealData.PURPLE_LIGHT
		for j in range(pts.size() - 1):
			_fx.draw_line(pts[j], pts[j + 1], Color(col, k), 1.0)
	for s in _sparks:
		var k: float = 1.0 - float(s["t"]) / float(s["life"])
		_fx.draw_rect(Rect2(Vector2(s["p"]).round(), Vector2(1, 1)), Color(s["col"], k))
	for s in _shards:
		var k: float = 1.0 - float(s["t"]) / float(s["life"])
		var sz: float = float(s["size"])
		var p: Vector2 = s["p"]
		var r: float = float(s["rot"])
		var tri := PackedVector2Array([p + Vector2.from_angle(r) * sz, p + Vector2.from_angle(r + 2.3) * sz * 0.7, p + Vector2.from_angle(r + 4.0) * sz * 0.8])
		_fx.draw_colored_polygon(tri, Color(SealData.BLUE_LIGHT.lerp(SealData.PURPLE_LIGHT, float(s["t"]) / float(s["life"])), 0.9 * k))
	for g in _rings:
		var t: float = float(g["t"])
		if t < 0.0:
			continue
		var u: float = t / float(g["life"])
		var r: float = lerpf(float(g["r0"]), float(g["r1"]), 1.0 - (1.0 - u) * (1.0 - u))
		_fx.draw_arc(g["c"], r, 0.0, TAU, 40, Color(g["col"], 0.85 * (1.0 - u)), float(g["w"]) * (1.0 - u) + 1.0)


func _draw_glow() -> void:
	var pulse: float = 0.8 + 0.2 * sin(_time * 2.6)
	var tint: float = float(_vis["tint"])
	var ph: float = float(_vis["phase"])
	var flash: float = float(_vis["flash"])
	for e in entries:
		var cx: float = (e["x0"] + e["x1"]) * 0.5
		var c := Vector2(cx, lerpf(-TILE * 0.6, 0.0, ph))
		var col: Color = SealData.BLUE.lerp(SealData.PURPLE, tint)
		var rx: float = lerpf(64.0, 46.0, ph)
		var ry: float = lerpf(48.0, 26.0, ph)
		var a: float = lerpf(0.42, 0.55, ph) * pulse + 0.3 * minf(1.0, _bump)
		_glow.draw_texture_rect(_glow_tex, Rect2(c - Vector2(rx, ry), Vector2(rx, ry) * 2.0), false, Color(col, a))
		_glow.draw_texture_rect(_glow_tex, Rect2(c - Vector2(rx, ry) * 0.5, Vector2(rx, ry)), false, Color(SealData.BLUE_LIGHT.lerp(SealData.PURPLE_LIGHT, tint), a * 0.6))
		if flash > 0.0:
			_glow.draw_texture_rect(_glow_tex, Rect2(c - Vector2(110, 80), Vector2(220, 160)), false, Color(1, 1, 1, 0.8 * flash))
	for s in _sparks:
		var k: float = 1.0 - float(s["t"]) / float(s["life"])
		_glow.draw_texture_rect(_glow_tex, Rect2(Vector2(s["p"]) - Vector2(3, 3), Vector2(6, 6)), false, Color(s["col"], 0.35 * k))


# For logs and playtests.
func state() -> Dictionary:
	return {"mode": mode, "blocking": blocking, "seen": seen, "open": is_open(), "touches": touches,
		"hits_refused": hits_refused, "passes": passes, "remote_touches": remote_touches, "vis": _vis.duplicate(), "t_open": t_open}
