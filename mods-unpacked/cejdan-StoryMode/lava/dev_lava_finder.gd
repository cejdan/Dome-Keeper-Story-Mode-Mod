extends Node

# Dev-only shortcut for finding lava, inert unless the game is launched with
# `-- --lava`. F9 reveals the map, digs out the rock cell beside the next magma
# pocket (shallowest first, cycling) and puts the keeper in it. From there, drill
# toward the pocket to let the lava out.

const FIELD_NAME := "StoryLavaField"
const HINT_SECONDS := 4.0

var _index := -1
var _label: Label
var _hint_left := 0.0


func _ready() -> void:
	if not "--lava" in OS.get_cmdline_user_args():
		queue_free()
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(12, 12)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)
	_say("F9: jump to the next lava pocket")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--finderprobe="):
			_probe(arg.substr(14))


# Self-test: `-- --lava --finderprobe=<abs out dir>` presses F9 three times through
# the real input path, saves screenshots and a log, breaches the first pocket, then quits.
func _probe(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var lines: PackedStringArray = []
	while Level.stage == null or not Level.stage.keeperInputStarted:
		await get_tree().process_frame
	for mm in Level.monstersByTeamId.values():
		mm.disabled = true
	var map = Level.map
	var keeper = Keepers.first()
	while not map.has_node(FIELD_NAME):
		await get_tree().process_frame
	var field = map.get_node(FIELD_NAME)
	await _frames(60)
	lines.append("start: keeper %s pockets=%d" % [map.getTileCoord(keeper.global_position), _pockets(field.magma).size()])
	await _probe_shot(dir, "00_start")
	for i in 3:
		var ev := InputEventKey.new()
		ev.keycode = KEY_F9
		ev.pressed = true
		Input.parse_input_event(ev)
		await _frames(60)
		var kc: Vector2i = map.getTileCoord(keeper.global_position)
		var near := 999.0
		for c in field.magma:
			near = min(near, Vector2(c - kc).length())
		lines.append("F9 #%d: keeper %s open=%s nearest magma %.1f tiles; label='%s'" % [i + 1, kc, map.is_tile_empty(kc), near, _label.text])
		await _probe_shot(dir, "%02d_after_f9" % (i + 1))
	# Go back to the first pocket and breach it, to confirm lava comes out.
	_index = -1
	_jump()
	await _frames(60)
	var pocket: Array = _pockets(field.magma)[0]
	var cell: Vector2i = pocket[0]
	var best := 9999.0
	for c in pocket:
		var dd := Vector2(c - map.getTileCoord(keeper.global_position)).length()
		if dd < best:
			best = dd
			cell = c
	var t = map.getTile(Vector2(cell))
	if t != null and is_instance_valid(t):
		map.destroyTile("team1", "keeper1", t)
	await _frames(180)
	lines.append("breach %s: %s" % [cell, field.stats()])
	await _probe_shot(dir, "04_breached")
	var f := FileAccess.open(dir + "/finder.log", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _probe_shot(dir: String, shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, shot_name])


func _process(delta: float) -> void:
	if _hint_left > 0.0:
		_hint_left -= delta
		if _hint_left <= 0.0:
			_label.text = ""


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		_jump()


func _say(text: String) -> void:
	_label.text = text
	_hint_left = HINT_SECONDS
	print("[lavafinder] ", text)


func _jump() -> void:
	var map = Level.map
	if map == null or not is_instance_valid(map) or not map.has_node(FIELD_NAME):
		_say("No lava field yet (start a run launched with --lava)")
		return
	var keeper = Keepers.first()
	if keeper == null or not is_instance_valid(keeper):
		return
	var field = map.get_node(FIELD_NAME)
	var pockets := _pockets(field.magma)
	if pockets.is_empty():
		_say("No magma pockets left on this map")
		return
	_index = (_index + 1) % pockets.size()
	var pocket: Array = pockets[_index]

	map.tileCoordsToReveal.append_array(map.tileData.get_used_cells(MapData.LAYER_BIOME))
	map.floodRevealTiles()

	var spot = _standing_cell(map, field, pocket)
	if spot == null:
		_say("Pocket %d/%d has no reachable neighbor cell" % [_index + 1, pockets.size()])
		return
	var t = map.getTile(Vector2(spot))
	if t != null and is_instance_valid(t):
		map.destroyTile("team1", "keeper1", t)
	keeper.teleport(map.getTilePos(Vector2(spot)))
	# The game camera only pans at the keeper's walking speed, so snap it.
	var cam = _find_camera(get_tree().root)
	if cam != null:
		cam.position = keeper.global_position
	var target: Vector2i = pocket[0]
	_say("Pocket %d/%d: %d cells at row %d. Drill %s from here" % [
			_index + 1, pockets.size(), pocket.size(), target.y, _direction(spot, pocket)])


func _find_camera(n: Node):
	if n is KeeperCamera:
		return n
	for c in n.get_children():
		var r = _find_camera(c)
		if r:
			return r
	return null


# Magma cells grouped into connected pockets, shallowest first.
func _pockets(magma: Dictionary) -> Array:
	var seen := {}
	var out := []
	for c in magma:
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
				if magma.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
		group.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
		out.append(group)
	out.sort_custom(func(a, b): return a[0].y < b[0].y or (a[0].y == b[0].y and a[0].x < b[0].x))
	return out


# A non-magma cell touching the pocket that the keeper can stand in: prefers the
# cell above, then the sides, then below.
func _standing_cell(map, field, pocket: Array):
	for d in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
		for c in pocket:
			var n: Vector2i = c + d
			if n.y < field.MIN_Y or field.magma.has(n) or pocket.has(n):
				continue
			if map.is_tile_empty(n):
				return n
			var t = map.getTile(Vector2(n))
			if t != null and map.tileData.get_hardnessv(n) < Data.HARDNESS_INDESTRUCTIBLE:
				return n
	return null


func _direction(spot: Vector2i, pocket: Array) -> String:
	var best: Vector2i = pocket[0]
	for c in pocket:
		if (c - spot).length_squared() < (best - spot).length_squared():
			best = c
	var d: Vector2i = best - spot
	if d == Vector2i.DOWN:
		return "down"
	if d == Vector2i.UP:
		return "up"
	if d == Vector2i.LEFT:
		return "left"
	if d == Vector2i.RIGHT:
		return "right"
	return "toward (%d, %d)" % [d.x, d.y]
