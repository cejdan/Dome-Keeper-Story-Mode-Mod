extends Node

# Playtest harness (dev only; the whole dev/ folder is left out of release builds).
#
# Runs one scenario and exits. A scenario is a GDScript in dev/scenarios/<name>.gd
# that extends dev/scenario.gd: it names the boot (game mode, seed, ...) and has a
# `run(h)` coroutine that sets things up, sends timed input and captures results
# through this node's helpers. Launch with dev/playtest.ps1 <name>.
#
# Output folder (--out=<abs dir>): numbered screenshots, frame bursts, map
# overview PNGs, and log.json (events, state snapshots, errors).

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")

var scenario_name: String = ""
var out_dir: String = ""
var scenario = null
var events: Array = []
var shot_index: int = 0
var failed: bool = false
var _started: bool = false
var _t0: int = 0


func _ready() -> void:
	scenario_name = Story.user_arg("scenario")
	out_dir = Story.user_arg("out", ProjectSettings.globalize_path("res://").path_join("../playtest_out/" + scenario_name)).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var script = load(Story.MOD_DIR + "dev/scenarios/" + scenario_name + ".gd")
	if script == null:
		push_error("Harness: no scenario " + scenario_name)
		get_tree().quit(2)
		return
	scenario = script.new()
	_t0 = Time.get_ticks_msec()
	Options.pauseWhenOutOfFocus = false
	note("harness start", {"scenario": scenario_name, "out": out_dir, "user_dir": OS.get_user_data_dir(), "boot": scenario.boot()})


func _process(_delta: float) -> void:
	# Injected input is dropped while the game thinks it lost focus.
	InputSystem.game_not_in_focus = false
	if _started:
		return
	if scenario == null:
		return
	if scenario.boot().get("loadout", false):
		if Level.stage != null and Level.stage.get("initialized") == true:
			_started = true
			_run()
		return
	if Level.stage != null and Level.stage.get("keeperInputStarted") == true and Level.map != null and Level.map.isMapReady():
		_started = true
		_run()


func _run() -> void:
	note("scenario begin", {"seed": Level.levelSeed, "mode": Level.loadout.modeId if Level.loadout else ""})
	await scenario.run(self)
	finish()


func finish() -> void:
	note("scenario end", {"failed": failed})
	var f: FileAccess = FileAccess.open(out_dir.path_join("log.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"scenario": scenario_name, "failed": failed, "events": events}, "  "))
	f.close()
	Engine.time_scale = 1.0
	get_tree().quit(1 if failed else 0)


# ---------------------------------------------------------------- logging

func now() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0


func note(label: String, data = null) -> void:
	var e: Dictionary = {"t": snappedf(now(), 0.01), "label": label}
	if data != null:
		e["data"] = _plain(data)
	events.append(e)
	print("[harness] ", label, " ", JSON.stringify(e.get("data", "")))


# Records a check; a failed check marks the whole run failed (exit code 1).
func check(label: String, ok: bool, data = null) -> bool:
	note(("PASS " if ok else "FAIL ") + label, data)
	if not ok:
		failed = true
	return ok


func approx(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance


func _plain(v):
	if v is Vector2 or v is Vector2i:
		return [v.x, v.y]
	if v is Dictionary:
		var d: Dictionary = {}
		for k in v:
			d[str(k)] = _plain(v[k])
		return d
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_plain(x))
		return a
	if v is Object:
		return str(v)
	return v


# A state snapshot: keeper, inventory, money, waves, plus any extra Data keys.
func snap(label: String, extra_keys: Array = []) -> Dictionary:
	var s: Dictionary = {}
	var k = keeper()
	if k != null and Level.map != null:
		s["keeper_pos"] = k.global_position
		s["keeper_tile"] = Level.map.getTileCoord(k.global_position)
	for key: String in ["team1.inventory.iron", "team1.inventory.water", "team1.inventory.sand", "team1.inventory.money",
			"team1.monsters.wavecooldown", "team1.monsters.cycle", "team1.dome.health"]:
		s[key] = Data.ofOr(key, null)
	for key: String in extra_keys:
		s[key] = Data.ofOr(key, null)
	if Level.mode != null and Level.mode.has_method("getRunWeight"):
		s["run_weight"] = Level.mode.getRunWeight("team1")
	s["run_time"] = GameWorld.runTime
	s["focused"] = DisplayServer.window_is_focused()
	note("state " + label, s)
	return s


# ---------------------------------------------------------------- time

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func frames(n: int = 1) -> void:
	for i in n:
		await get_tree().process_frame


func speed(scale: float) -> void:
	Engine.time_scale = scale


# Waits until `cond` (a Callable returning bool) is true, at most `timeout` s.
func until(cond: Callable, timeout: float = 10.0) -> bool:
	var left: float = timeout
	while left > 0.0:
		if cond.call():
			return true
		await get_tree().create_timer(0.1).timeout
		left -= 0.1
	return cond.call()


# ---------------------------------------------------------------- input

func _key(action: String, pressed: bool) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var e: InputEventKey = ev.duplicate()
			e.pressed = pressed
			Input.parse_input_event(e)
			return
	push_error("Harness: no key for action " + action)


func down(action: String) -> void:
	_key(action, true)


func up(action: String) -> void:
	_key(action, false)


func hold(action: String, sec: float) -> void:
	down(action)
	await wait(sec)
	up(action)
	await frames(2)


func press(action: String) -> void:
	down(action)
	await frames(3)
	up(action)
	await frames(3)


# ---------------------------------------------------------------- capture

func shot(label: String) -> String:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var file: String = "%03d_%s.png" % [shot_index, label]
	shot_index += 1
	img.save_png(out_dir.path_join(file))
	note("shot " + file)
	return file


func burst(label: String, count: int, every: int = 1) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join("%03d_%s_f%02d.png" % [shot_index, label, i]))
		for j in every - 1:
			await get_tree().process_frame
	note("burst %03d_%s x%d" % [shot_index, label, count])
	shot_index += 1


# Draws the whole map's tile data as a picture, `scale` px per tile, using
# `colors` (resource id -> Color) on top of a biome-tinted rock colour. This is
# the "revealed map" view for maps too big for one in-game screenshot.
func map_png(label: String, colors: Dictionary = {}, scale: int = 6, tile_data = null, overlay: Dictionary = {}) -> String:
	var td = tile_data if tile_data != null else Level.map.tileData
	var rect: Rect2i = td.get_used_rect()
	var img: Image = Image.create(rect.size.x * scale, rect.size.y * scale, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.03, 0.03, 0.05))
	var base: Dictionary = {0: Color("#b9bcc4"), 1: Color("#3f8fe0"), 2: Color("#e04fb0"), 3: Color("#ffffff"), 4: Color("#ffe14d"),
		5: Color("#7a4d9c"), 6: Color("#ffe14d"), 7: Color("#ff9a3c"), 9: Color("#101018"), 19: Color("#000000")}
	for c: Vector2i in td.get_used_cells(0):
		var biome: int = td.get_biomev(c)
		var res: int = td.get_resourcev(c)
		var hard: int = td.get_hardnessv(c)
		var col: Color = Color.from_hsv(fmod(0.07 + biome * 0.11, 1.0), 0.35, 0.20 + 0.035 * hard)
		if overlay.has(c):
			col = overlay[c]
		elif colors.has(res):
			col = colors[res]
		elif base.has(res):
			col = base[res]
		img.fill_rect(Rect2i((c - rect.position) * scale, Vector2i(scale, scale)), col)
	var file: String = "%03d_%s.png" % [shot_index, label]
	shot_index += 1
	img.save_png(out_dir.path_join(file))
	note("map " + file, {"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
	return file


# ---------------------------------------------------------------- world helpers

func keeper():
	return Keepers.first()


func keeper_tile() -> Vector2i:
	return Level.map.getTileCoord(keeper().global_position)


func teleport_tile(coord: Vector2i) -> void:
	keeper().teleport(Level.map.getTilePos(coord))
	snap_camera()
	await frames(3)


# Moves the keeper's camera straight onto the keeper. The game's camera moves
# at most about twice the keeper's speed, so after a long teleport it would
# take many seconds to arrive.
func snap_camera() -> void:
	var k = keeper()
	if Level.viewports == null or k == null:
		return
	var cam = Level.viewports.getPlayerCam(k.playerId)
	if cam != null:
		cam.position = k.position + (cam.targetOffset if "targetOffset" in cam else Vector2.ZERO)


func disable_waves() -> void:
	for mm in Level.monstersByTeamId.values():
		mm.disabled = true


func enable_waves() -> void:
	for mm in Level.monstersByTeamId.values():
		mm.disabled = false


func reveal_all() -> void:
	Level.map.tileCoordsToReveal.append_array(Level.map.tileData.get_used_cells(MapData.LAYER_BIOME))
	Level.map.floodRevealTiles()
	await frames(5)


func reveal(coords: Array) -> void:
	Level.map.tileCoordsToReveal.append_array(coords)
	Level.map.floodRevealTiles()
	await frames(3)


func clear_tiles(coords: Array) -> void:
	var v: Array = []
	for c in coords:
		v.append(Vector2(c))
	Level.map.freeTiles(v)
	await frames(3)


# Clears a rectangle of tiles (inclusive corners) and moves the keeper into it.
func dig_room(top_left: Vector2i, bottom_right: Vector2i) -> void:
	var cells: Array = []
	for y in range(top_left.y, bottom_right.y + 1):
		for x in range(top_left.x, bottom_right.x + 1):
			cells.append(Vector2i(x, y))
	await reveal(cells)
	await clear_tiles(cells)


func set_inv(type: String, amount) -> void:
	Data.apply("team1.inventory." + type, amount)


func inv(type: String):
	return Data.ofOr("team1.inventory." + type, 0)


# Spawns `count` drops of `type` just above the dome's drop target, so they are
# delivered the way carried drops are.
func deliver(type: String, count: int = 1) -> void:
	var dome = Level.getDome("team1")
	var target = dome.getDropTarget(type)
	var pos: Vector2 = target.global_position if target != null else dome.global_position
	for i in count:
		Level.drops.network_spawn({"type": type, "position": pos + Vector2(randf_range(-4, 4), -14), "impulse": Vector2.ZERO})
		await frames(6)


# Buys an upgrade the way the shop does. Returns false when it is unknown or
# cannot be afforded (vanilla refuses it the same way).
func buy(upgrade_id: String) -> bool:
	var id: String = upgrade_id.to_lower()
	if not GameWorld.upgrades.has(id):
		for prefix: String in ["team1.", "player1."]:
			if GameWorld.upgrades.has(prefix + id):
				id = prefix + id
				break
	var ok: bool = GameWorld.upgrades.has(id) and GameWorld.canAfford(GameWorld.upgrades[id].get("cost", {}), "team1")
	GameWorld.buyUpgrade(id, "team1", keeper().playerId)
	await frames(3)
	note("buy " + id, {"ok": ok, "cost": GameWorld.upgrades.get(id, {}).get("cost", {})})
	return ok


# ---------------------------------------------------------------- map generation reports

# Generates a map's tile data from an archetype and seed without starting a run.
# Returns the MapData (free it with queue_free when done), or null on failure.
func generate_map(archetype: MapArchetype, gen_seed: int):
	var gen = load("res://content/map/generation/TileDataGenerator.tscn").instantiate()
	add_child(gen)
	gen.init(archetype, gen_seed, "team1")
	gen.generate()
	var ok: bool = gen.finishedSuccessful
	var td = gen.popTileData()
	gen.queue_free()
	if not ok:
		td.queue_free()
		return null
	return td


# Connected groups (4-neighbour) of cells holding resource `id`.
func deposits_of(td, id: int) -> Array:
	var left: Dictionary = {}
	for c: Vector2i in td.get_resource_cells_by_id(id):
		left[c] = true
	var groups: Array = []
	while left.size() > 0:
		var start: Vector2i = left.keys()[0]
		left.erase(start)
		var open: Array = [start]
		var group: Array = []
		while open.size() > 0:
			var c: Vector2i = open.pop_back()
			group.append(c)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if left.has(c + d):
					left.erase(c + d)
					open.append(c + d)
		groups.append(group)
	return groups
