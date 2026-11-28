extends Node2D

# The ship (#368, End game 2.0 map #363): a Halcyon Minerals pickup vessel.
# Values in data/ship.gd, placeholder art in endgame/ship_art.gd (#371 makes
# the real art).
#
#   In the ocean (before the last chain): background art. A third tentacle,
#   much bigger than the two climbable ones, comes up out of the deep lava
#   over the chamber's middle and is coiled twice round the ship, holding it
#   up out of the lava with its tip curled over the bridge. It sways slowly.
#   Nothing collides with it. Under the lava it soaks like the climbable
#   tentacles (endgame/ship_ocean.gdshader) and fades into the deep; above it,
#   a lava haze puts it behind them. Hidden until the player has seen the
#   ocean round it; drawn only while a view shows it.
#
#   At the last chain (EndGame.when_free): the last-chain cutscene (#367,
#   endgame/last_chain.gd) takes the ship over and sets it down by the dome.
#   Without it (no cutscene node), a placeholder: the coil drags the ship down
#   into the lava, the ground beside the dome cracks and the ship is pushed
#   up out of it, legs out. After a load or a late join it is simply at the dome.
#
#   At the dome: it stands on the ground on the dome's left (the station is on
#   every dome's right), nose to the dome, no collision, behind the monsters.
#   A boarding tube runs from its nose door to a hatch in the dome's glass.
#   A keeper in the dome at the hatch gets its focus (vanilla's highlight) and
#   a prompt, and boards by holding the use key (vanilla's hold). Boarding:
#     before the horror's body is dead ("" or "fight"): the escape, the doom
#       ending (Storymode.board_ship -> EndingDirector.play_doom);
#     its body dead, the chase and the final dome battle on ("chase",
#       "finale"): locked. The tube folds away, the hatch is red, and trying
#       it buzzes and the keeper says the locked line;
#     the final dome battle won ("won"): the way home, the saved ending.
#   Boarding plays a lift-off before the ending: the keeper goes through the
#   tube, the nose shuts, the engines light and the ship climbs out of sight,
#   with every nearby camera leaning after it.
#
# Online: every peer builds its own from the map facts and the end-game state
# (Data), so the ship's place and phase agree everywhere. Boarding is the
# host's: a client's keeper that holds the use key asks it
# (StoryNet.ship_board); the host checks the phase, stops play for everyone
# and sends the lift-off (Storymode._net_ship_lift), then plays the ending.
# Any keeper boarding ends the run for the whole team.
#
# The API for #367 (the last-chain cutscene sets the ship down by the dome):
#   Ship.find()                        the node (under the map, every peer)
#   Ship.is_landed() -> bool           it stands at the dome (boardable or locked)
#   Ship.dome_spot() -> Vector2        where it stands at the dome (global; its
#                                      centre, ship space origin), once the dome is up
#   ship.take_over()                   from your own EndGame.when_free(live) callback,
#                                      in the same frame: the placeholder move does
#                                      not run; the ship leaves the coil and shows as
#                                      `ship.carrier` where it hung in the ocean
#   ship.carrier                       a Node2D you move (global_position, rotation)
#                                      during the cutscene; ship.set_legs(0..1),
#                                      ship.set_visor(0..1), ship.set_scorched(bool)
#   ship.release_ocean(animated)       the coil lets go and sinks (or just goes)
#   ship.clip_to_ground(on)            hides what of the carrier is under the
#                                      ground beside the dome (#367's break-out)
#   ship.ground_y() -> float           the ground's height there (global)
#   ship.set_lights(on)                its windows and running lights
#   ship.land_now(live)                ends it where the cutscene set it down:
#                                      clean, lit, standing at the dome
#   ship.place_at_dome(animated)       ends it: the ship stands at the dome
#                                      (animated: the placeholder rise from the
#                                      ground; false: at once). Any peer, local.
#   ship.landed(live)                  signal, when it stands at the dome
#   ship.lifted_off(player_id)         signal, after the lift-off

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const EndGame = preload("res://mods-unpacked/flantor-StoryMode/endgame/end_game.gd")
static var _EndGame = EndGame  # calls go through this: lazy_preload makes const-preload calls slow
const ShipData = preload("res://mods-unpacked/flantor-StoryMode/data/ship.gd")
const ShipArt = preload("res://mods-unpacked/flantor-StoryMode/endgame/ship_art.gd")
static var _ShipArt = ShipArt  # calls go through this: lazy_preload makes const-preload calls slow
const Sfx = preload("res://mods-unpacked/flantor-StoryMode/boss/sfx.gd")
static var _Sfx = Sfx  # calls go through this: lazy_preload makes const-preload calls slow
const StoryNet = preload("res://mods-unpacked/flantor-StoryMode/net/story_net.gd")
static var _StoryNet = StoryNet  # calls go through this: lazy_preload makes const-preload calls slow
const Endings = preload("res://mods-unpacked/flantor-StoryMode/data/endings.gd")

const NAME := "StoryShip"
const T := 24.0
const SHADER := "res://mods-unpacked/flantor-StoryMode/endgame/ship_ocean.gdshader"
const AWAKE_KEY := "team1.story.awake"   # beats/awakening.gd AWAKE
const SEEN_EVERY := 0.5
const VIEW_EVERY := 0.2
# The coil's colours: the climbable tentacles' (map/tentacle_rig.gd), a step darker.
const COIL_DARK := Color(0.11, 0.05, 0.19)
const COIL_BODY := Color(0.29, 0.13, 0.45)
const COIL_LIGHT := Color(0.45, 0.26, 0.64)
const COIL_SUCKER := Color(0.66, 0.50, 0.80)

signal landed(live: bool)
signal lifted_off(player_id: String)
signal _lift_done

# Every moment so far, for playtests: [{"what", ...}].
static var events: Array = []

# ocean: in the coil; sinking: the placeholder's drag under; carried: #367 has
# it; rising: the placeholder's rise beside the dome; dome: standing there;
# lifting: lift-off; gone: flown.
var mode: String = "ocean"
var ocean: Node2D = null          # the coil and the ship it holds (sways)
var carrier: Node2D = null        # the ship anywhere but the ocean (#367 moves it)
var ocean_home: Vector2           # the held ship's centre at rest (this node's space)
var spot: Vector2                 # its centre standing at the dome (this node's space)
var hatch_at: Vector2             # the hatch in the dome's glass (this node's space)
var seen: bool = false
var on_view: bool = false
var tube_ext: float = 0.0         # 0 folded .. 1 out to the dome
var hold_share: float = 0.0       # the local keeper's hold, 0..1 (the prompt's ring)
var proc_us: int = 0              # time in _process so far (playtests' frame cost)

var _map = null
var _lava_y: float = 0.0
var _holder: Node2D = null        # inside `ocean`: ship space, tilted, bobbing
var _ocean_ship: Node2D = null    # where the held ship is (in the bake)
var _ocean_sprite: Sprite2D = null
var _baking: bool = false
var _body_tex: Dictionary = {}     # "clean" / "scorched" -> the ship's body, baked
var _body_baking: Dictionary = {}
var _tip_lines: Array = []
var _tip_w := PackedFloat32Array()
var _probe: Array = []
var _seen_acc: float = 0.0
var _view_acc: float = 0.0
var _t: float = 0.0
var _mat: ShaderMaterial = null
var _taken: bool = false
var _want_land: int = 0           # 1: snap to the dome once it is up, 2: animated
var _check_acc: float = 0.0
var _dome = null
var _ground_y: float = 0.0
var _wall_x: float = 0.0
var _hull: Node2D = null          # the carrier's drawing
var _lights: Node2D = null
var _plume: Node2D = null
var _clip: Control = null
var _tube: Node2D = null
var _hatch: Node2D = null
var _usable: Area2D = null
var _prompt: Node2D = null
var _fx: Node2D = null
var _legs: float = 1.0
var _visor: float = 0.0
var _scorched: bool = false
var _lights_on: bool = true
var _engine: float = 0.0
var _sink_t: float = -1.0
var _rise_t: float = -1.0
var _rise_live: bool = false
var _lift_t: float = -1.0
var _boarder: String = ""
var _boarder_fade: Array = []
var _cams: Dictionary = {}        # playerId -> lean applied
var _holds: Dictionary = {}       # playerId -> {"p": seconds held, "last": msec}
var _asked: float = -100.0
var _locked_cd: Dictionary = {}   # playerId -> seconds until the locked line may repeat
var _flash: float = 0.0           # the hatch's red flash
var _nudge: float = 0.0           # the prompt's "hold it" nudge
var _dust: Array = []             # [pos, vel, life, max, r]
var _rng := RandomNumberGenerator.new()
var _last_phase: String = ""
var _focus_local: bool = false
var _line: Node2D = null


static func find():
	if Level.map == null or not is_instance_valid(Level.map):
		return null
	return Level.map.get_node_or_null(NAME)


static func is_landed() -> bool:
	var n = find()
	return n != null and n.mode == "dome"


# Where the ship stands at the dome (global), or Vector2.INF before the dome is up.
static func dome_spot() -> Vector2:
	var n = find()
	if n == null or not n._dome_geo():
		return Vector2.INF
	return n.to_global(n.spot)


# The run's end-game state says the ship is out of the ocean: the last chain is
# broken (or the horror woke by an older route).
static func should_be_landed() -> bool:
	return _EndGame.is_free() or bool(Data.ofOr(AWAKE_KEY, false)) or str(Data.ofOr(Story.BOSS_STATE, "")) != ""


# away (not at the dome), escape (boarding plays the doom ending), locked,
# home (boarding plays the saved ending), gone (an ending plays or it flew).
static func phase() -> String:
	var n = find()
	if n == null:
		return "away"
	if n.mode == "lifting" or n.mode == "gone":
		return "gone"
	if n.mode != "dome":
		return "away"
	if Level.mode != null and Level.mode.has_method("is_ending") and Level.mode.is_ending():
		return "gone"
	match str(Data.ofOr(Story.BOSS_STATE, "")):
		"chase", "finale":
			return "locked"
		"won":
			return "home"
		"lost":
			return "gone"
	return "escape"


# What boarding plays now: "doom", "saved", or "" (it can't be boarded).
static func board_kind() -> String:
	match phase():
		"escape":
			return "doom"
		"home":
			return "saved"
	return ""


# --- setup ------------------------------------------------------------------------

func setup(map) -> bool:
	var td = map.tileData
	var om: Dictionary = td.get_meta("story_ocean", {})
	if om.is_empty() or not td.has_meta("story_boss_chamber"):
		return false
	_map = map
	name = NAME
	z_index = 7          # over the lava (6) and its glow; the anchors and the climbable tentacles (7) come after us in the tree
	_rng.seed = hash([Level.levelSeed, "ship"])
	var ch: Rect2i = td.get_meta("story_boss_chamber")
	var top: int = int(om["top"])
	_lava_y = map.getTilePos(Vector2(0, top)).y - T * 0.5
	var x_mid: float = map.getTilePos(Vector2(ch.position.x, top)).x - T * 0.5 + float(ch.size.x) * T * 0.5
	ocean_home = Vector2(x_mid, _lava_y - ShipData.OCEAN_LIFT_PX)
	_build_ocean()
	_build_carrier()
	_build_dome_parts()
	# Seen once the ocean's air band round it is in sight.
	var cx: int = int(floor(x_mid / T))
	for y in range(int(om["ceiling"]) + 1, top + 3):
		for x in range(cx - 7, cx + 8):
			_probe.append(Vector2(x, y))
	if should_be_landed():
		_go_ashore(false)
	else:
		_EndGame.when_free(_on_free)
	ModLoaderLog.info("Ship: %s (ocean at %s)" % [mode if _want_land == 0 else "to the dome", str(ocean_home.round())], _Story.LOG)
	return true


func _build_ocean() -> void:
	ocean = Node2D.new()
	ocean.name = "Ocean"
	ocean.position = ocean_home + ShipData.SWAY_PIVOT
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER)
	_mat.set_shader_parameter("lava_y", 0.0)
	_mat.set_shader_parameter("soak_px", ShipData.SOAK_PX)
	_mat.set_shader_parameter("fade_from", ShipData.FADE_FROM)
	_mat.set_shader_parameter("fade_to", ShipData.FADE_TO)
	_mat.set_shader_parameter("depth_tint", ShipData.DEPTH_TINT)
	_mat.set_shader_parameter("depth_mix", ShipData.DEPTH_MIX)
	ocean.material = _mat
	ocean.visible = false
	add_child(ocean)
	_holder = Node2D.new()
	_holder.name = "Holder"
	_holder.use_parent_material = true
	_holder.position = -ShipData.SWAY_PIVOT
	_holder.rotation = ShipData.OCEAN_TILT
	ocean.add_child(_holder)
	# The coil and the ship it holds never change shape: baked into one texture
	# the first time it is seen (_bake_ocean), drawn in one go.
	_ocean_sprite = Sprite2D.new()
	_ocean_sprite.name = "Baked"
	_ocean_sprite.centered = false
	_ocean_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ocean_sprite.use_parent_material = true
	_holder.add_child(_ocean_sprite)
	# Where the held ship is (no drawing of its own: it is in the bake).
	_ocean_ship = Node2D.new()
	_ocean_ship.name = "HeldShip"
	_holder.add_child(_ocean_ship)
	# The free tip, waving: drawn live.
	var tip := {"pts": PackedVector2Array(ShipArt.TIP), "widths": _tip_widths(), "front": false}
	_tip_lines = _coil_lines(tip, true)
	for l in _tip_lines:
		_holder.add_child(l)


# Bakes the coil (behind the ship, the ship, in front of it) into one texture.
func _bake_ocean(with_ship: bool = true) -> void:
	if _baking or (_ocean_sprite.texture != null and with_ship):
		return
	_baking = true
	var pieces: Array = _ShipArt.coil_pieces(6.0)
	var nodes: Array = []
	var box := ShipArt.BODY_RECT.grow(4.0)
	for p in pieces:
		var ws: PackedFloat32Array = p["widths"]
		var i: int = 0
		for q: Vector2 in p["pts"]:
			var r: float = ws[i] * 0.5 + 4.0
			box = box.expand(q + Vector2(r, r)).expand(q - Vector2(r, r))
			i += 1
	box = Rect2(box.position.floor(), box.size.ceil())
	for p in pieces:
		if not p["front"]:
			nodes.append_array(_coil_lines(p, false))
	if with_ship:
		var held := Node2D.new()
		held.draw.connect(func(): _ShipArt.draw_ship(held, 0.15, 0.0, false, true, true))
		nodes.append(held)
	for p in pieces:
		if p["front"]:
			nodes.append_array(_coil_lines(p, false))
	var tex: ImageTexture = await _bake(box, nodes)
	_baking = false
	if tex == null or not is_instance_valid(_ocean_sprite):
		return
	_ocean_sprite.texture = tex
	_ocean_sprite.offset = box.position
	_ocean_sprite.visible = true
	events.append({"what": "baked", "ship": with_ship, "size": [tex.get_width(), tex.get_height()]})


# Draws `nodes` (ship space) into a texture of `box` once, off screen.
func _bake(box: Rect2, nodes: Array) -> ImageTexture:
	var vp := SubViewport.new()
	vp.name = "Bake"
	vp.size = Vector2i(int(box.size.x), int(box.size.y))
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var root := Node2D.new()
	root.position = -box.position
	vp.add_child(root)
	for n in nodes:
		root.add_child(n)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(vp):
		return null
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


func _body_texture(scorched: bool) -> void:
	var key: String = "scorched" if scorched else "clean"
	if _body_tex.has(key) or _body_baking.has(key):
		return
	_body_baking[key] = true
	var n := Node2D.new()
	n.draw.connect(func(): _ShipArt.draw_body(n, true, scorched))
	var tex: ImageTexture = await _bake(ShipArt.BODY_RECT, [n])
	_body_baking.erase(key)
	if tex != null:
		_body_tex[key] = tex
		if _hull != null and _hull.scorched == scorched:
			_hull.body_tex = tex
			_hull.queue_redraw()


# One run of the coil: a hot-rim marker, an outline, the body and a light
# stripe, each a Line2D with the run's taper; suckers along a front run.
# `live`: drawn in the ocean (the tip; the ocean's shader), else for the bake.
func _coil_lines(p: Dictionary, live: bool) -> Array:
	var pts: PackedVector2Array = p["pts"]
	var ws: PackedFloat32Array = p["widths"]
	var wmax: float = 1.0
	for w in ws:
		wmax = maxf(wmax, w)
	var curve := Curve.new()
	var total: float = 0.0
	var acc := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
		acc.append(total)
	for i in pts.size():
		curve.add_point(Vector2(acc[i] / maxf(total, 1.0), ws[i] / wmax))
	var lines: Array = []
	for layer in [["rim", ShipArt.RIM_KEY, 5.0], ["edge", COIL_DARK, 3.0], ["body", COIL_BODY, 0.0], ["light", COIL_LIGHT, -1.0]]:
		var l := Line2D.new()
		l.name = "Coil_" + str(layer[0])
		l.points = pts if layer[0] != "light" else _side(pts, ws, -0.24)
		l.width = wmax + float(layer[2]) if layer[0] != "light" else wmax * 0.2
		l.width_curve = curve
		l.default_color = layer[1]
		l.joint_mode = Line2D.LINE_JOINT_ROUND
		l.begin_cap_mode = Line2D.LINE_CAP_ROUND
		l.end_cap_mode = Line2D.LINE_CAP_ROUND
		l.round_precision = 4
		l.antialiased = false
		l.use_parent_material = live
		lines.append(l)
	if p["front"]:
		var s := _Suckers.new()
		s.pts = pts
		s.widths = ws
		s.use_parent_material = live
		lines.append(s)
	return lines


static func _side(pts: PackedVector2Array, ws: PackedFloat32Array, share: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in pts.size():
		var a: Vector2 = pts[maxi(i - 1, 0)]
		var b: Vector2 = pts[mini(i + 1, pts.size() - 1)]
		var n: Vector2 = (b - a).normalized().orthogonal()
		out.append(pts[i] + n * ws[i] * share)
	return out


func _build_carrier() -> void:
	# A clip that hides the ship's part under the ground while it rises out of
	# it (the placeholder); off otherwise, so #367 can carry it anywhere.
	_clip = Control.new()
	_clip.name = "Clip"
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.clip_contents = false
	_clip.z_as_relative = false
	_clip.z_index = 0
	add_child(_clip)
	carrier = Node2D.new()
	carrier.name = "Carrier"
	carrier.visible = false
	_clip.add_child(carrier)
	_hull = _ShipBody.new()
	_hull.name = "Hull"
	_hull.modulate = ShipData.DOME_TINT
	carrier.add_child(_hull)
	_lights = _Lights.new()
	_lights.name = "Lights"
	_lights.ship = self
	carrier.add_child(_lights)
	_plume = _Plume.new()
	_plume.name = "Plume"
	_plume.ship = self
	carrier.add_child(_plume)
	carrier.move_child(_plume, 0)


func _build_dome_parts() -> void:
	_tube = _Tube.new()
	_tube.name = "Tube"
	_tube.modulate = ShipData.DOME_TINT
	_tube.ship = self
	_tube.z_as_relative = false
	_tube.z_index = 1
	_tube.visible = false
	add_child(_tube)
	_hatch = _Hatch.new()
	_hatch.name = "Hatch"
	_hatch.ship = self
	_hatch.z_as_relative = false
	_hatch.z_index = 61
	_hatch.visible = false
	add_child(_hatch)
	_usable = load("res://content/shared/Usable.tscn").instantiate()
	_usable.name = "Usable"
	_hatch.add_child(_usable)
	_usable.monitorable = false
	_prompt = _Prompt.new()
	_prompt.name = "Prompt"
	_prompt.ship = self
	_prompt.z_as_relative = false
	_prompt.z_index = 62
	_prompt.visible = false
	add_child(_prompt)
	_fx = _Fx.new()
	_fx.name = "Fx"
	_fx.ship = self
	_fx.z_as_relative = false
	_fx.z_index = 2
	add_child(_fx)


# The dome's geometry, once it is up: the ground, the glass on our side at
# hatch height, the hatch and where the ship stands.
func _dome_geo() -> bool:
	var d = Level.getDome("team1")
	if d == null or not is_instance_valid(d) or not d.is_inside_tree() or not is_inside_tree():
		return false
	if d == _dome:
		return true
	_dome = d
	var dp: Vector2 = to_local(d.global_position)
	var y: float = -ShipData.HATCH_UP_PX
	var wall: float = -66.0
	var shape = d.get_node_or_null("DomeBorder/DomeShape")
	if shape is CollisionPolygon2D:
		var poly: PackedVector2Array = shape.polygon
		var best: float = -INF
		for i in poly.size():
			var a: Vector2 = poly[i] + shape.position
			var b: Vector2 = poly[(i + 1) % poly.size()] + shape.position
			if a.y == b.y or (a.y - y) * (b.y - y) > 0.0:
				continue
			var x: float = lerpf(a.x, b.x, (y - a.y) / (b.y - a.y))
			if x < 0.0 and x > best:
				best = x
		if best > -INF:
			wall = best
	_ground_y = dp.y + 2.0
	_wall_x = dp.x + wall
	hatch_at = Vector2(_wall_x, _ground_y - ShipData.HATCH_UP_PX)
	spot = Vector2(_wall_x - ShipData.TUBE_GAP_PX - ShipArt.DOOR.x, _ground_y - ShipArt.FOOT_Y)
	_hatch.position = hatch_at
	_usable.position = Vector2(8.0, 0.0)
	_prompt.position = hatch_at + Vector2(14.0, -30.0)
	ModLoaderLog.info("Ship: the dome's glass at x %.0f, the ship stands at %s" % [wall, str(spot.round())], _Story.LOG)
	return true


# --- the last chain ----------------------------------------------------------------

func _on_free(live: bool) -> void:
	if mode != "ocean":
		return
	if not live:
		_go_ashore(false)
		return
	events.append({"what": "free_live", "t": _t})
	# One frame for #367 to take_over() from its own callback.
	_start_placeholder.call_deferred()


func _start_placeholder() -> void:
	if _taken or mode != "ocean":
		return
	ModLoaderLog.info("Ship: the last chain: the placeholder move", _Story.LOG)
	release_ocean(true)
	_want_land = 2
	_check_acc = -ShipData.LAND_DELAY_S


# #367: the cutscene moves the ship itself. Call it in the same frame as the
# last chain (from an EndGame.when_free(live) callback). The ship leaves the
# coil and shows as `carrier` where it hung; the coil keeps hold of nothing
# until release_ocean().
func take_over() -> void:
	if mode == "dome" or mode == "lifting" or mode == "gone":
		return
	_taken = true
	_want_land = 0
	# The coil without the ship: baked again (two frames); hidden till then.
	_ocean_sprite.visible = false
	_bake_ocean(false)
	mode = "carried"
	_clip.clip_contents = false
	carrier.visible = true
	carrier.global_position = _ocean_ship.global_position
	carrier.rotation = _ocean_ship.global_rotation
	set_legs(0.15)
	set_scorched(true)
	_lights_on = false
	_hull.lights = false
	_hull.queue_redraw()
	events.append({"what": "taken"})


# The coil lets go: it sinks into the deep lava (animated) or just goes.
func release_ocean(animated: bool) -> void:
	if ocean == null or not ocean.visible and not animated:
		if ocean != null:
			ocean.visible = false
		_sink_t = -1.0
		if mode == "ocean":
			mode = "away"
		return
	if animated:
		_sink_t = 0.0
		if mode == "ocean":
			mode = "sinking"
	else:
		ocean.visible = false
		_sink_t = -1.0
		if mode == "ocean" or mode == "sinking":
			mode = "away"


# The ship stands at the dome. Animated: the placeholder rise out of the ground
# beside the dome; else at once (a load, a late join, after #367's cutscene).
func place_at_dome(animated: bool) -> void:
	if mode == "dome" or mode == "lifting" or mode == "gone":
		return
	if not _dome_geo():
		_want_land = 2 if animated else 1
		return
	_want_land = 0
	if mode == "ocean":
		release_ocean(false)
	carrier.visible = true
	carrier.position = spot
	carrier.rotation = 0.0
	set_scorched(false)
	_lights_on = true
	_hull.lights = true
	_hull.queue_redraw()
	if animated:
		mode = "rising"
		_rise_t = 0.0
		_rise_live = true
		_clip.clip_contents = true
		_clip.position = Vector2(spot.x - 400.0, _ground_y - 2400.0)
		_clip.size = Vector2(800.0, 2400.0 + 1.0)
		carrier.position = spot - _clip.position + Vector2(0, ShipData.DOME_RISE_FROM_PX)
		set_legs(0.0)
		_Sfx.play("grow", -2.0, 0.7)
		_Sfx.play("boom", -6.0, 0.6)
		_shake_near(10.0, 0.8)
		_burst(Vector2(spot.x, _ground_y), 26, 1.4)
		events.append({"what": "rise", "t": _t})
	else:
		_land(false)


# #367: the cutscene has set the ship down at the dome itself; it stands there
# from now on (`live`: the landed signal says it was live).
func land_now(live: bool) -> void:
	if mode == "dome" or mode == "lifting" or mode == "gone" or not _dome_geo():
		return
	_want_land = 0
	_sink_t = -1.0
	if ocean != null:
		ocean.visible = false
	carrier.visible = true
	set_scorched(false)
	set_lights(true)
	_land(live)


# #367: hides what of the carrier is under the ground beside the dome (the
# ship and anything the cutscene hangs on it), or stops hiding it.
func clip_to_ground(on: bool) -> void:
	if not _dome_geo():
		return
	var at: Vector2 = carrier.global_position
	_clip.clip_contents = on
	if on:
		_clip.position = Vector2(spot.x - 1400.0, _ground_y - 3200.0)
		_clip.size = Vector2(2800.0, 3200.0)
	else:
		_clip.position = Vector2.ZERO
		_clip.size = Vector2.ZERO
	carrier.global_position = at


# The ground's height beside the dome (global y), INF before the dome is up.
func ground_y() -> float:
	if not _dome_geo():
		return INF
	return to_global(Vector2(0, _ground_y)).y


func set_lights(on: bool) -> void:
	_lights_on = on
	if _hull != null and _hull.lights != on:
		_hull.lights = on
		_hull.queue_redraw()
	if _lights != null:
		_lights.queue_redraw()


func _land(live: bool) -> void:
	_clip.clip_contents = false
	_clip.position = Vector2.ZERO
	carrier.position = spot
	carrier.rotation = 0.0
	set_legs(1.0)
	mode = "dome"
	_rise_t = -1.0
	tube_ext = 0.0
	_visor = 0.0
	_hull.visor = 0.0
	_hull.queue_redraw()
	_tube.visible = true
	_hatch.visible = true
	events.append({"what": "landed", "live": live, "t": _t})
	ModLoaderLog.info("Ship: at the dome (%s)" % ("live" if live else "placed"), _Story.LOG)
	landed.emit(live)


func _go_ashore(live: bool) -> void:
	if ocean != null:
		ocean.visible = false
	_want_land = 2 if live else 1
	mode = "away"
	place_at_dome(live)


func set_legs(f: float) -> void:
	_legs = clampf(f, 0.0, 1.0)
	if _hull != null and not is_equal_approx(_hull.legs, _legs):
		_hull.legs = _legs
		_hull.queue_redraw()


func set_visor(f: float) -> void:
	_visor = clampf(f, 0.0, 1.0)
	if _hull != null and not is_equal_approx(_hull.visor, _visor):
		_hull.visor = _visor
		_hull.queue_redraw()


func set_scorched(on: bool) -> void:
	_scorched = on
	if _hull != null and _hull.scorched != on:
		_hull.scorched = on
		_hull.body_tex = _body_tex.get("scorched" if on else "clean", null)
		_hull.queue_redraw()
	if is_inside_tree():
		_body_texture(on)


# --- every frame --------------------------------------------------------------------

func _process(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	_process_all(delta)
	proc_us += Time.get_ticks_usec() - t0


func _process_all(delta: float) -> void:
	_t += delta
	_check_acc += delta
	if _check_acc >= 0.5:
		_check_acc = 0.0
		if _want_land != 0:
			place_at_dome(_want_land == 2)
		elif (mode == "ocean") and not _taken and should_be_landed():
			# The state moved on without a live moment here (a dev route).
			_go_ashore(false)
	if ocean != null and (mode == "ocean" or mode == "sinking" or mode == "carried" or _sink_t >= 0.0):
		_process_ocean(delta)
	if mode == "rising":
		_process_rise(delta)
	if mode == "dome":
		_process_dome(delta)
	if mode == "lifting":
		_process_lift(delta)
	_process_dust(delta)


func _process_ocean(delta: float) -> void:
	if not seen:
		_seen_acc += delta
		if _seen_acc >= SEEN_EVERY:
			_seen_acc = 0.0
			var vis: Dictionary = Level.map.visibleTileCoords
			for c in _probe:
				if vis.has(c):
					seen = true
					break
	_view_acc += delta
	if _view_acc >= VIEW_EVERY:
		_view_acc = 0.0
		var r := Rect2(to_global(ocean_home) - Vector2(220, 140), Vector2(440, 520))
		on_view = false
		for v: Rect2 in _Story.view_rects(T):
			if v.intersects(r):
				on_view = true
				break
	if seen and on_view and _ocean_sprite.texture == null:
		_bake_ocean()
	var show: bool = seen and on_view and _ocean_sprite.texture != null and (mode != "sinking" or _sink_t >= 0.0)
	if ocean.visible != show and mode != "carried":
		ocean.visible = show
	if not ocean.visible:
		if _sink_t >= 0.0:
			_sink_t += delta
			if _sink_t >= ShipData.OCEAN_SINK_S:
				release_ocean(false)
		return
	_mat.set_shader_parameter("lava_y", to_global(Vector2(0, _lava_y)).y)
	# The sway round the deep pivot, a slow bob, the grip's squeeze.
	var sway: float = sin(_t * ShipData.SWAY_SPEED) * ShipData.SWAY_ANGLE + sin(_t * ShipData.SWAY_SPEED * 2.3 + 1.1) * ShipData.SWAY_ANGLE * 0.3
	var bob: float = sin(_t * ShipData.BOB_SPEED) * ShipData.BOB_PX
	ocean.rotation = sway
	var sink: float = 0.0
	var fade: float = 1.0
	if _sink_t >= 0.0:
		_sink_t += delta
		var u: float = clampf(_sink_t / ShipData.OCEAN_SINK_S, 0.0, 1.0)
		sink = 300.0 * u * u
		fade = 1.0 - smoothstep(0.55, 1.0, u)
		ocean.rotation += sin(_sink_t * 9.0) * 0.01 * (1.0 - u)
		if _sink_t >= ShipData.OCEAN_SINK_S:
			release_ocean(false)
			return
	_mat.set_shader_parameter("fade_all", fade)
	_holder.position = -ShipData.SWAY_PIVOT + Vector2(0, bob + sink)
	var sq: float = 1.0 + 0.015 * sin(_t * ShipData.SQUEEZE_SPEED)
	_holder.scale = Vector2(1.0, sq)
	# The tip curls.
	var pts := PackedVector2Array()
	for i in ShipArt.TIP.size():
		var p: Vector2 = ShipArt.TIP[i]
		var k: float = float(i) / float(ShipArt.TIP.size() - 1)
		p += Vector2(sin(_t * 0.8 + float(i) * 0.9), cos(_t * 0.6 + float(i) * 1.1)) * (k * k * 6.0)
		pts.append(p)
	for l in _tip_lines:
		if l is Line2D:
			l.points = pts if l.name != "Coil_light" else _side(pts, _tip_widths(), -0.24)


func _tip_widths() -> PackedFloat32Array:
	if _tip_w.is_empty():
		for s in ShipArt.TIP_SHARE:
			_tip_w.append(_ShipArt.width_at(float(s)))
	return _tip_w


func _process_rise(delta: float) -> void:
	_rise_t += delta
	var u: float = clampf(_rise_t / ShipData.DOME_RISE_S, 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - u, 3.0)
	var wobble: float = sin(_rise_t * 14.0) * 1.5 * (1.0 - u)
	carrier.position = spot - _clip.position + Vector2(wobble, ShipData.DOME_RISE_FROM_PX * (1.0 - e))
	carrier.rotation = sin(_rise_t * 5.0) * 0.03 * (1.0 - u)
	if _rng.randf() < delta * 30.0 * (1.0 - u):
		_burst(Vector2(spot.x + _rng.randf_range(-140, 140), _ground_y), 1, 0.9)
	set_legs(smoothstep(0.75, 1.0, u))
	if u >= 1.0:
		_Sfx.play("ship_land", -4.0, 0.8)
		_shake_near(8.0, 0.5)
		_burst(Vector2(spot.x - 94.0, _ground_y), 8, 0.8)
		_burst(Vector2(spot.x + 66.0, _ground_y), 8, 0.8)
		_land(true)


# At the dome: the tube, the hatch and the prompt follow the phase; a local
# keeper at the hatch gets its focus; holds count up to boarding.
func _process_dome(delta: float) -> void:
	_dome_geo()
	var ph: String = phase()
	if ph != _last_phase:
		if _last_phase != "" and ph == "home":
			_Sfx.play("ship_ready", -4.0, 0.9)
			_Sfx.play("ship_door_open", -6.0, 1.0)
		elif _last_phase == "escape" and ph == "locked":
			_Sfx.play("ship_door_close", -6.0, 0.9)
		events.append({"what": "phase", "phase": ph, "t": _t})
		_last_phase = ph
	var open: bool = ph == "escape" or ph == "home"
	tube_ext = move_toward(tube_ext, 1.0 if open else 0.0, delta / 0.6)
	set_visor(tube_ext)
	_flash = maxf(0.0, _flash - delta * 2.0)
	_nudge = maxf(0.0, _nudge - delta * 2.5)
	for pid in _locked_cd.keys():
		_locked_cd[pid] = float(_locked_cd[pid]) - delta
	_usable.monitorable = ph == "escape" or ph == "home" or ph == "locked"
	_steal_focus()
	_tick_holds(delta)
	_tube.queue_redraw()
	_hatch.queue_redraw()
	_prompt.visible = _focus_local
	if _prompt.visible:
		_prompt.queue_redraw()
	_lights.tick(delta)


# The hatch wins the use key over anything else a keeper at the glass could
# use (a dome gadget's station, say): vanilla gives focus to whichever usable
# came into reach first and keeps it.
func _steal_focus() -> void:
	_focus_local = false
	for k in _Story.local_keepers():
		if k == null or not is_instance_valid(k):
			continue
		if not can_focus(k):
			continue
		_focus_local = true
		if k.focussedUsable == _usable or not k.usables.has(_usable):
			continue
		if k.focussedUsable != null and is_instance_valid(k.focussedUsable):
			k.focussedUsable.unfocusUse(k)
		k.focussedUsable = _usable
		_usable.focusUse(k)


func can_focus(k) -> bool:
	if mode != "dome" or k == null or not is_instance_valid(k) or k.disabled or k.isInsideStation:
		return false
	var ph: String = phase()
	if ph != "escape" and ph != "home" and ph != "locked":
		return false
	if not k.isInsideDome:
		return false
	var p: Vector2 = to_local(k.global_position)
	return absf(p.x - hatch_at.x) <= ShipData.HATCH_REACH_PX and absf(p.y - hatch_at.y) <= 20.0


func _tick_holds(delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	hold_share = 0.0
	for pid in _holds.keys():
		var h: Dictionary = _holds[pid]
		if now - int(h["last"]) > 350:
			_holds.erase(pid)
			continue
		h["p"] = float(h["p"]) + delta
		hold_share = maxf(hold_share, clampf(float(h["p"]) / ShipData.BOARD_HOLD_S, 0.0, 1.0))
		if float(h["p"]) >= ShipData.BOARD_HOLD_S:
			_holds.erase(pid)
			request_board(pid)


# The hatch's use (from its Usable): a tap nudges the prompt, a hold boards.
func use_hit(k) -> bool:
	if not can_focus(k):
		return false
	if phase() == "locked":
		_locked(k)
	else:
		_nudge = 1.0
	return true


func use_hold(k) -> bool:
	if not can_focus(k):
		return false
	if phase() == "locked":
		_locked(k)
		return true
	var h: Dictionary = _holds.get(k.playerId, {})
	var now: int = Time.get_ticks_msec()
	if h.is_empty() or now - int(h["last"]) > 350:
		h = {"p": 0.3, "last": now}     # vanilla's hold starts after 0.3 s
	h["last"] = now
	_holds[k.playerId] = h
	return true


func _locked(k) -> void:
	_flash = 1.0
	if float(_locked_cd.get(k.playerId, 0.0)) > 0.0:
		return
	_locked_cd[k.playerId] = ShipData.LOCKED_LINE_EVERY
	_Sfx.play("ship_denied", -4.0, 0.8)
	events.append({"what": "locked", "player": k.playerId, "t": _t})
	_say(k, Endings.SHIP_LOCKED)


# A keeper of this instance boards: the host decides (Storymode.board_ship).
func request_board(pid: String) -> void:
	if _t - _asked < 2.0:
		return
	_asked = _t
	events.append({"what": "board_asked", "player": pid, "t": _t})
	ModLoaderLog.info("Ship: %s boards" % pid, _Story.LOG)
	if Network.is_client():
		_StoryNet.ship_board(pid)
	elif Level.mode != null and Level.mode.has_method("board_ship"):
		Level.mode.board_ship(pid)


# --- lift-off ------------------------------------------------------------------------

# Every peer (the host's Storymode calls it, and sends it to the clients).
# Awaitable: returns once the ship has climbed out of sight.
func lift_off(pid: String) -> void:
	if mode == "lifting" or mode == "gone":
		return
	if mode != "dome":
		place_at_dome(false)
		if mode != "dome":
			return
	mode = "lifting"
	_lift_t = 0.0
	_boarder = pid
	_prompt.visible = false
	_holds.clear()
	tube_ext = 1.0
	set_visor(1.0)
	events.append({"what": "lift_off", "player": pid, "t": _t})
	ModLoaderLog.info("Ship: lift-off (%s aboard)" % pid, _Story.LOG)
	var k = Keepers.getKeeper(pid) if Keepers.hasKeeper(pid) else null
	_boarder_fade = [k] if k != null and is_instance_valid(k) else []
	await _lift_done


func _process_lift(delta: float) -> void:
	_lift_t += delta
	var t0: float = ShipData.WALK_S
	var t1: float = t0 + ShipData.SHUT_S
	var t2: float = t1 + ShipData.SPOOL_S
	var t3: float = t2 + ShipData.CLIMB_S
	var t: float = _lift_t
	# The keeper steps into the hatch and fades.
	for k in _boarder_fade:
		if is_instance_valid(k):
			k.modulate.a = 1.0 - clampf(t / (t0 * 0.6), 0.0, 1.0)
	# The nose shuts and the tube folds away.
	if t >= t0 and t - delta < t0:
		_Sfx.play("ship_door_close", -3.0, 0.9)
	tube_ext = 1.0 - clampf((t - t0) / ShipData.SHUT_S, 0.0, 1.0)
	set_visor(tube_ext)
	# The engines light.
	if t >= t1 and t - delta < t1:
		_Sfx.play("ship_liftoff", 0.0, 1.0)
	_engine = clampf((t - t1) / ShipData.SPOOL_S, 0.0, 1.0)
	# The climb: slow off the ground, nose up, then away.
	var u: float = clampf((t - t2) / ShipData.CLIMB_S, 0.0, 1.0)
	var h: float = ShipData.CLIMB_PX * pow(u, 2.2)
	var drift: float = -160.0 * pow(u, 2.5)
	carrier.position = spot + Vector2(drift, -h)
	carrier.rotation = -0.42 * smoothstep(0.15, 0.7, u)
	set_legs(1.0 - clampf((t - t2) / 0.6, 0.0, 1.0))
	# Dust under it while it is low; a shake that grows and fades.
	var low: float = 1.0 - clampf(h / 160.0, 0.0, 1.0)
	if t >= t1 and _rng.randf() < delta * 40.0 * low * _engine:
		_burst(Vector2(spot.x + _rng.randf_range(-130, 110), _ground_y), 1, 1.2)
	if t >= t1 and int(t * 10.0) != int((t - delta) * 10.0):
		_shake_near(ShipData.SHAKE * _engine * maxf(low, 0.25), 0.25)
	_lean_cams(t, t3)
	_lights.tick(delta)
	_plume.queue_redraw()
	_tube.queue_redraw()
	_hatch.queue_redraw()
	if t >= t3:
		mode = "gone"
		carrier.visible = false
		_engine = 0.0
		_tube.visible = false
		_hatch.visible = false
		_lean_cams(t3 + 10.0, t3)
		events.append({"what": "gone", "t": _t})
		lifted_off.emit(_boarder)
		_lift_done.emit()


# Every local keeper near the dome watches it go: its camera leans toward the
# ship and comes back for the ending. In the dome vanilla's camera rests on a
# point of its own (cameraRestPositionInDome), which leans; out of it, the
# keeper's camera offset does.
func _lean_cams(t: float, t_end: float) -> void:
	if Level.viewports == null:
		return
	var lean: float = ShipData.CAM_LEAN * clampf(t / 1.2, 0.0, 1.0) * (1.0 - clampf((t - t_end + 0.9) / 0.9, 0.0, 1.0))
	var at: Vector2 = carrier.global_position + Vector2(0, -20)
	for k in _Story.local_keepers():
		var cam = Level.viewports.getPlayerCam(k.playerId)
		if cam == null or not ("targetOffset" in cam):
			continue
		if not _cams.has(k.playerId):
			if k.global_position.distance_to(to_global(spot)) > 1000.0:
				continue
			_cams[k.playerId] = cam.cameraRestPositionInDome if "cameraRestPositionInDome" in cam else Vector2.ZERO
		var base: Vector2 = _cams[k.playerId]
		if k.isInsideDome and "cameraRestPositionInDome" in cam:
			cam.cameraRestPositionInDome = base + (cam.get_parent().to_local(at) - base) * lean if cam.get_parent() is Node2D else base + (at - base) * lean
			cam.targetOffset = Vector2.ZERO
		else:
			cam.targetOffset = (at - k.global_position) * lean
		if lean <= 0.0 and t > t_end:
			cam.cameraRestPositionInDome = base


# --- feedback --------------------------------------------------------------------------

func _shake_near(amount: float, sec: float) -> void:
	if amount <= 0.0:
		return
	var p: Vector2 = to_global(spot)
	for k in _Story.local_keepers():
		if k.global_position.distance_to(p) < 900.0:
			InputSystem.shake(amount, sec, amount)
			return


func _burst(at: Vector2, n: int, size: float) -> void:
	for i in n:
		var v := Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-50, -10)) * size
		var life: float = _rng.randf_range(0.7, 1.4)
		_dust.append([at + Vector2(_rng.randf_range(-8, 8), 0), v, life, life, _rng.randf_range(2.5, 5.5) * size])


func _process_dust(delta: float) -> void:
	if _dust.is_empty():
		return
	for d in _dust:
		d[0] += d[1] * delta
		d[1] *= 1.0 - delta * 1.8
		d[2] -= delta
	_dust = _dust.filter(func(d): return d[2] > 0.0)
	_fx.queue_redraw()


# A short line over the keeper's head, like its heat lines (hud/heat_talk.gd).
func _say(k, text: String) -> void:
	if _line != null and is_instance_valid(_line):
		_line.queue_free()
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _ShipArt._font_small())
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color("ffb0a8"))
	label.add_theme_color_override("font_outline_color", Color("1a0606"))
	label.add_theme_constant_override("outline_size", 3)
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var holder := Node2D.new()
	holder.name = "ShipLine"
	holder.add_to_group("story-ship-line")
	holder.set_meta("text", text)
	holder.z_as_relative = false
	holder.z_index = 63
	add_child(holder)
	holder.add_child(label)
	label.reset_size()
	label.position = Vector2(-label.size.x * 0.5, -label.size.y)
	holder.position = (to_local(k.global_position) + Vector2(0, -30)).round()
	var tw: Tween = holder.create_tween()
	holder.modulate.a = 0.0
	tw.tween_property(holder, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.2)
	tw.tween_property(holder, "modulate:a", 0.0, 0.5)
	tw.tween_callback(holder.queue_free)
	_line = holder


# --- the pieces ----------------------------------------------------------------------

# The ship's drawing (endgame/ship_art.gd): the legs, the body (baked once,
# drawn live until the bake is in) and the nose; redrawn only when a part moves.
class _ShipBody extends Node2D:
	static var _A = ShipArt
	var legs: float = 1.0
	var visor: float = 0.0
	var lights: bool = true
	var scorched: bool = false
	var body_tex: Texture2D = null

	func _draw() -> void:
		_A.draw_legs(self, legs)
		if body_tex != null:
			draw_texture(body_tex, ShipArt.BODY_RECT.position)
		else:
			_A.draw_body(self, lights, scorched)
		_A.draw_nose(self, visor, lights)


# The running lights: blinking nav lights and the beacon (a few redraws a second).
class _Lights extends Node2D:
	static var _A = ShipArt
	var ship
	var _acc: float = 0.0
	var _blink: bool = false

	func tick(delta: float) -> void:
		_acc += delta
		var b: bool = fmod(_acc, 1.2) < 0.6
		if b != _blink or ship.mode == "lifting":
			_blink = b
			queue_redraw()

	func _draw() -> void:
		if not ship._lights_on:
			return
		var beacon: float = 1.0 if fmod(_acc, 1.6) < 0.18 else 0.0
		_A.draw_lights(self, _blink, beacon)


# The engine plumes out of the bells and the lift jets under the belly.
class _Plume extends Node2D:
	var ship

	func _draw() -> void:
		var e: float = ship._engine
		if e <= 0.0:
			return
		var f: float = 0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.05)
		for m: Vector2 in ShipArt.PLUMES:
			var len: float = (18.0 + 46.0 * e) * f
			var w: float = 6.0 * e
			draw_colored_polygon(PackedVector2Array([m + Vector2(0, -w), m + Vector2(-len, 0), m + Vector2(0, w)]), Color(ShipData.PLUME, 0.85 * e))
			draw_colored_polygon(PackedVector2Array([m + Vector2(0, -w * 0.45), m + Vector2(-len * 0.55, 0), m + Vector2(0, w * 0.45)]), Color(ShipData.PLUME_CORE, e))
		for x in [-60.0, 40.0]:
			var len2: float = (10.0 + 30.0 * e) * f
			var top := Vector2(x, 30.0)
			draw_colored_polygon(PackedVector2Array([top + Vector2(-5, 0), top + Vector2(5, 0), top + Vector2(0, len2)]), Color(ShipData.PLUME, 0.7 * e))
			draw_colored_polygon(PackedVector2Array([top + Vector2(-2, 0), top + Vector2(2, 0), top + Vector2(0, len2 * 0.6)]), Color(ShipData.PLUME_CORE, e))


# The boarding tube: a ribbed jet-bridge from the nose door down to the hatch,
# folding back into the nose.
class _Tube extends Node2D:
	var ship

	func _draw() -> void:
		var e: float = ship.tube_ext
		if e <= 0.01 or not ship.carrier.visible:
			return
		var door: Vector2 = to_local(ship.carrier.to_global(ShipArt.DOOR))
		var hatch: Vector2 = ship.hatch_at
		var end: Vector2 = door.lerp(hatch, e)
		var h0: float = ShipArt.DOOR_HALF_H - 2.0
		var h1: float = lerpf(h0, 11.0, e)
		var top := [door + Vector2(0, -h0), end + Vector2(0, -h1)]
		var bot := [door + Vector2(0, h0), end + Vector2(0, h1)]
		var poly := PackedVector2Array([top[0], top[1], bot[1], bot[0]])
		draw_colored_polygon(Geometry2D.offset_polygon(poly, 1.0)[0], ShipData.OUTLINE)
		draw_colored_polygon(poly, ShipData.HULL_DARK)
		# Its top lit, its floor dark, ribs every few px.
		draw_line(top[0] + Vector2(0, 1), top[1] + Vector2(0, 1), ShipData.HULL, 2.0)
		draw_line(bot[0] + Vector2(0, -1), bot[1] + Vector2(0, -1), ShipData.OUTLINE, 2.0)
		var n: int = int(door.distance_to(end) / 5.0)
		for i in range(1, n):
			var u: float = float(i) / float(n)
			var a: Vector2 = top[0].lerp(top[1], u)
			var b: Vector2 = bot[0].lerp(bot[1], u)
			draw_line(a, b, ShipData.HULL_MID if i % 2 == 0 else ShipData.OUTLINE, 1.0)
		# A stripe of Halcyon yellow at its mouth.
		draw_line(top[1], bot[1], ShipData.BRAND, 2.0)


# The hatch in the dome's glass: a door frame and a light (green open, red
# locked, gold while a keeper holds to board). Its Usable gives the focus.
class _Hatch extends Node2D:
	var ship

	func canFocusUse(keeper) -> bool:
		return ship.can_focus(keeper)

	func useHit(keeper) -> bool:
		return ship.use_hit(keeper)

	func useHold(keeper) -> bool:
		return ship.use_hold(keeper)

	func _draw() -> void:
		var ph: String = ship.phase()
		var col: Color = ShipData.HATCH_LOCKED if ph == "locked" else ShipData.HATCH_OPEN
		if ship.hold_share > 0.0:
			col = ShipData.HATCH_FOCUS
		if ship._flash > 0.0:
			col = col.lerp(Color.WHITE, ship._flash * 0.6)
		var r := Rect2(-3, -12, 6, 24)
		draw_rect(r.grow(1.0), ShipData.OUTLINE)
		draw_rect(r, ShipData.HULL_DARK if ship.tube_ext < 0.5 else Color("0e1218"))
		draw_rect(Rect2(-3, -12, 6, 2), ShipData.BRAND)
		draw_rect(Rect2(-1, -16, 3, 3), col)
		draw_circle(Vector2(0.5, -14.5), 4.0, Color(col, 0.25))


# The prompt over the hatch for a keeper there: the use key (a key cap with
# its name, as bound for the keyboard; the pad's A), the words, and a bar
# under them that fills while the key is held. Locked: a red padlock alone
# (trying the hatch then says the locked line over the keeper).
class _Prompt extends Node2D:
	static var _A = ShipArt
	static var _S = Story
	var ship
	var _label: Label = null
	var _key: String = ""

	func _ready() -> void:
		_label = Label.new()
		_label.add_theme_font_override("font", _A._font_small())
		_label.add_theme_font_size_override("font_size", 8)
		_label.add_theme_color_override("font_color", Color("f4ecd8"))
		_label.add_theme_color_override("font_outline_color", Color("0b0d12"))
		_label.add_theme_constant_override("outline_size", 3)
		_label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_label.position = Vector2(14, -7)
		add_child(_label)

	# The use key's name for the keeper at the hatch.
	func _key_name() -> String:
		var pad: bool = false
		for k in _S.local_keepers():
			if ship.can_focus(k):
				pad = k.deviceId > 0
		if pad:
			return "A"
		for ev in InputMap.action_get_events("ui_select"):
			if ev is InputEventKey:
				var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
				var n: String = OS.get_keycode_string(code)
				if n != "":
					return n.to_upper().substr(0, 5)
		return "E"

	func _draw() -> void:
		var ph: String = ship.phase()
		var locked: bool = ph == "locked"
		_label.text = Endings.SHIP_LOCKED if locked else Endings.SHIP_BOARD
		_label.add_theme_color_override("font_color", Color("ffb0a8") if locked else Color("f4ecd8"))
		var nudge: float = ship._nudge
		position.x = ship.hatch_at.x + 14.0 + sin(nudge * 20.0) * 2.0 * nudge
		var f: FontFile = _A._font_small()
		if locked:
			# Just a padlock: trying the hatch says why (the keeper's line).
			_label.text = ""
			draw_arc(Vector2(4, -4), 3.0, PI, TAU, 8, ShipData.HATCH_LOCKED, 1.5)
			draw_rect(Rect2(0, -3, 8, 6), ShipData.HATCH_LOCKED)
			return
		# The key cap, the words, and under them the hold filling up.
		_key = _key_name()
		var w: float = maxf(9.0, f.get_string_size(_key, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 4.0)
		var cap := Rect2(Vector2(0, -5), Vector2(w, 10))
		draw_rect(cap.grow(1.0), Color("0b0d12"))
		draw_rect(cap, Color("e8e0cc") if nudge <= 0.0 else Color("ffe9a8"))
		draw_rect(Rect2(cap.position + Vector2(0, cap.size.y - 2), Vector2(cap.size.x, 2)), Color("9a927e"))
		draw_string(f, Vector2(2.0, 3.0), _key, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("1a1612"))
		_label.position = Vector2(w + 5.0, -7)
		var lw: float = f.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		var bar := Rect2(Vector2(w + 5.0, 6.0), Vector2(lw, 2.0))
		draw_rect(bar.grow(1.0), Color(0, 0, 0, 0.55))
		if ship.hold_share > 0.0:
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * ship.hold_share, bar.size.y)), ShipData.HATCH_FOCUS)


# Dust on the ground (landing, lift-off) and the boarding keeper's shadow
# running up the tube.
class _Fx extends Node2D:
	var ship

	func _draw() -> void:
		for d in ship._dust:
			var a: float = clampf(d[2] / d[3], 0.0, 1.0)
			var r: float = d[4] * (1.6 - 0.6 * a)
			draw_circle(d[0].round(), round(r), Color(0.36, 0.30, 0.36, 0.5 * a))
			draw_circle((d[0] + Vector2(-r * 0.3, -r * 0.3)).round(), round(r * 0.6), Color(0.58, 0.50, 0.56, 0.4 * a))
		if ship.mode == "lifting" and ship._lift_t < ShipData.WALK_S:
			var u: float = clampf(ship._lift_t / ShipData.WALK_S, 0.0, 1.0)
			var door: Vector2 = to_local(ship.carrier.to_global(ShipArt.DOOR))
			var p: Vector2 = ship.hatch_at.lerp(door, u) + Vector2(0, 3)
			draw_rect(Rect2(p + Vector2(-3, -9), Vector2(6, 12)), Color(0.05, 0.06, 0.09, 0.9))


# Suckers down one side of a front run of the coil.
class _Suckers extends Node2D:
	var pts: PackedVector2Array
	var widths: PackedFloat32Array

	func _draw() -> void:
		var acc: float = 0.0
		for i in range(1, pts.size()):
			acc += pts[i].distance_to(pts[i - 1])
			if acc < 11.0:
				continue
			acc = 0.0
			var n: Vector2 = (pts[i] - pts[i - 1]).normalized().orthogonal()
			var w: float = widths[i]
			var p: Vector2 = pts[i] + n * w * 0.28
			var r: float = maxf(1.5, w * 0.09)
			draw_circle(p, r, COIL_SUCKER)
			draw_circle(p, r * 0.5, COIL_DARK)
