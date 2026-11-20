extends Control

# Narration cards for the endings (#96, #97): the screen goes dark and short
# lines of plain past-tense narration fade in one at a time, centred, like the
# last page of a book. Each card holds for a few seconds and moves on by
# itself; select moves on sooner. Same interface as the beat boxes, so
# BeatInputProcessor drives it.
#
# mood "doom": the dark deepens card by card while a violet glow rises from
#              below the screen (the ground opening like an eye).
# mood "saved": a soft dawn gold warms the bottom of the screen instead.

const HOLD := 4.2
const FADE := 0.8

var beat_id: String = ""
var tier: int = 0
var cards: Array = []
var mood: String = "doom"
var _i: int = -1
var _label: Label
var _dim: ColorRect
var _glow: TextureRect
var _closing: bool = false
var _busy: bool = false
var _t: Tween
var _auto: float = 0.0

signal finished


func setup(id: String, _tier: int) -> void:
	beat_id = id


func _init() -> void:
	name = "StoryEndingCards"
	add_to_group("story-beat-box")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.0, 0.03, 0.0)
	_full(_dim)
	add_child(_dim)
	_glow = TextureRect.new()
	var g: Gradient = Gradient.new()
	var c: Color = Color("6b5cff") if mood == "doom" else Color("ffc46b")
	g.set_color(0, Color(c, 0.0))
	g.set_color(1, Color(c, 0.55))
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 8
	tex.height = 128
	_glow.texture = tex
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_full(_glow)
	_glow.modulate.a = 0.0
	add_child(_glow)
	var center: CenterContainer = CenterContainer.new()
	_full(center)
	add_child(center)
	_label = Label.new()
	_label.name = "CardText"
	_label.add_theme_font_override("font", load("res://gui/fonts/FontLarge.tres"))
	_label.add_theme_font_size_override("font_size", 46)
	_label.add_theme_color_override("font_color", Color("eeeaf4") if mood == "doom" else Color("fff4e0"))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 8)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(1300, 0)
	_label.modulate.a = 0.0
	center.add_child(_label)
	# The cards run by themselves; input (if any) only moves them on sooner.
	move_in.call_deferred()


func _full(n: Control) -> void:
	n.set_anchors_preset(Control.PRESET_FULL_RECT)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE


func current_card() -> String:
	return cards[_i] if _i >= 0 and _i < cards.size() else ""


func _show(i: int) -> void:
	_i = i
	_busy = true
	_auto = 0.0
	var depth: float = float(i + 1) / maxf(1.0, cards.size())
	if _t != null:
		_t.kill()
	_t = create_tween()
	_t.tween_property(_label, "modulate:a", 0.0, FADE * 0.5 if i > 0 else 0.0)
	_t.tween_callback(func(): _label.text = cards[i])
	_t.tween_property(_dim, "color:a", 0.72 + 0.28 * depth, FADE)
	_t.parallel().tween_property(_glow, "modulate:a", depth if mood == "doom" else 0.6 + 0.4 * depth, FADE * 2.0)
	_t.parallel().tween_property(_label, "modulate:a", 1.0, FADE)
	_t.tween_callback(func(): _busy = false)


func _process(delta: float) -> void:
	if _busy or _closing or _i < 0:
		return
	_auto += delta
	if _auto >= HOLD:
		if has_next_page():
			next_page()
		else:
			_auto = -1000.0
			finished.emit()


# --- beat-box interface -----------------------------------------------------

func move_in() -> void:
	if _i >= 0:
		return
	modulate.a = 1.0
	_show(0)


func is_revealing() -> bool:
	return _busy


func finish_reveal() -> void:
	if _t != null:
		_t.custom_step(10.0)
	_busy = false


func has_next_page() -> bool:
	return _i + 1 < cards.size()


func next_page() -> void:
	_show(_i + 1)


func page_count() -> int:
	return cards.size()


func move_out() -> void:
	_closing = true
	var t: Tween = create_tween()
	t.tween_property(_label, "modulate:a", 0.0, 0.6)
	t.tween_callback(queue_free)


func text() -> String:
	return "\n".join(PackedStringArray(cards))
