extends Control

# The horror's story beat box, in one of four style tiers (#24). The voice
# rises with depth but always stays inviting:
#   1  calm      the vanilla panel, pale text, typed out gently
#   2  warm      violet panel (the boss chamber barrier's colours), soft glow,
#                a slow hypnotic wave, a faint violet dimming of the world
#   3  glowing   larger, brighter glow, the wave slower and deeper, a pulsing
#                border, and rare glitch flickers: something wrong underneath
#   4  awake     no panel: the screen sinks into violet dark, huge glowing
#                text, glitches and small shudders more often
# Red shaking text belongs to the monsters' pleas, never to the horror.
#
# The narrator (#137): a line starting with "> " describes what the keeper
# hears or thinks, in a plain, muted, slanted voice at three quarters size, the
# same in every tier, so the horror's own words stand out against it.
#
# The horror's volume (#145): its voice grows louder the deeper the keeper has
# been. At B2 it is a whisper, small white text below the narrator's size with
# a faint wave; each biome uncovered after that brings it closer to its tier's
# full style, which it reaches from B5 on (VOLUME_FULL_AT). The narrator never
# changes size.
#
# Text comes from the translation key story.beat.<id> (text/strings.gd), with
# the data file's English lines as a fallback, so it is always readable.

const Glitch = preload("res://mods-unpacked/cejdan-StoryMode/beats/fx_glitch.gd")

const VIOLET_DEEP := Color("2e1f8f")
const VIOLET := Color("6b5cff")
const VIOLET_LIGHT := Color("b8b0ff")
const VIOLET_SPARK := Color("eeeaff")
const NIGHT := Color("0b0620")

const NARRATION := "> "
const NARRATOR_COLOR := Color("c7bfb4")
const NARRATOR_SCALE := 0.75
# Slant of the narrator's synthetic italic (x shift per unit of height).
const NARRATOR_SLANT := 0.2

# Per tier: text size, colour, glow, width, BBCode wrap, typing speed (chars/s),
# backdrop dimming, glitch rate for the box's shudders.
const STYLES := {
	1: {"size": 36, "color": Color("ece6f5"), "glow": Color(0, 0, 0, 0), "glow_size": 0, "width": 860,
		"open": "", "close": "", "cps": 45.0, "dim": 0.0, "shudder": 0.0},
	2: {"size": 44, "color": VIOLET_LIGHT, "glow": Color(VIOLET, 0.45), "glow_size": 10, "width": 960,
		"open": "[wave amp=14 freq=1.4 connected=1]", "close": "[/wave]", "cps": 32.0, "dim": 0.28, "shudder": 0.0},
	3: {"size": 54, "color": Color("d9d3ff"), "glow": Color(Color("8a7cff"), 0.6), "glow_size": 14, "width": 1100,
		"open": "[wave amp=20 freq=0.9 connected=1][glitch rate=0.25]", "close": "[/glitch][/wave]", "cps": 26.0, "dim": 0.5, "shudder": 0.0},
	4: {"size": 96, "color": VIOLET_SPARK, "glow": Color(VIOLET, 0.75), "glow_size": 20, "width": 1500,
		"open": "[wave amp=26 freq=0.6 connected=1][glitch rate=0.7]", "close": "[/glitch][/wave]", "cps": 20.0, "dim": 0.84, "shudder": 0.7},
}

# The whisper: the horror's text at volume 0.
const WHISPER_SIZE := 20
const WHISPER_COLOR := Color("f6f4ff")
const WHISPER_WAVE_AMP := 9.0
const WHISPER_WAVE_FREQ := 1.6
# Deepest biome index (0 = B1, story_beats.gd DEEPEST) at volume 0, and the one
# where the voice reaches its full tier style.
const VOLUME_QUIET_AT := 1
const VOLUME_FULL_AT := 4

var beat_id: String = ""
var tier: int = 1
# 0 = whisper .. 1 = the tier's full style. Set from the depth on setup().
var volume: float = 1.0
var _style: Dictionary
var _text: RichTextLabel
var _hint: Label
var _frame: Control
var _panel_box: StyleBoxFlat
var _reveal: Tween
var _time: float = 0.0
var _closing: bool = false
var _pages: Array = []
var _page: int = 0

# A beat longer than this many lines is shown in pages; select turns the page.
const PAGE_LINES := 3
# Most text rows a page may take before its font shrinks to fit.
const MAX_ROWS := {1: 5, 2: 5, 3: 4, 4: 4}


func setup(id: String, style_tier: int) -> void:
	beat_id = id
	tier = clampi(style_tier, 1, 4)
	volume = volume_for(int(Data.ofOr("team1.story.deepest", 0)))


# How loud the horror is once the keeper has reached the biome index `deepest`.
static func volume_for(deepest: int) -> float:
	return clampf(float(deepest - VOLUME_QUIET_AT) / float(VOLUME_FULL_AT - VOLUME_QUIET_AT), 0.0, 1.0)


func _init() -> void:
	name = "StoryBeatPopup"
	add_to_group("story-beat-box")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_style = STYLES[tier]
	theme = load("res://gui/theme.tres")
	# The world sinks into violet dark behind the deeper tiers.
	if _style["dim"] > 0.0:
		var dim: ColorRect = ColorRect.new()
		dim.name = "Dim"
		dim.color = Color(NIGHT, _style["dim"])
		_full(dim)
		add_child(dim)
		var halo: TextureRect = TextureRect.new()
		halo.name = "Halo"
		halo.texture = _halo_texture(tier)
		halo.stretch_mode = TextureRect.STRETCH_SCALE
		_full(halo)
		add_child(halo)
	var center: CenterContainer = CenterContainer.new()
	_full(center)
	add_child(center)
	_frame = _make_frame()
	center.add_child(_frame)
	var col: VBoxContainer = VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 24 if tier < 4 else 48)
	_frame.add_child(col)
	_text = RichTextLabel.new()
	_text.name = "BeatText"
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(_style["width"], 0)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.install_effect(Glitch.new())
	var font: Font = load("res://gui/fonts/FontVeryLarge.tres" if tier >= 3 else "res://gui/fonts/FontLarge.tres")
	_text.add_theme_font_override("normal_font", font)
	var slanted: FontVariation = FontVariation.new()
	slanted.base_font = font
	slanted.variation_transform = Transform2D(Vector2(1, 0), Vector2(-NARRATOR_SLANT, 1), Vector2.ZERO)
	_text.add_theme_font_override("italics_font", slanted)
	_text.add_theme_color_override("default_color", _style["color"])
	if _style["glow_size"] > 0:
		_text.add_theme_constant_override("outline_size", _style["glow_size"])
		_text.add_theme_color_override("font_outline_color", _style["glow"])
	else:
		_text.add_theme_constant_override("outline_size", 6)
		_text.add_theme_color_override("font_outline_color", Color("221f1f"))
	_text.add_theme_constant_override("line_separation", 10 if tier < 4 else 22)
	col.add_child(_text)
	# Pages: a "---" line breaks the page; otherwise every PAGE_LINES lines.
	var group: PackedStringArray = []
	for l: String in lines_text().split("\n", false) + PackedStringArray(["---"]):
		if l.strip_edges() == "---" or group.size() == PAGE_LINES:
			if not group.is_empty():
				_pages.append("\n".join(group))
			group = []
		if l.strip_edges() != "---":
			group.append(l)
	_set_page(0)
	_hint = Label.new()
	_hint.name = "BeatHint"
	_hint.label_settings = load("res://gui/fontsettings/SmallFontSettings.tres")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if tier < 4 else HORIZONTAL_ALIGNMENT_CENTER
	_hint.text = tr("story.beat.continue")
	_hint.modulate = Color(VIOLET_LIGHT if tier > 1 else Color.WHITE, 0.0)
	col.add_child(_hint)
	# Vanilla's Style maps panels and colour rects through the world palette.
	# Only tier 1's vanilla panel wants that; the horror's violet is real colour.
	if tier == 1:
		Style.init(self)
	modulate.a = 0.0


# The beat's lines, one per line: the translation if there is one, else the
# data file's English.
func lines_text() -> String:
	var key: String = "story.beat." + beat_id
	var s: String = tr(key)
	if s == key:
		var b: Dictionary = load("res://mods-unpacked/cejdan-StoryMode/data/beats.gd").by_id(beat_id)
		s = "\n".join(PackedStringArray(b.get("lines", [])))
	return s


func _set_page(i: int) -> void:
	_page = i
	var page: String = _pages[i] if i < _pages.size() else ""
	# Shrink the font until the page fits its tier's rows (a rough estimate:
	# a character is about half the font size wide).
	var size: int = _style["size"]
	while size > 28:
		var rows: int = 0
		for l: String in page.split("\n"):
			var s: float = size * (NARRATOR_SCALE if is_narration(l) else 1.0)
			var per_row: float = maxf(1.0, _style["width"] / (s * 0.5))
			rows += maxi(1, ceili(l.length() / per_row))
		if rows <= MAX_ROWS[tier]:
			break
		size -= 4
	_text.add_theme_font_size_override("normal_font_size", size)
	_text.add_theme_font_size_override("italics_font_size", int(size * NARRATOR_SCALE))
	var tags: Array = _voice_tags(size)
	# Runs of the horror's lines share one effect wrap, so its wave stays connected.
	var parts: PackedStringArray = []
	var run: PackedStringArray = []
	for l: String in page.split("\n"):
		if is_narration(l):
			if not run.is_empty():
				parts.append(tags[0] + _escape("\n".join(run)) + tags[1])
				run = []
			parts.append("[i][color=#%s]%s[/color][/i]" % [NARRATOR_COLOR.to_html(false), _escape(narration_text(l))])
		else:
			run.append(l)
	if not run.is_empty():
		parts.append(tags[0] + _escape("\n".join(run)) + tags[1])
	_text.text = "[center]" + "\n".join(parts) + "[/center]"
	_text.visible_characters = 0


# The horror's wave and glitch per tier: [amp, freq, glitch rate] (0 = none),
# the numbers in STYLES' own open tags.
const VOICE_FX := {1: [0.0, 0.0, 0.0], 2: [14.0, 1.4, 0.0], 3: [20.0, 0.9, 0.25], 4: [26.0, 0.6, 0.7]}


# Open and close tags for the horror's lines at this beat's volume (#145): at
# full volume the tier's own tags; quieter, smaller and whiter, with the wave
# easing toward a faint whisper wave.
func _voice_tags(size: int) -> Array:
	if volume >= 1.0:
		return [_style["open"], _style["close"]]
	var fx: Array = VOICE_FX[tier]
	var px: int = int(round(lerpf(WHISPER_SIZE, size, volume)))
	var col: Color = WHISPER_COLOR.lerp(_style["color"], volume)
	var amp: float = lerpf(WHISPER_WAVE_AMP, fx[0], volume)
	var freq: float = lerpf(WHISPER_WAVE_FREQ, fx[1] if fx[1] > 0.0 else WHISPER_WAVE_FREQ, volume)
	var open: String = "[font_size=%d][color=#%s]" % [px, col.to_html(false)]
	var close: String = "[/color][/font_size]"
	if amp >= 0.5:
		open += "[wave amp=%.1f freq=%.2f connected=1]" % [amp, freq]
		close = "[/wave]" + close
	var glitch: float = fx[2] * volume
	if glitch > 0.0:
		open += "[glitch rate=%.2f]" % glitch
		close = "[/glitch]" + close
	return [open, close]


static func is_narration(line: String) -> bool:
	return line.begins_with(NARRATION)


static func narration_text(line: String) -> String:
	return line.substr(NARRATION.length()) if is_narration(line) else line


func has_next_page() -> bool:
	return _page + 1 < _pages.size()


func next_page() -> void:
	if _hint != null:
		_hint.modulate.a = 0.0
	_set_page(_page + 1)
	_start_reveal(0.15)


func page_count() -> int:
	return _pages.size()


func _escape(s: String) -> String:
	return s.replace("[", "[lb]")


func _full(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _make_frame() -> Control:
	var frame: PanelContainer = PanelContainer.new()
	frame.name = "BeatFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tier == 1:
		var sb: StyleBox = load("res://gui/panels/panel_outside.tres").duplicate()
		sb.set_content_margin_all(36)
		frame.add_theme_stylebox_override("panel", sb)
		return frame
	_panel_box = StyleBoxFlat.new()
	if tier == 4:
		_panel_box.bg_color = Color(0, 0, 0, 0)
		_panel_box.border_width_top = 0
	else:
		_panel_box.bg_color = Color(Color("140d33") if tier == 2 else NIGHT, 0.94)
		_panel_box.set_border_width_all(3 if tier == 2 else 4)
		_panel_box.border_color = VIOLET if tier == 2 else Color("8a7cff")
		_panel_box.shadow_color = Color(VIOLET, 0.35 if tier == 2 else 0.55)
		_panel_box.shadow_size = 18 if tier == 2 else 34
	_panel_box.set_content_margin_all(44 if tier < 4 else 0)
	frame.add_theme_stylebox_override("panel", _panel_box)
	return frame


func _halo_texture(t: int) -> Texture2D:
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(VIOLET_DEEP, 0.55 if t >= 3 else 0.3))
	g.set_color(1, Color(VIOLET_DEEP, 0.0))
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 0.5)
	tex.width = 128
	tex.height = 72
	return tex


func _process(delta: float) -> void:
	_time += delta
	if tier == 3 and _panel_box != null:
		# The border breathes.
		var p: float = 0.5 + 0.5 * sin(_time * 1.6)
		_panel_box.border_color = Color("8a7cff").lerp(VIOLET_SPARK, p * 0.5)
		_panel_box.shadow_size = int(26 + 14 * p)
	if _style.get("shudder", 0.0) > 0.0 and _frame != null:
		if Glitch.burst(_time, _style["shudder"]):
			var r: float = Glitch._rand(int(_time * 10.0) * 31)
			_frame.pivot_offset = _frame.size / 2.0
			_frame.rotation = (r - 0.5) * 0.012
			_frame.scale = Vector2.ONE * (1.0 + (r - 0.5) * 0.02)
		else:
			_frame.rotation = 0.0
			_frame.scale = Vector2.ONE


func is_revealing() -> bool:
	return _text != null and _text.visible_ratio < 1.0


func finish_reveal() -> void:
	if _reveal != null:
		_reveal.kill()
	_text.visible_ratio = 1.0
	_show_hint()


func move_in() -> void:
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35 if tier < 4 else 0.9)
	_start_reveal(0.25 if tier < 4 else 0.8)


func _start_reveal(delay: float) -> void:
	if _reveal != null:
		_reveal.kill()
	var chars: int = _text.get_total_character_count()
	_reveal = create_tween()
	_reveal.tween_interval(delay)
	_reveal.tween_property(_text, "visible_characters", chars, chars / float(_style["cps"]))
	_reveal.tween_callback(_show_hint)


func _show_hint() -> void:
	if _hint != null:
		create_tween().tween_property(_hint, "modulate:a", 0.65, 0.4)


func move_out() -> void:
	_closing = true
	var t: Tween = create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.25 if tier < 4 else 0.6)
	t.tween_callback(queue_free)


# Plain text of the beat, every page (for checks).
func text() -> String:
	return "\n".join(PackedStringArray(_pages))
