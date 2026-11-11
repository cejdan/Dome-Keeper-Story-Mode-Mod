extends HudElement

# The Story Mode balance, always on the HUD: "$1,234".

const Assets = preload("res://mods-unpacked/cejdan-StoryMode/util/assets.gd")
const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")

var _groups: HBoxContainer
var _flash: float = 0.0
var _flash_color: Color = Color.WHITE


func _init() -> void:
	name = "StoryMoneyHud"
	element_size = Vector2(4, 2)
	layoutWeights = Vector2(5, 0)
	layoutPriority = 3
	scale = Vector2(0.333, 0.333)
	add_theme_constant_override("margin_left", 6)
	add_theme_constant_override("margin_top", 6)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(row)
	var icon: TextureRect = TextureRect.new()
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = Assets.tex("res://mods-unpacked/cejdan-StoryMode/art/icon_money.png")
	icon.stretch_mode = TextureRect.STRETCH_KEEP
	row.add_child(icon)
	# The HUD font has digits but no comma, so thousands are shown as groups of
	# three digits with a small gap between them.
	_groups = HBoxContainer.new()
	_groups.add_theme_constant_override("separation", 6)
	row.add_child(_groups)


func init() -> void:
	super.init()
	Data.listen(self, teamId + ".inventory.money", true)


func propertyChanged(_property: String, oldValue, newValue) -> void:
	var amount: int = int(newValue) if newValue != null else 0
	var parts: PackedStringArray = Minerals.dollars(amount).substr(1).split(",")
	while _groups.get_child_count() > parts.size():
		var extra: Node = _groups.get_child(_groups.get_child_count() - 1)
		_groups.remove_child(extra)
		extra.queue_free()
	while _groups.get_child_count() < parts.size():
		var l: Label = Label.new()
		l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		l.add_theme_font_override("font", load("res://gui/fonts/FontHudPixelartMonospaced.tres"))
		l.label_settings = load("res://gui/fontsettings/HudPixelartMonospacedFontSettings.tres")
		_groups.add_child(l)
	var digits: int = 0
	for i in parts.size():
		_groups.get_child(i).text = parts[i]
		digits += parts[i].length()
	# One HUD unit is 18 px here: margin 6 + icon 24 + gap 8, about 17 px a digit, 6 px a group gap.
	var units: int = maxi(4, ceili((38.0 + 17.0 * digits + 6.0 * (parts.size() - 1)) / 18.0))
	if int(element_size.x) != units:
		element_size.x = units
		request_rebuild.emit()
	if oldValue != null and newValue != null and int(newValue) != int(oldValue):
		# Gains pulse bright, losses pulse red.
		_flash = 1.0
		_flash_color = Color(1.6, 1.6, 1.2) if int(newValue) > int(oldValue) else Color(2.2, 0.4, 0.4)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.0)
		_groups.modulate = Color.WHITE.lerp(_flash_color, _flash)
