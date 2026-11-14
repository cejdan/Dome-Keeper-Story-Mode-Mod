extends CenterContainer

# The story beat text box: the horror's lines on a vanilla panel, centred on
# screen, with a small "continue" hint. Plain styling for every tier; the tier
# looks are #24. Text comes from the translation key story.beat.<id>
# (text/strings.gd registers it from data/beats.gd), so it is always readable.

var beat_id: String = ""
var tier: int = 1
var _panel: PanelContainer


func setup(id: String, style_tier: int) -> void:
	beat_id = id
	tier = style_tier


func _init() -> void:
	name = "StoryBeatPopup"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	theme = load("res://gui/theme.tres")
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", load("res://gui/panels/panel_outside.tres"))
	_panel.custom_minimum_size = Vector2(900, 0)
	add_child(_panel)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	_panel.add_child(margin)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 28)
	margin.add_child(col)
	var text: Label = Label.new()
	text.name = "BeatText"
	text.label_settings = load("res://gui/fontsettings/LargeFontSettings.tres")
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(820, 0)
	var key: String = "story.beat." + beat_id
	text.text = tr(key)
	if text.text == key:
		# No translation for this locale yet: the data file's English lines.
		var b: Dictionary = load("res://mods-unpacked/cejdan-StoryMode/data/beats.gd").by_id(beat_id)
		text.text = "\n".join(PackedStringArray(b.get("lines", [])))
	col.add_child(text)
	var hint: Label = Label.new()
	hint.name = "BeatHint"
	hint.label_settings = load("res://gui/fontsettings/SmallFontSettings.tres")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.text = tr("story.beat.continue")
	col.add_child(hint)
	Style.init(self)
	modulate.a = 0.0


func move_in() -> void:
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25)


func move_out() -> void:
	var t: Tween = create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.2)
	t.tween_callback(queue_free)


func text() -> String:
	var l: Label = find_child("BeatText", true, false)
	return l.text if l != null else ""
