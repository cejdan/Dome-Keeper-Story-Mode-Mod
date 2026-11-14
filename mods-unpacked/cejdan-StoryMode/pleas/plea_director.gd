extends Node

# Monster pleas (#91). During a wave the monsters shout at the keeper: one line
# when the wave arrives, one or two during the fight, and now and then a
# monster's last words where it falls. Pleas never pause anything.
#
# Look: the monsters' frantic voice, red text shaking harder the deeper the
# keeper has been (the horror's voice is violet and calm; the two never mix).
# Lines float above the dome in the world. When the dome is off screen (the
# keeper is down the mine), wave lines show small at the top of the screen
# instead, as a distant cry; last words only show where the monster fell.
#
# The pool comes from the deepest biome reached (data/pleas.gd stages A-D).
# A line shows through render(): in the monsters' runes until translators are
# installed (pleas/runes.gd, #92).

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const PleaData = preload("res://mods-unpacked/cejdan-StoryMode/data/pleas.gd")
const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const Runes = preload("res://mods-unpacked/cejdan-StoryMode/pleas/runes.gd")

const GROUP := "story-pleas"
const RED := Color("ff3b30")
const RED_DEEP := Color("8c0f1c")
# Shake strength by stage: frantic grows with depth.
const SHAKE := {"A": 3, "B": 5, "C": 8, "D": 11}
const SECONDS := {"arrive": 4.5, "fight": 4.0, "death": 3.0}
# Fight lines this long after the wave arrives (the second one only sometimes).
const FIGHT_AT := [7.0, 17.0]
const SECOND_FIGHT_CHANCE := 0.6
# Last words: chance per monster death, and the shortest gap between two.
var death_chance: float = 0.3
const DEATH_GAP := 6.0
# Where above the dome a wave line floats (world px from the dome's origin).
const DOME_OFFSET := Vector2(0, -96)

signal plea_shown(kind: String, line: String, stage: String)

var _wave_t: float = -1.0
var _fights_due: Array = []
var _last_death_t: float = -100.0
var _time: float = 0.0
var _watched: Dictionary = {}
var _current: Node = null
var _last_line: String = ""
var _ui_layer: CanvasLayer
# Every plea shown this run, for checks: [{t, kind, stage, line, where}]
var shown: Array = []


static func instance():
	var tree = Engine.get_main_loop()
	return tree.get_first_node_in_group(GROUP) if tree is SceneTree else null


func _ready() -> void:
	name = "StoryPleas"
	add_to_group(GROUP)
	Data.listen(self, "team1.monsters.wavepresent")
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 3
	add_child(_ui_layer)


func propertyChanged(property: String, oldValue, newValue) -> void:
	if property == "team1.monsters.wavepresent" and newValue and not oldValue:
		_wave_arrived()


func stage() -> String:
	return PleaData.stage_for(StoryBeats.deepest())


func _wave_arrived() -> void:
	_wave_t = 0.0
	_fights_due = [FIGHT_AT[0]]
	if randf() < SECOND_FIGHT_CHANCE:
		_fights_due.append(FIGHT_AT[1])
	say("arrive")


func _process(delta: float) -> void:
	if GameWorld.paused or not Story.is_story():
		return
	_time += delta
	var present: bool = bool(Data.ofOr("team1.monsters.wavepresent", false))
	if present and _wave_t >= 0.0:
		_wave_t += delta
		if not _fights_due.is_empty() and _wave_t >= _fights_due[0]:
			_fights_due.pop_front()
			say("fight")
	elif not present:
		_wave_t = -1.0
		_fights_due.clear()
	# Watch new monsters for their death.
	for m in get_tree().get_nodes_in_group("team1-monster"):
		var id: int = m.get_instance_id()
		if not _watched.has(id) and m.has_signal("died"):
			_watched[id] = true
			m.died.connect(_on_monster_died.bind(m))


func _on_monster_died(m) -> void:
	if not is_instance_valid(m) or _time - _last_death_t < DEATH_GAP or randf() >= death_chance:
		return
	_last_death_t = _time
	say("death", m.global_position + Vector2(0, -28))


# Shows one line of `kind` from the current stage's pool (or `forced`). Wave
# lines go above the dome (or to the top of the screen when the dome is off
# screen); last words go to `at`. `life` overrides how long it stays up.
func say(kind: String, at = null, forced: String = "", life: float = -1.0) -> String:
	var st: String = stage()
	var pool: Array = PleaData.pool(st, kind)
	var line: String = forced
	if line == "":
		if pool.is_empty():
			return ""
		line = pool.pick_random()
		if pool.size() > 1:
			while line == _last_line:
				line = pool.pick_random()
	_last_line = line
	var where: String = "world"
	var pos: Vector2
	if at != null:
		pos = at
	else:
		var dome = Level.getDome("team1")
		pos = (dome.global_position if dome != null else Vector2.ZERO) + DOME_OFFSET
		if not _on_screen(pos):
			where = "screen"
	if where == "world" and kind != "death" and is_instance_valid(_current):
		_current.queue_free()
	var node: Node = _make(line, st, kind, pos, where, life)
	if kind != "death":
		_current = node
	shown.append({"t": snappedf(_time, 0.01), "kind": kind, "stage": st, "line": line, "where": where})
	plea_shown.emit(kind, line, st)
	return line


# The line as it shows: runes for whatever the translators can't read yet (#92).
func render(line: String) -> String:
	return Runes.render(line, Runes.stage(), true)


func _on_screen(world_pos: Vector2) -> bool:
	var k = Keepers.first()
	if k == null or Level.viewports == null:
		return true
	var cam = Level.viewports.getPlayerCam(k.playerId)
	if cam == null:
		return true
	var vs: Vector2 = cam.get_viewport_rect().size / cam.zoom
	return Rect2(cam.get_screen_center_position() - vs / 2.0, vs).grow(-24).has_point(world_pos)


func _make(line: String, st: String, kind: String, pos: Vector2, where: String, life_override: float = -1.0) -> Node:
	var label: RichTextLabel = RichTextLabel.new()
	label.name = "PleaText"
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font: Font = Runes.font()
	label.add_theme_font_override("normal_font", font if font != null else load("res://gui/fonts/FontLarge.tres"))
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label.add_theme_color_override("default_color", RED if kind != "death" else RED.lerp(Color.WHITE, 0.25))
	label.add_theme_color_override("font_outline_color", Color("12060a"))
	# Bitmap runes take no outline; a hard shadow keeps them readable.
	label.add_theme_color_override("font_shadow_color", Color(0.05, 0.0, 0.02, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	var shake: int = SHAKE.get(st, 6)
	label.text = "[center][shake rate=18 level=%d connected=0]%s[/shake][/center]" % [shake, render(line)]
	var holder: Node2D = Node2D.new()
	holder.add_to_group("story-plea")
	holder.set_meta("kind", kind)
	holder.set_meta("line", line)
	holder.set_meta("stage", st)
	var width: float
	if where == "world":
		label.add_theme_font_size_override("normal_font_size", 19 if kind != "death" else 14)
		label.add_theme_constant_override("outline_size", 5)
		width = 460.0
		holder.z_index = 60
		holder.z_as_relative = false
		Level.map.add_child(holder)
		holder.global_position = pos
	else:
		label.add_theme_font_size_override("normal_font_size", 30)
		label.add_theme_constant_override("outline_size", 10)
		width = 1200.0
		_ui_layer.add_child(holder)
		holder.position = Vector2(get_viewport().get_visible_rect().size.x / 2.0, 70)
		label.modulate = Color(1, 1, 1, 0.85)
	label.custom_minimum_size = Vector2(width, 0)
	label.position = Vector2(-width / 2.0, -10)
	holder.add_child(label)
	# Burst in, hold, fade; last words drift up.
	holder.modulate.a = 0.0
	holder.scale = Vector2(1.25, 1.25)
	var t: Tween = holder.create_tween()
	t.tween_property(holder, "modulate:a", 1.0, 0.15)
	t.parallel().tween_property(holder, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var life: float = life_override if life_override > 0.0 else SECONDS.get(kind, 4.0)
	if kind == "death":
		t.parallel().tween_property(holder, "position:y", holder.position.y - 18.0, life)
	t.tween_interval(maxf(0.1, life - 0.9) if kind != "death" else 0.0)
	t.tween_property(holder, "modulate:a", 0.0, 0.6)
	t.tween_callback(holder.queue_free)
	return holder
