extends Control

# A miner's data log (#94), shown like a beat (it pauses the game, once per
# run) but in the look of a salvaged suit pad, not the horror's voice: a
# cracked green terminal with scanlines and a faint flicker, a header naming
# where it was recovered, the log's title, and its lines typed out quickly.
# Same interface as BeatBox, so beats/story_beats.gd and the input processor
# drive both.

const LogData = preload("res://mods-unpacked/cejdan-StoryMode/data/logs.gd")
const Assets = preload("res://mods-unpacked/cejdan-StoryMode/util/assets.gd")

const GREEN := Color("2fbf78")
const GREEN_TEXT := Color("9ef5c8")
const GREEN_DIM := Color("1d6b47")
const BG := Color("06120c")
const CPS := 70.0
const PAGE_LINES := 5

var beat_id: String = ""
var tier: int = 0
var _text: RichTextLabel
var _hint: Label
var _reveal: Tween
var _pages: Array = []
var _page: int = 0
var _time: float = 0.0
var _closing: bool = false
var _panel: PanelContainer


func setup(id: String, _style_tier: int) -> void:
	beat_id = id


func _init() -> void:
	name = "StoryLogPopup"
	add_to_group("story-beat-box")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var log: Dictionary = LogData.by_id(beat_id)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.03, 0.02, 0.55)
	_full(dim)
	add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	_full(center)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.name = "LogFrame"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(BG, 0.97)
	sb.set_border_width_all(3)
	sb.border_color = GREEN_DIM
	sb.shadow_color = Color(GREEN, 0.18)
	sb.shadow_size = 16
	sb.set_content_margin_all(34)
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 14)
	_panel.add_child(col)
	var mono: Font = load("res://gui/fonts/FontNormalMonospace.tres")
	# Header: the pad icon and where the log was recovered (or the log's own
	# header line, for the keeper's company log).
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	var icon: TextureRect = TextureRect.new()
	icon.texture = Assets.tex("res://mods-unpacked/cejdan-StoryMode/art/items/datalog_icon.png")
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size = Vector2(42, 42)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)
	Style.init(icon)
	var where: Label = _label(mono, 20, GREEN)
	if log.has("header"):
		where.text = str(log["header"])
	else:
		where.text = "SALVAGED SUIT LOG  //  RECOVERED IN B%d  //  SIGNAL %d%%" % [int(log.get("biome", 0)) + 1, 91 - 9 * int(log.get("biome", 0))]
	where.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(where)
	var title: Label = _label(mono, 26, GREEN_TEXT)
	title.text = str(log.get("title", "")).to_upper()
	col.add_child(title)
	var rule: ColorRect = ColorRect.new()
	rule.color = GREEN_DIM
	rule.custom_minimum_size = Vector2(0, 2)
	col.add_child(rule)
	_text = RichTextLabel.new()
	_text.name = "LogText"
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(1080, 0)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_override("normal_font", mono)
	_text.add_theme_font_size_override("normal_font_size", 30)
	_text.add_theme_color_override("default_color", GREEN_TEXT)
	_text.add_theme_constant_override("line_separation", 12)
	col.add_child(_text)
	_hint = _label(mono, 18, GREEN)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.text = "> " + tr("story.beat.continue").to_upper()
	_hint.modulate.a = 0.0
	col.add_child(_hint)
	# Scanlines over the pad.
	var lines: TextureRect = TextureRect.new()
	lines.texture = _scanlines()
	lines.stretch_mode = TextureRect.STRETCH_TILE
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(lines)
	var body: Array = log.get("lines", [])
	for i in range(0, body.size(), PAGE_LINES):
		_pages.append("\n".join(PackedStringArray(body.slice(i, i + PAGE_LINES))))
	_set_page(0)
	modulate.a = 0.0


func _label(font: Font, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _full(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _scanlines() -> Texture2D:
	var img: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in 4:
		img.set_pixel(x, 0, Color(0, 0, 0, 0.28))
		img.set_pixel(x, 1, Color(0, 0, 0, 0.12))
	return ImageTexture.create_from_image(img)


func _set_page(i: int) -> void:
	_page = i
	_text.text = (_pages[i] if i < _pages.size() else "").replace("[", "[lb]")
	_text.visible_characters = 0


func _process(delta: float) -> void:
	_time += delta
	# A dying screen: a faint, uneven flicker.
	if _panel != null:
		var f: float = 0.94 + 0.06 * sin(_time * 37.0) * sin(_time * 3.1)
		if fmod(_time, 4.7) < 0.06:
			f = 0.7
		_panel.modulate = Color(f, f, f, 1.0)


func is_revealing() -> bool:
	return _text != null and _text.visible_ratio < 1.0


func finish_reveal() -> void:
	if _reveal != null:
		_reveal.kill()
	_text.visible_ratio = 1.0
	_show_hint()


func has_next_page() -> bool:
	return _page + 1 < _pages.size()


func next_page() -> void:
	_hint.modulate.a = 0.0
	_set_page(_page + 1)
	_start_reveal(0.1)


func page_count() -> int:
	return _pages.size()


func move_in() -> void:
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)
	_start_reveal(0.45)


func _start_reveal(delay: float) -> void:
	if _reveal != null:
		_reveal.kill()
	var chars: int = _text.get_total_character_count()
	_reveal = create_tween()
	_reveal.tween_interval(delay)
	_reveal.tween_property(_text, "visible_characters", chars, chars / CPS)
	_reveal.tween_callback(_show_hint)


func _show_hint() -> void:
	if _hint != null:
		create_tween().tween_property(_hint, "modulate:a", 0.8, 0.3)


func move_out() -> void:
	_closing = true
	var t: Tween = create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.2)
	t.tween_callback(queue_free)


func text() -> String:
	return "\n".join(PackedStringArray(_pages))
