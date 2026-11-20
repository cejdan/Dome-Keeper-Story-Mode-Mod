extends Node

# Dev-only shortcut for finding gas, inert unless the game is launched with
# `-- --gas` (with `--story`). F10 reveals the map, digs a short tunnel beside
# the next gas pocket (shallowest first, cycling) and puts the keeper in it.
# From there, drill toward the green cracks to let the gas out.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const FIELD_NAME := "StoryGasField"
const HINT_SECONDS := 5.0

var _index := -1
var _label: Label
var _hint_left := 0.0


func _ready() -> void:
	# A playtest scenario's boot() can ask for it too (`gas: true`, #272).
	if not _Story.has_user_arg("gas"):
		queue_free()
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(12, 40)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)
	_say("F10: jump to the next gas pocket")


func _process(delta: float) -> void:
	if _hint_left > 0.0:
		_hint_left -= delta
		if _hint_left <= 0.0:
			_label.text = ""


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		jump()


func _say(text: String) -> void:
	_label.text = text
	_hint_left = HINT_SECONDS
	print("[gasfinder] ", text)


# Gas rock cells grouped into connected pockets, shallowest first.
static func pockets(rock: Dictionary) -> Array:
	var seen := {}
	var out := []
	for c in rock:
		if seen.has(c):
			continue
		var group := []
		var stack := [c]
		seen[c] = true
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			group.append(cur)
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = cur + d
				if rock.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
		group.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
		out.append(group)
	out.sort_custom(func(a, b): return a[0].y < b[0].y or (a[0].y == b[0].y and a[0].x < b[0].x))
	return out


# A three-cell tunnel beside the pocket (left or right of one of its cells),
# clear of the pocket itself: [the cell next to the pocket, ...]. Empty if none.
static func tunnel_beside(map, pocket: Array) -> Array:
	for c in pocket:
		for side in [Vector2i.LEFT, Vector2i.RIGHT]:
			var cells: Array = []
			var ok := true
			for i in range(1, 4):
				var n: Vector2i = c + side * i
				if pocket.has(n) or map.tileData.get_biomev(n) < 0 or map.tileData.get_hardnessv(n) >= Data.HARDNESS_INDESTRUCTIBLE:
					ok = false
				cells.append(n)
			if ok:
				return cells
	return []


func jump() -> void:
	var map = Level.map
	if map == null or not is_instance_valid(map) or not map.has_node(FIELD_NAME):
		_say("No gas field yet (start a Story Mode run)")
		return
	var keeper = _Story.local_keeper()
	if keeper == null or not is_instance_valid(keeper):
		return
	var field = map.get_node(FIELD_NAME)
	var all := pockets(field.rock)
	if all.is_empty():
		_say("No gas pockets left on this map")
		return
	_index = (_index + 1) % all.size()
	var pocket: Array = all[_index]
	map.tileCoordsToReveal.append_array(map.tileData.get_used_cells(MapData.LAYER_BIOME))
	map.floodRevealTiles()
	# The reveal runs over several frames; finish it now, or the first jump's
	# tunnel is dug before its tiles exist.
	if map.has_method("finish_flood"):
		map.finish_flood()
	var cells: Array = tunnel_beside(map, pocket)
	if cells.is_empty():
		_say("Pocket %d/%d has no room beside it" % [_index + 1, all.size()])
		return
	var free: Array = []
	for c in cells:
		if not map.is_tile_empty(c) and not field.rock.has(c):
			free.append(Vector2(c))
	map.freeTiles(free)
	keeper.teleport(map.getTilePos(Vector2(cells[1])))
	if Level.viewports != null:
		var cam = Level.viewports.getPlayerCam(keeper.playerId)
		if cam != null:
			cam.position = keeper.position
	var toward: String = "left" if cells[0].x < cells[1].x else "right"
	_say("Pocket %d/%d: %d cells at row %d. Drill %s, into the green cracks" % [_index + 1, all.size(), pocket.size(), pocket[0].y, toward])
