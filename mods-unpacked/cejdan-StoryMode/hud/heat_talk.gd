extends Node

# The keeper talks about the depth heat (#146): a small wavy line over its
# head, so the heat bar explains itself.
#   - Entering passive heat: "so hot" (red-orange).
#   - Each deeper, hotter section after that: the next line of data/heat_lines.gd
#     HOT ("feels even hotter", ...). Going back up a section stays quiet.
#   - Out of the heat with the bar draining (the mine above B4, or the dome):
#     a relieved line from a shuffled cycle (pale blue). Then the next trip
#     down starts from "so hot" again.
# Heat Shielding that stops passive heat (tier IV) stops the hot lines, since
# the bar no longer fills. Lava itself is not depth heat: no lines there.
#
# Lives under the Story Mode node; does nothing without the run's lava field.

const LavaData = preload("res://mods-unpacked/cejdan-StoryMode/data/lava.gd")
const Lines = preload("res://mods-unpacked/cejdan-StoryMode/data/heat_lines.gd")

const GROUP := "story-heat-talk"
const FIELD := "StoryLavaField"
# The line's foot, over the keeper's head (world px; the heat bar sits at -20).
const OFFSET := Vector2(0, -30)

# Highest hot section announced since the keeper last cooled off; -1 = none.
var hot_section: int = -1
# Every line shown this run, for checks: [{text, kind, t}]
var shown: Array = []

var _time: float = 0.0
var _gap_t: float = 0.0
# The state being settled: "hot:<section>" / "cool" / "", and for how long.
var _pending: String = ""
var _pending_t: float = 0.0
var _bag: Array = []
var _holder: Node2D = null
var _font: FontFile


static func instance():
	var tree = Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return null
	return tree.get_first_node_in_group(GROUP)


func _ready() -> void:
	name = "StoryHeatTalk"
	add_to_group(GROUP)


func _process(delta: float) -> void:
	_follow()
	if GameWorld.paused:
		return
	_time += delta
	_gap_t -= delta
	var keeper = Keepers.first()
	var map = Level.map
	if keeper == null or not is_instance_valid(keeper) or map == null or not is_instance_valid(map):
		return
	var field = map.get_node_or_null(FIELD)
	if field == null or keeper.disabled:
		return
	var state: String = _state(keeper, map, field)
	if state != _pending:
		# Leaving the heat: the relief line wants heat on the bar at that moment
		# (it drains fast; an overheat recall has already emptied it).
		if _pending.begins_with("hot:") and not state.begins_with("hot:"):
			_heat_at_exit = field.heat
		_pending = state
		_pending_t = 0.0
		return
	_pending_t += delta
	if _pending_t < Lines.SETTLE or _gap_t > 0.0:
		return
	if state.begins_with("hot:"):
		var section: int = int(state.substr(4))
		if section > hot_section:
			hot_section = section
			_say(str(Lines.HOT.get(section, Lines.HOT[Lines.HOT.keys().max()])), Lines.HOT_COLOR, "hot")
	elif state == "out" and hot_section >= 0:
		# Out of the heat: the next trip down starts from "so hot" again.
		hot_section = -1
		if _heat_at_exit > 0.5 or field.heat > 0.5:
			_say(_next_cool(), Lines.COOL_COLOR, "cool")


var _heat_at_exit: float = 0.0


# "hot:<section>" in passive heat the suit can feel, "out" out of it (the mine
# above B4, or the dome), "" for anything else (in lava).
func _state(keeper, map, field) -> String:
	if field.keeper_in_lava(keeper):
		return ""
	if keeper.isInsideDome:
		return "out"
	var c: Vector2i = map.getTileCoord(keeper.global_position)
	var section: int = map.tileData.get_biomev(c)
	var ocean: Dictionary = map.tileData.get_meta("story_ocean", {})
	if not ocean.is_empty() and c.y >= int(ocean["top"]) - 1:
		section = 8
	if section >= LavaData.PASSIVE_HEAT_START_BIOME and LavaData.passive_heat_mult(keeper.teamId) > 0.0:
		return "hot:%d" % section
	return "out"


func _next_cool() -> String:
	if _bag.is_empty():
		_bag = Lines.COOL.duplicate()
		_bag.shuffle()
	return str(_bag.pop_back())


# small_pixel at 8 px, unsmoothed: one font pixel per world pixel, about half
# the width of the sale pops' Joystix, so a line stays small over the keeper.
func _pixel_font() -> FontFile:
	if _font == null:
		_font = (load("res://gui/fonts/small_pixel.ttf") as FontFile).duplicate()
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.hinting = TextServer.HINTING_NONE
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return _font


func _say(text: String, color: Color, kind: String) -> void:
	_gap_t = Lines.GAP
	shown.append({"text": text, "kind": kind, "t": snappedf(_time, 0.01)})
	ModLoaderLog.info("Keeper heat line: " + text, "cejdan-StoryMode")
	if _holder != null and is_instance_valid(_holder):
		_holder.queue_free()
	var label: RichTextLabel = RichTextLabel.new()
	label.name = "HeatLine"
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label.add_theme_font_override("normal_font", _pixel_font())
	label.add_theme_font_size_override("normal_font_size", 8)
	label.add_theme_color_override("default_color", color)
	label.add_theme_color_override("font_outline_color", Color("140a06") if kind == "hot" else Color("06101a"))
	label.add_theme_constant_override("outline_size", 3)
	var wave: String = "[wave amp=12 freq=4 connected=1]" if kind == "hot" else "[wave amp=8 freq=2 connected=1]"
	label.text = "[center]" + wave + text.replace("[", "[lb]") + "[/wave][/center]"
	var holder: Node2D = Node2D.new()
	holder.add_to_group("story-heat-line")
	holder.set_meta("text", text)
	holder.z_index = 62
	holder.z_as_relative = false
	Level.map.add_child(holder)
	holder.add_child(label)
	label.custom_minimum_size = Vector2(text.length() * 6 + 12, 0)
	label.reset_size()
	label.position = Vector2(-label.size.x / 2.0, -label.size.y)
	_holder = holder
	_follow()
	holder.modulate.a = 0.0
	var t: Tween = holder.create_tween()
	t.tween_property(holder, "modulate:a", 1.0, 0.2)
	t.tween_interval(Lines.LIFE - 0.75)
	t.tween_property(holder, "modulate:a", 0.0, 0.55)
	t.tween_callback(holder.queue_free)


func _follow() -> void:
	if _holder == null or not is_instance_valid(_holder):
		return
	var keeper = Keepers.first()
	if keeper != null and is_instance_valid(keeper):
		_holder.global_position = (keeper.global_position + OFFSET).round()
