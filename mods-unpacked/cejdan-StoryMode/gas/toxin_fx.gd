extends Node2D

# What the keeper's toxin looks and sounds like (#202): the green bar over the
# keeper, a green vignette that creeps in from the screen's edges, and the
# game's sound going muffled. A child of the gas field, drawn above the gas.
# Draw and sound only; the toxin itself is the gas field's.

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const FieldUtil = preload("res://mods-unpacked/cejdan-StoryMode/util/field_util.gd")
const GasData = preload("res://mods-unpacked/cejdan-StoryMode/data/gas.gd")
const GasSfx = preload("res://mods-unpacked/cejdan-StoryMode/gas/gas_sfx.gd")
const BAR_OFFSET := Vector2(-9, -15)      # under the heat bar (-20)
const COL_BAR := Color("7ad11e")
const COL_BAR_FULL := Color("d8ff4a")
const MUFFLE_FROM := 0.35                 # share of the bar where the sound starts to dull
const MUFFLE_HZ := 700.0                  # cutoff at a full bar

var field
var muffle := 0.0                         # 0..1, as applied

# One screen-edge vignette per local keeper, in that keeper's split view (#231):
# playerId -> {"layer", "rect", "mat", "share", "vignette"}. A CanvasLayer under
# the map draws in the first view only, so each gets its view's viewport.
var views: Dictionary = {}
# The first local keeper's, as before (playtests read these).
var share: float:
	get:
		return _first().get("share", 0.0)
var vignette: float:
	get:
		return _first().get("vignette", 0.0)
var _rect: ColorRect:
	get:
		return _first().get("rect", null)

var _time := 0.0
var _lowpass: AudioEffectLowPassFilter
var _choke_t := 0.0

const VIGNETTE := preload("res://mods-unpacked/cejdan-StoryMode/gas/look/toxin_vignette.gdshader")


func setup(p_field) -> void:
	field = p_field
	z_index = 20


func _first() -> Dictionary:
	var k = Story.local_keeper()
	if k != null and is_instance_valid(k) and views.has(k.playerId):
		return views[k.playerId]
	return views.values()[0] if not views.is_empty() else {}


# One local keeper: a CanvasLayer over the screen, as before. Several (split
# views): a rect in the world over that keeper's camera view, drawn in that
# keeper's view only (its canvas bit). A CanvasLayer can't be pointed at a
# split view: one with custom_viewport set errors when the level is freed.
func _make_view(keeper, split: bool) -> Dictionary:
	var layer: CanvasLayer = null
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = VIGNETTE
	mat.set_shader_parameter("amount", 0.0)
	mat.set_shader_parameter("pulse", 0.0)
	rect.material = mat
	rect.visible = false
	if split:
		rect.z_as_relative = false
		rect.z_index = 200
		add_child(rect)
		rect.visibility_layer = 0
		Level.viewports.showForLocalKeeper(keeper, rect)
	else:
		layer = CanvasLayer.new()
		layer.layer = 3
		add_child(layer)
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(rect)
	return {"layer": layer, "rect": rect, "mat": mat, "share": 0.0, "vignette": 0.0, "split": split}


func _free_view(v: Dictionary) -> void:
	if v["layer"] != null and is_instance_valid(v["layer"]):
		v["layer"].queue_free()
	elif is_instance_valid(v["rect"]):
		v["rect"].queue_free()


# Each local keeper's vignette sits in that keeper's split view.
func _sync_views() -> Array:
	var ks: Array = Story.local_keepers()
	var split: bool = ks.size() > 1 and Level.viewports != null
	var ids: Dictionary = {}
	for k in ks:
		ids[k.playerId] = true
		if views.has(k.playerId) and views[k.playerId]["split"] != split:
			_free_view(views[k.playerId])
			views.erase(k.playerId)
		if not views.has(k.playerId):
			views[k.playerId] = _make_view(k, split)
		if split:
			# Over the keeper's camera view, a margin past its edges.
			var r: Rect2 = Story.view_rect(k.playerId, 8.0)
			if r.has_area():
				var rect: ColorRect = views[k.playerId]["rect"]
				rect.position = to_local(r.position)
				rect.size = r.size
	for pid in views.keys():
		if not ids.has(pid):
			_free_view(views[pid])
			views.erase(pid)
	return ks


func _process(delta: float) -> void:
	if field == null:
		return
	if not GameWorld.paused:
		_time += delta
	var worst := 0.0
	for k in _sync_views():
		var v: Dictionary = views[k.playerId]
		v["share"] = clampf(field.toxin_of(k) / GasData.TOXIN_MAX, 0.0, 1.0)
		worst = maxf(worst, v["share"])
		var warn_k: bool = v["share"] >= GasData.WARN_SHARE
		# The vignette eases toward the bar, so it creeps in and drains away.
		var want: float = smoothstep(0.15, 1.0, v["share"])
		v["vignette"] = move_toward(v["vignette"], want, delta * (1.6 if want > v["vignette"] else 0.9))
		v["rect"].visible = v["vignette"] > 0.003
		v["mat"].set_shader_parameter("amount", v["vignette"])
		v["mat"].set_shader_parameter("pulse", (0.5 + 0.5 * sin(_time * 12.0)) if warn_k else 0.0)
	# One sound for the room: it dulls for the worst-off local keeper.
	var warn: bool = worst >= GasData.WARN_SHARE
	_set_muffle(smoothstep(MUFFLE_FROM, 1.0, worst), delta)
	if warn and not GameWorld.paused:
		_choke_t -= delta
		if _choke_t <= 0.0:
			_choke_t = 0.45
			GasSfx.play("choke", -4.0)
	else:
		_choke_t = 0.0
	queue_redraw()


# The game's sound through a low-pass on the master bus, only while it is needed.
func _set_muffle(want: float, delta: float) -> void:
	muffle = move_toward(muffle, want, delta * 2.0)
	if muffle <= 0.001:
		_drop_lowpass()
		return
	if _lowpass == null:
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.resonance = 0.5
		AudioServer.add_bus_effect(0, _lowpass)
	# From wide open down to MUFFLE_HZ, evenly in pitch.
	_lowpass.cutoff_hz = 18000.0 * pow(MUFFLE_HZ / 18000.0, muffle)


func _drop_lowpass() -> void:
	if _lowpass == null:
		return
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) == _lowpass:
			AudioServer.remove_bus_effect(0, i)
			break
	_lowpass = null


func _exit_tree() -> void:
	_drop_lowpass()


func _draw() -> void:
	if field == null:
		return
	# A bar over each local keeper (#231).
	for keeper in Story.local_keepers():
		var t: float = field.toxin_of(keeper)
		if t <= 0.5:
			continue
		var sh: float = clampf(t / GasData.TOXIN_MAX, 0.0, 1.0)
		FieldUtil.draw_bar(self, (to_local(keeper.global_position) + BAR_OFFSET).round(), sh,
			COL_BAR.lerp(COL_BAR_FULL, sh), sh >= GasData.WARN_SHARE and fposmod(_time * 8.0, 1.0) < 0.5)
