extends Node

# Sale pops (#121): every piece the dome takes in pops its price over the dome,
# "+$5" for a piece of iron, so the player can see what each item is worth. A
# batch ripples out one pop at a time (three iron: +$5 +$5 +$5), at the pace
# the dome takes the pieces in. Sales of $100 or more pop half again as big.
# Miner bones pop their own value in bone white.
#
#   const SalePops = preload("res://mods-unpacked/cejdan-StoryMode/hud/sale_pops.gd")
#   SalePops.pop(5)                       # one mineral piece
#   SalePops.pop(300, SalePops.BONES)     # a set of bones
# pop() returns roughly how long until that pop shows.
#
# Does nothing outside a Story Mode run (the node only exists in one).

const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")

const GROUP := "story-sale-pops"
const GOLD := Color("ffe14d")
const BONES := Color("f1e9d4")
const OUTLINE := Color("1a1206")
# Where over the dome a pop starts (world px from the dome's origin), how far
# it rises and how long it lives.
const OFFSET := Vector2(0, -64)
const RISE := 34.0
const LIFE := 1.3
# Seconds between two pops of one batch, and the most that wait in line (a big
# batch speeds up rather than trailing on for seconds).
const GAP := 0.11
const MAX_WAITING := 12

var _waiting: Array = []   # [amount, color]
var _wait_t: float = 0.0
var _lane: int = 0
# Every pop shown this run, for checks: [{amount, t}]
var shown: Array = []
var _time: float = 0.0
var _font: FontFile


# Joystix, a pixel font with every ASCII glyph (the HUD's digit font has no
# "+"), unsmoothed so it stays crisp at whole multiples of 10 px
# (20 px: 2 screen px per font pixel).
func _pixel_font() -> FontFile:
	if _font == null:
		_font = (load("res://gui/fonts/joystix.monospace.ttf") as FontFile).duplicate()
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.hinting = TextServer.HINTING_NONE
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return _font


static func instance():
	var tree = Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return null
	return tree.get_first_node_in_group(GROUP)


# Queues a pop. Returns about how many seconds until it shows (0 when it
# shows on the next frame, or when there is nothing to show it).
static func pop(amount: int, color: Color = GOLD) -> float:
	var n = instance()
	if n == null or amount <= 0:
		return 0.0
	n._waiting.append([amount, color])
	return maxf(n._wait_t, 0.0) + GAP * (n._waiting.size() - 1)


func _ready() -> void:
	name = "StorySalePops"
	add_to_group(GROUP)


func _process(delta: float) -> void:
	_time += delta
	_wait_t -= delta
	if _waiting.is_empty() or _wait_t > 0.0:
		return
	var p: Array = _waiting.pop_front()
	_show(int(p[0]), p[1])
	_wait_t = GAP if _waiting.size() < MAX_WAITING else GAP * 0.4


func _show(amount: int, color: Color) -> void:
	var dome = Level.getDome("team1")
	if dome == null or Level.map == null:
		return
	var label: Label = Label.new()
	label.name = "SalePop"
	label.text = "+" + Minerals.dollars(amount)
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label.add_theme_font_override("font", _pixel_font())
	label.add_theme_font_size_override("font_size", 20 if amount < 100 else 30)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", 6 if amount < 100 else 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var holder: Node2D = Node2D.new()
	holder.add_to_group("story-sale-pop")
	holder.set_meta("amount", amount)
	holder.z_index = 61
	holder.z_as_relative = false
	Level.map.add_child(holder)
	holder.add_child(label)
	label.reset_size()
	label.position = Vector2(-label.size.x / 2.0, -label.size.y / 2.0)
	# Pops step between three lanes so a ripple doesn't stack on one spot.
	_lane = (_lane + 1) % 3
	var x: float = [-16.0, 0.0, 16.0][_lane] + randf_range(-4.0, 4.0)
	holder.global_position = dome.global_position + OFFSET + Vector2(x, 0)
	holder.scale = Vector2(1.6, 1.6)
	holder.modulate.a = 0.0
	var t: Tween = holder.create_tween()
	t.tween_property(holder, "modulate:a", 1.0, 0.08)
	t.parallel().tween_property(holder, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(holder, "position:y", holder.position.y - RISE, LIFE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(holder, "modulate:a", 0.0, 0.45).set_delay(LIFE - 0.45)
	t.tween_callback(holder.queue_free)
	shown.append({"amount": amount, "t": snappedf(_time, 0.01)})
