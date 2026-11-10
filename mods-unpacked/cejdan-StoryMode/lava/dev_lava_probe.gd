extends Node

# Dev-only playtest for the lava, inert unless launched with
# `-- --lava --lavaprobe=<abs out dir>`. It digs a small test mine, puts a magma
# pocket above it, breaches the pocket, and saves screenshots and a state log
# while the lava runs. Then it stands the keeper in the lava to test suit heat.

const FIELD_NAME := "StoryLavaField"

var out_dir := ""
var log_lines: PackedStringArray = []
var cam = null
var cam_target := Vector2.ZERO
var cam_zoom := 3.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lavaprobe="):
			out_dir = arg.substr(12)
	if out_dir == "":
		queue_free()
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()


var _burn_shot := false


func _process(_delta: float) -> void:
	if not _burn_shot and Level.map != null and is_instance_valid(Level.map) and Level.map.has_node(FIELD_NAME):
		var f = Level.map.get_node(FIELD_NAME)
		if f.heat > 60.0:
			_burn_shot = true
			_log("burning: heat=%.1f" % f.heat)
			_shot("03_burning")
	if cam != null and is_instance_valid(cam):
		cam.position = cam_target
		cam.zoom = Vector2.ONE * cam_zoom


func _log(s: String) -> void:
	print("[lavaprobe] ", s)
	log_lines.append(s)
	var f := FileAccess.open(out_dir + "/probe.log", FileAccess.WRITE)
	f.store_string("\n".join(log_lines) + "\n")
	f.close()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, shot_name])


func _wait(seconds: float) -> void:
	var frames := int(seconds * 60.0)
	for i in frames:
		await get_tree().physics_frame


func _dig(map, c: Vector2i) -> void:
	var t = map.getTile(Vector2(c))
	if t != null and is_instance_valid(t):
		map.destroyTile("team1", "keeper1", t)


func _run() -> void:
	while Level.stage == null or not Level.stage.keeperInputStarted:
		await get_tree().process_frame
	for mm in Level.monstersByTeamId.values():
		mm.disabled = true
	var map = Level.map
	var keeper = Keepers.first()
	while not map.has_node(FIELD_NAME):
		await get_tree().process_frame
	var field = map.get_node(FIELD_NAME)
	_log("mode=%s keeper at %s coord=%s" % [Level.loadout.modeId, keeper.global_position, map.getTileCoord(keeper.global_position)])
	_log("generated magma cells=%d rows=%s" % [field.magma.size(), _rows(field.magma)])

	map.tileCoordsToReveal.append_array(map.tileData.get_used_cells(MapData.LAYER_BIOME))
	map.floodRevealTiles()
	await _wait(0.3)

	# Coordinate round trip, which the breach handler relies on.
	var probe_c := Vector2i(2, 9)
	_log("round trip %s -> %s -> %s" % [probe_c, map.getTilePos(Vector2(probe_c)), map.getTileCoord(map.getTilePos(Vector2(probe_c)))])

	cam = _find_camera(get_tree().root)

	# --- shot of the generated pockets as the player would find them -----------
	if field.magma.size() > 0:
		var first: Vector2i = field.magma.keys()[0]
		cam_target = map.getTilePos(Vector2(first))
		cam_zoom = 4.0
		await _wait(0.5)
		await _shot("00_generated_pocket")

	# --- test mine -----------------------------------------------------------
	# Corridor at row 12, a drop shaft on the left into a basin at rows 15-16,
	# and a pocket two rows above the right end of the corridor.
	field.magma.clear()
	var ox := 0
	var corridor_y := 12
	for x in range(ox - 5, ox + 6):
		_dig(map, Vector2i(x, corridor_y))
	for y in range(corridor_y + 1, corridor_y + 5):
		_dig(map, Vector2i(ox - 4, y))
	for x in range(ox - 6, ox - 1):
		_dig(map, Vector2i(x, corridor_y + 4))
		_dig(map, Vector2i(x, corridor_y + 3))
	var pocket := []
	for c in [Vector2i(ox + 3, corridor_y - 1), Vector2i(ox + 4, corridor_y - 1), Vector2i(ox + 3, corridor_y - 2),
			Vector2i(ox + 4, corridor_y - 2), Vector2i(ox + 2, corridor_y - 2), Vector2i(ox + 4, corridor_y - 3)]:
		if map.getTile(Vector2(c)) != null:
			pocket.append(c)
	field.add_pocket(pocket)
	_log("test pocket cells=%d" % pocket.size())
	keeper.teleport(map.getTilePos(Vector2(ox - 1, corridor_y)))
	cam_target = map.getTilePos(Vector2(ox - 1, corridor_y + 1))
	cam_zoom = 3.0
	await _wait(1.0)
	await _shot("01_before_breach")

	# Breach: the keeper "drills" the pocket cell right above the corridor.
	_dig(map, Vector2i(ox + 3, corridor_y - 1))
	_log("breached; %s" % field.stats())
	var t := 0.0
	for step in [0.4, 0.6, 1.0, 1.5, 2.5, 4.0, 6.0, 8.0]:
		await _wait(step)
		t += step
		await _shot("02_flow_t%04.1f" % t)
		_log("t=%.1f %s min_row=%d" % [t, field.stats(), _min_row(field.mass)])

	_log("keeper: recalls=%d heat=%.1f at %s recall_pos=%s carried=%d" % [field.recalls, field.heat, keeper.global_position, field.recall_pos, keeper.carriedCarryables.size()])
	cam_target = keeper.global_position
	await _wait(0.5)
	await _shot("04_keeper_after")

	# --- long settle: lava should cool away --------------------------------------
	cam_target = map.getTilePos(Vector2(ox - 1, corridor_y + 1))
	Engine.time_scale = 8.0
	await _wait(240.0)
	Engine.time_scale = 1.0
	await _shot("05_after_240s")
	_log("after 240 s more: %s" % field.stats())
	_log("done")
	get_tree().quit()


func _rows(cells: Dictionary) -> String:
	var lo := 9999
	var hi := -9999
	for c in cells:
		lo = min(lo, c.y)
		hi = max(hi, c.y)
	return "%d..%d" % [lo, hi]


func _min_row(cells: Dictionary) -> int:
	var lo := 9999
	for c in cells:
		lo = min(lo, c.y)
	return lo


func _find_camera(n: Node):
	if n is KeeperCamera:
		return n
	for c in n.get_children():
		var r = _find_camera(c)
		if r:
			return r
	return null
