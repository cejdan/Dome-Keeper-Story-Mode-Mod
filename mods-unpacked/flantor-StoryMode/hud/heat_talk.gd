extends Node

# The keeper talks about the depth heat (#146): a small wavy line over its
# head, so the heat bar explains itself.
#   - Entering passive heat: "so hot" (red-orange).
#   - Each hotter heat level after that: that level's line in data/heat_lines.gd
#     HOT ("feels even hotter", ...). The level counts from the suit's
#     shielding (#285), so with Heat Shielding I "so hot" comes at B5. Going
#     back up stays quiet.
#   - Out of the heat with the bar draining (the mine above B4, or the dome):
#     a relieved line from a shuffled cycle (pale blue). Then the next trip
#     down starts from "so hot" again.
# Where the suit's shielding stops the depth heat there are no hot lines, since
# the bar doesn't fill. Lava itself is not depth heat: no lines there.
#
# Lives under the Story Mode node; does nothing without the run's lava field.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const LavaData = preload("res://mods-unpacked/flantor-StoryMode/data/lava.gd")
static var _LavaData = LavaData  # calls go through this: lazy_preload makes const-preload calls slow
const Lines = preload("res://mods-unpacked/flantor-StoryMode/data/heat_lines.gd")

const GROUP := "story-heat-talk"
const FIELD := "StoryLavaField"
# The line's foot, over the keeper's head (world px; the heat bar sits at -20).
const OFFSET := Vector2(0, -30)

# Every local keeper talks about its own heat (#231). Per keeper (playerId ->):
#   hot: highest heat level announced since it last cooled off (-1 = none)
#   pending / pending_t: the state being settled ("hot:<level>" / "out" / "")
#   gap: seconds before it may talk again; exit_heat: heat as it left the heat
#   holder: its line on screen
var talkers: Dictionary = {}
# Every line shown this run, for checks: [{text, kind, t, player}]
var shown: Array = []

var _time: float = 0.0
var _bag: Array = []
var _font: FontFile

# The first local keeper's state, as before (playtests read these).
var hot_section: int:
	get:
		return int(_t0().get("hot", -1))
var _pending: String:
	get:
		return str(_t0().get("pending", ""))


func _t0() -> Dictionary:
	var k = _Story.local_keeper()
	return talkers.get(k.playerId, {}) if k != null and is_instance_valid(k) else {}


func _talker(pid: String) -> Dictionary:
	if not talkers.has(pid):
		talkers[pid] = {"hot": -1, "pending": "", "pending_t": 0.0, "gap": 0.0, "exit_heat": 0.0, "holder": null}
	return talkers[pid]


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
	var map = Level.map
	if map == null or not is_instance_valid(map):
		return
	var field = map.get_node_or_null(FIELD)
	if field == null:
		return
	for keeper in _Story.local_keepers():
		_process_keeper(keeper, map, field, delta)


func _process_keeper(keeper, map, field, delta: float) -> void:
	var t: Dictionary = _talker(keeper.playerId)
	t["gap"] -= delta
	if keeper.disabled:
		return
	var heat: float = field.heat_of(keeper)
	var state: String = _state(keeper, map, field)
	if state != t["pending"]:
		# Leaving the heat: the relief line wants heat on the bar at that moment
		# (it drains fast; an overheat recall has already emptied it).
		if str(t["pending"]).begins_with("hot:") and not state.begins_with("hot:"):
			t["exit_heat"] = heat
		t["pending"] = state
		t["pending_t"] = 0.0
		return
	t["pending_t"] += delta
	if t["pending_t"] < Lines.SETTLE or t["gap"] > 0.0:
		return
	if state.begins_with("hot:"):
		var level: int = int(state.substr(4))
		if level > t["hot"]:
			t["hot"] = level
			_say(keeper, str(Lines.HOT[mini(level, Lines.HOT.size() - 1)]), Lines.HOT_COLOR, "hot")
	elif state == "out" and t["hot"] >= 0:
		# Out of the heat: the next trip down starts from "so hot" again.
		t["hot"] = -1
		if t["exit_heat"] > 0.5 or heat > 0.5:
			_say(keeper, _next_cool(), Lines.COOL_COLOR, "cool")


# "hot:<level>" in passive heat the suit can feel, "out" out of it (the mine
# above B4, or the dome), "" for anything else (in lava). The level is
# data/lava.gd's passive_level, except that the lava ocean counts one deeper
# than B8 here (it heats like B8, but gets its own line).
func _state(keeper, map, field) -> String:
	if field.keeper_in_lava(keeper):
		return ""
	if keeper.isInsideDome:
		return "out"
	var c: Vector2i = map.getTileCoord(keeper.global_position)
	var section: int = map.tileData.get_biomev(c)
	var ocean: Dictionary = map.tileData.get_meta("story_ocean", {})
	if not ocean.is_empty() and c.y > int(ocean["ceiling"]):
		section = 8
	if section >= LavaData.PASSIVE_HEAT_START_BIOME and _LavaData.passive_rate(section, keeper) > 0.0:
		return "hot:%d" % (section - LavaData.PASSIVE_HEAT_START_BIOME - _LavaData.shield_tier(keeper))
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


func _say(k, text: String, color: Color, kind: String) -> void:
	var t: Dictionary = _talker(k.playerId)
	t["gap"] = Lines.GAP
	shown.append({"text": text, "kind": kind, "t": snappedf(_time, 0.01), "player": k.playerId})
	ModLoaderLog.info("Keeper heat line (%s): %s" % [k.playerId, text], "flantor-StoryMode")
	if t["holder"] != null and is_instance_valid(t["holder"]):
		t["holder"].queue_free()
	t["holder"] = _make(text, color, kind)
	_follow()
	# Online (#229): the other players see this keeper's line over its head.
	if not Network.is_offline_mode():
		if multiplayer.is_server():
			_relay(k.playerId, text, color, kind, 1)
		else:
			_net_line.rpc_id(1, k.playerId, text, color, kind)


# Lines over the other players' keepers: playerId -> holder. Every one shown,
# for checks: [{player, text}]
var _remote: Dictionary = {}
var shown_remote: Array = []


# A player's heat line: a client sends its own to the host, which passes it on
# to the other clients; the host sends its own to every client.
@rpc("any_peer", "call_remote", "reliable")
func _net_line(player_id: String, text: String, color: Color, kind: String) -> void:
	var from: int = multiplayer.get_remote_sender_id()
	if multiplayer.is_server():
		_relay(player_id, text, color, kind, from)
	elif from != 1:
		return
	for mine in _Story.local_keepers():
		if mine.playerId == player_id:
			return
	if _remote.has(player_id) and is_instance_valid(_remote[player_id]):
		_remote[player_id].queue_free()
	_remote[player_id] = _make(text, color, kind)
	shown_remote.append({"player": player_id, "text": text})
	_follow()


func _relay(player_id: String, text: String, color: Color, kind: String, from: int) -> void:
	for c in Network.clients:
		if c.peer_id != from and c.connection_state == Network.ConnectionState.LEVEL_STAGE_SYNC:
			_net_line.rpc_id(c.peer_id, player_id, text, color, kind)


func _make(text: String, color: Color, kind: String) -> Node2D:
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
	holder.modulate.a = 0.0
	var t: Tween = holder.create_tween()
	t.tween_property(holder, "modulate:a", 1.0, 0.2)
	t.tween_interval(Lines.LIFE - 0.75)
	t.tween_property(holder, "modulate:a", 0.0, 0.55)
	t.tween_callback(holder.queue_free)
	return holder


func _follow() -> void:
	for pid in _remote:
		var h = _remote[pid]
		var k = Keepers.getKeeper(pid) if is_instance_valid(h) and Keepers.hasKeeper(pid) else null
		if k != null and is_instance_valid(k):
			h.global_position = (k.global_position + OFFSET).round()
	for keeper in _Story.local_keepers():
		var h = talkers.get(keeper.playerId, {}).get("holder", null)
		if h != null and is_instance_valid(h):
			h.global_position = (keeper.global_position + OFFSET).round()
