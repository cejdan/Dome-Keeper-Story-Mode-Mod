extends Node2D

# The gas's look (#203): a small fluid simulation on the GPU, for the tiles
# around the screen only (spike: #199).
#
# The gas field's grid (one density per tile) is the truth. For a window of
# WIN tiles that follows the screen, two float fields at SUB texels a tile are
# stepped STEPS times a second in ping-pong SubViewports: velocity (buoyancy,
# churn, rock as walls, the keeper's wake, the grid's own gas movement), and
# the dye the picture is made of. The dye is pulled toward the grid, so what
# is drawn thick is what hurts. look/show.gdshader draws it in the game's
# pixels; look/glow.gdshader adds its light to the rock around.
#
# Draw-only: nothing here is saved or changes the game.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const GasData = preload("res://mods-unpacked/flantor-StoryMode/data/gas.gd")
const DIR := "res://mods-unpacked/flantor-StoryMode/gas/look/"
const TILE := 24.0
const SUB := 8                      # field texels per tile
const WIN := Vector2i(32, 20)       # the window, in tiles (the screen shows about 19 x 11)
const STEPS := 60.0                 # simulation steps a second, whatever the frame rate
const FLUX_FULL := 0.6              # grid gas movement that counts as a full-strength push

var field
var map
# The keeper whose split view this look draws (#231); null: the first local
# keeper, or the screen's centre when there is none.
var keeper = null
var c0 := Vector2i.ZERO             # the window's top-left tile
var params := {"buoyancy": 1.6, "churn": 2.6, "vorticity": 0.16, "jet": 0.05, "flux_gain": 7.0,
	"fill_rate": 0.09, "clear_rate": 0.16, "untwist": 0.02, "glow": 0.17}
var cpu_us := 0
var cpu_frames := 0
var rebuilds := 0

var _time := 0.0
var _acc := 0.0
var _vel_mat: ShaderMaterial
var _dye_mat: ShaderMaterial
var _show_mat: ShaderMaterial
var _glow_mat: ShaderMaterial
var _vel_a: SubViewport
var _dye_a: SubViewport
var _tiles_img: Image
var _tiles_tex: ImageTexture
var _flux_img: Image
var _flux_tex: ImageTexture
var _sprite: Sprite2D
var _glow: Sprite2D
var _last_keeper = null
var _keeper_vel := Vector2.ZERO
var _have_window := false
var _built_rev := -1
var _built_c0 := Vector2i(1 << 20, 0)
var _built_seen := -1
var _flux_live := false
var _glided := false
# Asleep (#347): no gas, fire or gas movement in the window for SLEEP_AFTER
# seconds, so the dye has long cleared (it loses CLEAR_RATE of what is left a
# step, 60 steps a second): nothing is drawn, so the four fields stop
# rendering and both layers hide until gas comes into the window again.
const SLEEP_AFTER := 2.0
var asleep := false
var _empty_for := 0.0
var _viewports: Array = []
# What stays put while the window does (#347): per window cell, bit 0 open
# (inside the mine, no rock, not the boss chamber), bit 1 revealed. Rebuilt
# when the window moves, a tile opens or closes, the reveal grows, or after
# STATIC_REFRESH seconds; the per-frame pass reads only the gas and lava
# dictionaries.
const STATIC_REFRESH := 1.0
var _static := PackedByteArray()
var _static_c0 := Vector2i(1 << 20, 0)
var _static_tiles := -1
var _static_seen := -1
var _static_t := 0.0
var _shifted := false            # the window moved this frame
var _has_gas := false            # the last pass found gas, fire or movement in the window


func setup(p_field) -> void:
	field = p_field
	map = field.map
	var size := WIN * SUB
	_tiles_img = Image.create(WIN.x, WIN.y, false, Image.FORMAT_RGBA8)
	_tiles_tex = ImageTexture.create_from_image(_tiles_img)
	_flux_img = Image.create(WIN.x, WIN.y, false, Image.FORMAT_RG8)
	_flux_img.fill(Color(0.5, 0.5, 0.0))
	_flux_tex = ImageTexture.create_from_image(_flux_img)
	_vel_mat = _material("vel.gdshader")
	_dye_mat = _material("dye.gdshader")
	var vel := _pair("Vel", size, _vel_mat)
	var dye := _pair("Dye", size, _dye_mat)
	_vel_a = vel[0]
	_dye_a = dye[0]
	_vel_mat.set_shader_parameter("prev", vel[1].get_texture())
	_vel_mat.set_shader_parameter("dye", dye[1].get_texture())
	_vel_mat.set_shader_parameter("flux", _flux_tex)
	_dye_mat.set_shader_parameter("prev", dye[1].get_texture())
	_dye_mat.set_shader_parameter("vel", vel[0].get_texture())
	for m in [_vel_mat, _dye_mat]:
		m.set_shader_parameter("tiles", _tiles_tex)
		m.set_shader_parameter("texel", Vector2(1.0 / size.x, 1.0 / size.y))
		m.set_shader_parameter("sub", float(SUB))
	_glow_mat = _material("glow.gdshader")
	_show_mat = _material("show.gdshader")
	for m in [_glow_mat, _show_mat]:
		m.set_shader_parameter("dye", dye[0].get_texture())
		m.set_shader_parameter("tiles", _tiles_tex)
		m.set_shader_parameter("size_px", Vector2(WIN) * TILE)
		m.set_shader_parameter("win_tiles", Vector2(WIN))
	_show_mat.set_shader_parameter("vel", vel[0].get_texture())
	_glow_mat.set_shader_parameter("tiles_soft", _tiles_tex)
	_glow = _layer(dye[0].get_texture(), _glow_mat)
	_sprite = _layer(dye[0].get_texture(), _show_mat)


func _layer(tex: Texture2D, mat: ShaderMaterial) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.scale = Vector2(TILE / SUB, TILE / SUB)
	s.material = mat
	add_child(s)
	return s


func _material(file: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(DIR + file)
	return m


# A simulated field and its copy: the simulation reads the copy (the last
# state) and writes the next one.
func _pair(label: String, size: Vector2i, mat: ShaderMaterial) -> Array:
	var out: Array = []
	for i in 2:
		var vp := SubViewport.new()
		vp.name = label + ("Sim" if i == 0 else "Copy")
		vp.size = size
		vp.disable_3d = true
		vp.transparent_bg = true
		vp.use_hdr_2d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		add_child(vp)
		out.append(vp)
		_viewports.append(vp)
	var sim := ColorRect.new()
	sim.size = Vector2(size)
	sim.material = mat
	out[0].add_child(sim)
	var copy := TextureRect.new()
	copy.texture = out[0].get_texture()
	copy.size = Vector2(size)
	copy.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	copy.material = _material("copy.gdshader")
	out[1].add_child(copy)
	return out


func _process(delta: float) -> void:
	if map == null:
		return
	var t0 := Time.get_ticks_usec()
	var step := false
	if not GameWorld.paused:
		_time += delta
		_acc += delta
		if _acc >= 1.0 / STEPS:
			step = true
			_acc = minf(_acc - 1.0 / STEPS, 1.0 / STEPS)
	_update_window()
	_update_tiles(step)
	_update_sleep(delta)
	if asleep:
		cpu_us += Time.get_ticks_usec() - t0
		cpu_frames += 1
		return
	var keeper = _keeper()
	var kp := Vector2(-999, -999)
	if keeper != null and is_instance_valid(keeper):
		var local: Vector2 = to_local(keeper.global_position)
		kp = (local - _sprite.position) / (TILE / SUB)
		if step:
			# Field velocity is texels a step / 0.15.
			var kv := Vector2.ZERO
			if _last_keeper != null:
				kv = (local - _last_keeper) / (TILE / SUB) / 0.15
			if kv.length() < 0.6 or kv.length() > 40.0:
				kv = Vector2.ZERO
			_keeper_vel = kv.limit_length(10.0)
			_last_keeper = local
	for m in [_vel_mat, _dye_mat]:
		m.set_shader_parameter("run", 1.0 if step else 0.0)
	# The fields change only on a step, or when the window moves under them
	# (#347): between steps a pass would copy each field onto itself, so the
	# four viewports render only on those frames, not on every frame.
	if step or _shifted:
		for vp in _viewports:
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_vel_mat.set_shader_parameter("time", _time)
	_vel_mat.set_shader_parameter("origin", Vector2(c0 * SUB))
	_vel_mat.set_shader_parameter("keeper", kp)
	_vel_mat.set_shader_parameter("keeper_vel", _keeper_vel)
	_vel_mat.set_shader_parameter("keeper_r", 0.75 * SUB)
	for k in ["buoyancy", "churn", "vorticity", "jet", "flux_gain"]:
		_vel_mat.set_shader_parameter(k, params[k])
	for k in ["fill_rate", "clear_rate", "untwist"]:
		_dye_mat.set_shader_parameter(k, params[k])
	_show_mat.set_shader_parameter("time", _time)
	_show_mat.set_shader_parameter("origin_tiles", Vector2(c0))
	_glow_mat.set_shader_parameter("time", _time)
	_glow_mat.set_shader_parameter("strength", params["glow"])
	cpu_us += Time.get_ticks_usec() - t0
	cpu_frames += 1


func _keeper():
	if keeper != null and is_instance_valid(keeper):
		return keeper
	var k = _Story.local_keeper()
	return k if k != null and is_instance_valid(k) else null


# Splitscreen (#231): this look's sprites show only in `k`'s split view (each
# view has its own look); null shows them in every view.
func show_in_view_of(k) -> void:
	for s in [_sprite, _glow]:
		if k == null or Level.viewports == null:
			s.visibility_layer = 1
		else:
			# As Viewports.hideForAllLocalPlayersExcept, which wants a typed array.
			s.visibility_layer = 0
			Level.viewports.showForLocalKeeper(k, s)


# The window follows the screen's centre (this look's keeper's camera) in whole
# tiles; the fields are shifted by the same amount on the frame it moves, so
# the gas stays put in the world.
func _update_window() -> void:
	var world_centre = null
	var k = _keeper()
	if k != null and Level.viewports != null and Keepers.local.getCount() > 1:
		var cam = Level.viewports.getPlayerCam(k.playerId)
		if cam != null and is_instance_valid(cam) and cam.is_inside_tree():
			world_centre = cam.get_screen_center_position()
	if world_centre == null:
		var inv: Transform2D = get_global_transform_with_canvas().affine_inverse()
		world_centre = to_global(inv * (get_viewport().get_visible_rect().get_center()))
	var want: Vector2i = map.getTileCoord(world_centre) - WIN / 2
	var shift := Vector2.ZERO
	if _have_window and want != c0:
		shift = Vector2(want - c0) / Vector2(WIN)
	c0 = want
	_have_window = true
	_vel_mat.set_shader_parameter("shift", shift)
	_dye_mat.set_shader_parameter("shift", shift)
	_shifted = shift != Vector2.ZERO
	var pos: Vector2 = to_local(map.getTilePos(Vector2(c0))) - Vector2(TILE, TILE) * 0.5
	_sprite.position = pos
	_glow.position = pos


# Sleeps once the window has held no gas for SLEEP_AFTER seconds; wakes the
# frame gas (or fire, or gas moving) is in it again (#347).
func _update_sleep(delta: float) -> void:
	if _has_gas:
		_empty_for = 0.0
		if asleep:
			_set_asleep(false)
		return
	_empty_for += delta
	if not asleep and _empty_for >= SLEEP_AFTER:
		_set_asleep(true)


func _set_asleep(v: bool) -> void:
	asleep = v
	for vp in _viewports:
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED if v else SubViewport.UPDATE_ONCE
	_sprite.visible = not v
	_glow.visible = not v


# Tiles that opened or closed anywhere: the gas field counts tile breaks, the
# lava field its hardenings.
func _tiles_rev() -> int:
	var n: int = field.tiles_rev
	if field._lava != null and is_instance_valid(field._lava):
		n += field._lava.tiles_rev
	return n


func _update_static(vis: Dictionary) -> void:
	var tr: int = _tiles_rev()
	_static_t += get_process_delta_time()
	if c0 == _static_c0 and tr == _static_tiles and vis.size() == _static_seen and _static_t < STATIC_REFRESH:
		return
	_static_c0 = c0
	_static_tiles = tr
	_static_seen = vis.size()
	_static_t = 0.0
	if _static.size() != WIN.x * WIN.y:
		_static.resize(WIN.x * WIN.y)
	var chamber: Rect2i = field._chamber
	var i := 0
	for y in range(c0.y, c0.y + WIN.y):
		for x in range(c0.x, c0.x + WIN.x):
			var c := Vector2i(x, y)
			var b := 0
			if y >= GasData.MIN_Y and map.is_tile_empty(c) and not chamber.has_point(c):
				b = 1
			if vis.has(Vector2(c)):
				b |= 2
			_static[i] = b
			i += 1


# One texel a tile. tiles: r open, g gas density / 4, b revealed, a how hot it burns. flux: the
# grid's gas movement through the tile. Rebuilt only when something changed.
func _update_tiles(step: bool = true) -> void:
	var vis: Dictionary = map.visibleTileCoords
	var flux_now: bool = not field.flux.is_empty()
	# Gas between two steps glides (#211): redrawn every frame while the last
	# step moved some, and once more when the glide ends.
	var gliding: bool = field.moving and field.step_blend() < 1.0
	var glided: bool = _glided
	_update_static(vis)
	var moved: bool = c0 != _built_c0 or vis.size() != _built_seen
	if not moved and field.revision == _built_rev and not flux_now and not _flux_live and not gliding and not glided:
		_glided = false
		return
	# The fields read the gas only on a step (#347): a change between steps
	# waits for the next one (a new window can't wait: it is drawn this frame).
	if not moved and not step:
		_glided = true
		return
	_glided = gliding
	# Asleep with no gas anywhere: nothing can be in the window.
	if asleep and field.mass.is_empty() and field.fire.is_empty():
		_built_rev = field.revision
		_built_c0 = c0
		_built_seen = vis.size()
		return
	_built_rev = field.revision
	_built_c0 = c0
	_built_seen = vis.size()
	rebuilds += 1
	var data := PackedByteArray()
	data.resize(WIN.x * WIN.y * 4)
	var fdata := PackedByteArray()
	fdata.resize(WIN.x * WIN.y * 2)
	fdata.fill(128)
	var i := 0
	var j := 0
	var k := 0
	var any_flux := false
	var any_gas := false
	var burning: bool = not field.fire.is_empty()
	var mass: Dictionary = field.mass
	var prev: Dictionary = field.prev_mass
	var flux: Dictionary = field.flux
	var fire: Dictionary = field.fire
	var lava: Dictionary = field._lava.mass if field._lava != null and is_instance_valid(field._lava) else {}
	# shown_mass(), inline: the gas between its last two steps.
	var blend: float = 1.0 if field.freeze_flow else field.step_blend()
	for y in range(c0.y, c0.y + WIN.y):
		for x in range(c0.x, c0.x + WIN.x):
			var st: int = _static[k]
			k += 1
			var c := Vector2i(x, y)
			if st & 1 and lava.get(c, 0.0) < 0.9:
				data[i] = 255
				var now: float = mass.get(c, 0.0)
				var m: float = lerpf(prev.get(c, now), now, blend) if blend < 1.0 else now
				if m > 0.0:
					any_gas = true
					data[i + 1] = int(clampf(m / 4.0, 0.0, 1.0) * 255.0)
				if flux_now and flux.has(c):
					var f: Vector2 = (field.flux_at(c) / FLUX_FULL).limit_length(1.0)
					if f != Vector2.ZERO:
						any_flux = true
						fdata[j] = int(clampf(f.x * 0.5 + 0.5, 0.0, 1.0) * 255.0)
						fdata[j + 1] = int(clampf(f.y * 0.5 + 0.5, 0.0, 1.0) * 255.0)
			if st & 2:
				data[i + 2] = 255
			if burning and fire.has(c):
				var fa: float = field.fire_at(c)
				if fa > 0.0:
					any_gas = true
					data[i + 3] = int(fa * 255.0)
			i += 4
			j += 2
	_has_gas = any_gas or any_flux
	if asleep and not _has_gas:
		return
	_tiles_img.set_data(WIN.x, WIN.y, false, Image.FORMAT_RGBA8, data)
	_tiles_tex.update(_tiles_img)
	if any_flux or _flux_live:
		_flux_img.set_data(WIN.x, WIN.y, false, Image.FORMAT_RG8, fdata)
		_flux_tex.update(_flux_img)
	_flux_live = any_flux


# The drawn density at the middle of a tile, read back from the dye field (playtests).
func dye_at(cell: Vector2i) -> float:
	var img: Image = _dye_a.get_texture().get_image()
	var p: Vector2i = (cell - c0) * SUB + Vector2i(SUB / 2, SUB / 2)
	if p.x < 0 or p.y < 0 or p.x >= img.get_width() or p.y >= img.get_height():
		return -1.0
	return img.get_pixel(p.x, p.y).r


func debug_view(mode: int) -> void:
	_show_mat.set_shader_parameter("raw", float(mode))
