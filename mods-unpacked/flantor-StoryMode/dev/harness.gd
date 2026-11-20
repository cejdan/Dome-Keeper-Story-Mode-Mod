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

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow

var scenario_name: String = ""
var out_dir: String = ""
var scenario = null
var events: Array = []
var shot_index: int = 0
var failed: bool = false
var _started: bool = false
var _t0: int = 0


func _ready() -> void:
	scenario_name = _Story.user_arg("scenario")
	out_dir = _Story.user_arg("out", ProjectSettings.globalize_path("res://").path_join("../playtest_out/" + scenario_name)).simplify_path()
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
	if scenario.boot().get("netjoin", false):
		_client_choose_keeper()
	if scenario.boot().get("title", false):
		# The title screen (#231): the scenario presses its buttons.
		var ts = StageManager.currentStage
		if is_instance_valid(ts) and ts.has_method("_on_splitscreen_button_pressed") and not StageManager.isSwitchingStage():
			_started = true
			_run()
		return
	if scenario.boot().get("loadout", false):
		if is_instance_valid(Level.stage) and Level.stage.get("initialized") == true:
			_started = true
			_run()
		return
	if is_instance_valid(Level.stage) and Level.stage.get("keeperInputStarted") == true and is_instance_valid(Level.map) and Level.map.isMapReady():
		_started = true
		_run()


func _run() -> void:
	mute_beats()
	note("scenario begin", {"seed": Level.levelSeed, "mode": Level.loadout.modeId if Level.loadout else ""})
	await scenario.run(self)
	finish()


# Story beats and miners' logs (#94) pause the game, so scenarios that don't
# test them start with every one marked played. boot() returns `beats: true`
# to keep them. Beat state is the host's (Data syncs it to clients), so a
# client instance (#223) leaves it alone; a host scenario that boots in the
# loadout calls this once its run has started.
func mute_beats() -> void:
	if not multiplayer.is_server():
		return
	if not scenario.boot().get("beats", false) and _Story.is_story():
		var ids: PackedStringArray = []
		for b: Dictionary in load(Story.MOD_DIR + "data/beats.gd").BEATS + load(Story.MOD_DIR + "data/logs.gd").LOGS:
			if b["id"] != "keeper_welcome" or not scenario.boot().get("welcome", false):
				ids.append(b["id"])
		Data.apply("team1.story.beatsplayed", ",".join(ids))
		note("story beats muted (boot has no beats: true)")
	elif not scenario.boot().get("welcome", false) and _Story.is_story():
		var played: Array = Array(str(Data.ofOr("team1.story.beatsplayed", "")).split(",", false))
		if not played.has("keeper_welcome"):
			played.append("keeper_welcome")
			Data.apply("team1.story.beatsplayed", ",".join(PackedStringArray(played)))


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
	# An action bound to the mouse only (keeper3's rope, #297): its button, where
	# the mouse is (aim_mouse puts it there).
	for ev in InputMap.action_get_events(action):
		if ev is InputEventMouseButton:
			var m: InputEventMouseButton = ev.duplicate()
			m.pressed = pressed
			m.position = get_viewport().get_mouse_position()
			m.global_position = m.position
			Input.parse_input_event(m)
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


# Gamepad input for splitscreen (#231): vanilla's device index for a gamepad is
# its joypad device + 1 (InputSystem.getDeviceIndex), so `index` 1 is joypad 0.
# Puts the mouse over `world_pos` in keeper `k`'s view (default: the first local
# keeper), the way a player aims with the mouse (#297: keeper3's kunai and
# rope aim at the mouse when it plays on the keyboard).
func aim_mouse(world_pos: Vector2, k = null) -> void:
	if k == null:
		k = keeper()
	var vp: Viewport = k.get_viewport()
	var at: Vector2 = vp.get_canvas_transform() * world_pos
	vp.warp_mouse(at)
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	vp.push_input(ev, true)


func pad(index: int, action: String, pressed: bool) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			var e: InputEventJoypadButton = ev.duplicate()
			e.device = index - 1
			e.pressed = pressed
			e.pressure = 1.0 if pressed else 0.0
			Input.parse_input_event(e)
			return
	push_error("Harness: no gamepad button for action " + action)


func pad_hold(index: int, action: String, sec: float) -> void:
	pad(index, action, true)
	await wait(sec)
	pad(index, action, false)
	await frames(2)


# A gamepad keeper walks and drills with the left stick, not the d-pad.
func pad_stick(index: int, dir: Vector2, sec: float) -> void:
	for axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		var e := InputEventJoypadMotion.new()
		e.device = index - 1
		e.axis = axis
		e.axis_value = dir.x if axis == JOY_AXIS_LEFT_X else dir.y
		Input.parse_input_event(e)
	await wait(sec)
	for axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
		var e := InputEventJoypadMotion.new()
		e.device = index - 1
		e.axis = axis
		e.axis_value = 0.0
		Input.parse_input_event(e)
	await frames(2)


func pad_press(index: int, action: String) -> void:
	pad(index, action, true)
	await frames(3)
	pad(index, action, false)
	await frames(3)


# Splitscreen loadout (#231, boot `splitscreen: true`): each device that
# presses a key joins as a local keeper, as a player's does. Index 0 is the
# keyboard, 1.. gamepads. True once that device's keeper stands in the loadout.
func join_device(index: int) -> bool:
	for i in 4:
		if index == 0:
			await press("ui_select")
		else:
			await pad_press(index, "ui_select")
		if await until(func(): return Keepers.getLocalKeeperByDeviceId(index) != null, 4.0):
			return true
	return false


# This instance's keepers (splitscreen: one per device).
func local_keepers() -> Array:
	return Keepers.local.getAll().filter(func(k): return is_instance_valid(k))


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


# ---------------------------------------------------------------- keeper choice (#232)
# Vanilla's keeper choice (DeviceSelectionStage) opens when a host loads an
# online save (every player walks to a saved keeper; the host starts) and for a
# client that joins a run under way (it picks a keeper whose player left and
# starts itself, clientOnlyMode). Scenarios can't walk there, so they pick by
# call: the host takes the saved keeper that was the host's (peer 1), a client
# joining a run under way a free one.
#
# Keepers.local is no help here: it can hold another player's keeper once the
# host has swapped keepers. This instance's keeper is found by its lobby player
# id (the stand-in "player10x") or by the stage's peer/device map once chosen.

var _choose_t := 0.0
var _choose_started := false
var _choose_seen := ""


# The free saved keeper (LoadoutKeeper) for this instance, or null.
func free_saved_keeper(host: bool):
	var st = Level.stage
	if not is_instance_valid(st) or not st is DeviceSelectionStage:
		return null
	var taken: Array = st.playerIdByPeerDeviceId.values()
	var free: Array = Level.loadout.keeperTemplates.filter(func(lk): return not taken.has(lk.playerId))
	if free.is_empty():
		return null
	var mine: Array = free.filter(func(lk): return (lk.peerId == 1) == host)
	return mine[0] if not mine.is_empty() else free[0]


# This instance's keeper in the keeper choice, or null.
func choice_keeper():
	var st = Level.stage
	var me: int = multiplayer.get_unique_id()
	var want: Array = []
	if is_instance_valid(st) and st is DeviceSelectionStage:
		for key in st.playerIdByPeerDeviceId:
			if str(key).begins_with("%d-" % me):
				want.append(st.playerIdByPeerDeviceId[key])
	for m in Lobby.members:
		if m.peer_id == me:
			want.append("player%d" % m.player_id)
	for pid in want:
		for k in Keepers.all.keepers:
			if is_instance_valid(k) and k.playerId == pid and not k.is_queued_for_deletion():
				return k
	return null


# Walks this instance's keeper into a saved keeper (one try; true if asked).
func choose_keeper(host: bool) -> bool:
	var st = Level.stage
	var k = choice_keeper()
	if not is_instance_valid(st) or not st is DeviceSelectionStage or not st.initialized or k == null or not k.isMovementDummy:
		return false
	var lk = free_saved_keeper(host)
	if lk == null:
		return false
	note("keeper choice: taking " + lk.playerId, {"client only": st.clientOnlyMode, "taken": st.playerIdByPeerDeviceId, "keeper": k.playerId, "lobby": lobby_rows()})
	st.changeKeeper(k, lk)
	return true


# Walks this instance's keeper into a free saved keeper's choice in the keeper
# choice and uses it, as a player does (#251): teleported onto the choice,
# then the keeper's own use. Returns the saved keeper's playerId it went for,
# or "" if there was nothing to walk into yet.
func walk_into_choice(host: bool, want: String = "") -> String:
	var st = Level.stage
	var k = choice_keeper()
	if not is_instance_valid(st) or not st is DeviceSelectionStage or not st.initialized or k == null or not k.isMovementDummy:
		return ""
	var lk = free_saved_keeper(host)
	if want != "":
		lk = null
		for l in Level.loadout.keeperTemplates:
			if l.playerId == want and not st.playerIdByPeerDeviceId.values().has(want):
				lk = l
	if lk == null or not st.containerByPlayerId.has(lk.playerId):
		return ""
	var choice = st.containerByPlayerId[lk.playerId]
	if choice.disabled:
		return ""
	note("keeper choice: walking into " + lk.playerId, {"keeper": k.playerId, "taken": st.playerIdByPeerDeviceId, "lobby": lobby_rows()})
	k.teleport(choice.get_global_rect().get_center())
	await wait(1.0)
	if not is_instance_valid(k):
		return ""
	var used: bool = k.useHit()
	note("keeper choice: used " + lk.playerId, {"handled": used, "focussed": str(k.focussedUsable.get_parent().id) if is_instance_valid(k.focussedUsable) and k.focussedUsable.get_parent().get("id") != null else ""})
	return lk.playerId if used else ""


func lobby_rows() -> Array:
	return Lobby.members.map(func(m): return [m.peer_id, m.device_id, m.player_id])


func _client_choose_keeper() -> void:
	var st = Level.stage
	if not is_instance_valid(st) or not st is DeviceSelectionStage or not st.initialized or _choose_started:
		return
	var t: float = now()
	if t - _choose_t < 1.0:
		return
	_choose_t = t
	var k = choice_keeper()
	var seen := str([k.playerId if k != null else "", k.isMovementDummy if k != null else null, st.playerIdByPeerDeviceId, lobby_rows(), st.clientOnlyMode,
		Keepers.all.keepers.filter(func(x): return is_instance_valid(x)).map(func(x): return [x.playerId, x.peerId, x.deviceId, x.isMovementDummy])])
	if seen != _choose_seen:
		_choose_seen = seen
		note("keeper choice (client)", seen)
	if k == null:
		return
	if k.isMovementDummy:
		# Joining a run under way. (In a loaded save's keeper choice a client
		# scenario walks into its keeper itself, walk_into_choice(); t251.
		# t232_mp_load_host still picks for the client from the host.)
		if st.clientOnlyMode:
			choose_keeper(false)
	elif st.clientOnlyMode:
		# Joining a run under way: this client starts itself.
		_choose_started = true
		note("keeper choice: joining the run as " + k.playerId)
		st.clientStartRunSelected()


# ---------------------------------------------------------------- world helpers

func keeper():
	return Keepers.first()


func keeper_tile() -> Vector2i:
	return Level.map.getTileCoord(keeper().global_position)


func teleport_tile(coord: Vector2i, k = null) -> void:
	if k == null:
		k = keeper()
	k.teleport(Level.map.getTilePos(coord))
	snap_camera(k)
	await frames(3)


# Moves the keeper's camera straight onto the keeper. The game's camera moves
# at most about twice the keeper's speed, so after a long teleport it would
# take many seconds to arrive.
func snap_camera(k = null) -> void:
	if k == null:
		k = keeper()
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
	if Level.map.has_method("finish_flood"):
		Level.map.finish_flood()
	await frames(5)


func reveal(coords: Array) -> void:
	Level.map.tileCoordsToReveal.append_array(coords)
	Level.map.floodRevealTiles()
	if Level.map.has_method("finish_flood"):
		Level.map.finish_flood()
	await frames(3)


func clear_tiles(coords: Array) -> void:
	var v: Array = []
	for c in coords:
		v.append(Vector2(c))
	# Online, a client breaks only tiles it has made: reveal them there too (#227).
	if Network.multiplayer_mode != Network.MultiplayerMode.OFFLINE_SINGLEPLAYER and multiplayer.is_server():
		for c in v:
			Level.map.networkRevealTile(c, 0.0)
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
# Buys `upgrade_id` as keeper `k` (default: the first local keeper) would in the
# shop: the team's entry, or `k`'s own (keeper-tree upgrades are per player,
# player2.drill1, player2.storyheatshield1; #265).
func buy(upgrade_id: String, k = null) -> bool:
	if k == null:
		k = keeper()
	var id: String = upgrade_id.to_lower()
	if not GameWorld.upgrades.has(id):
		for prefix: String in ["team1.", k.playerId + "."]:
			if GameWorld.upgrades.has(prefix + id):
				id = prefix + id
				break
	var ok: bool = GameWorld.upgrades.has(id) and GameWorld.canAfford(GameWorld.upgrades[id].get("cost", {}), "team1")
	GameWorld.buyUpgrade(id, "team1", k.playerId)
	await frames(3)
	note("buy " + id, {"ok": ok, "cost": GameWorld.upgrades.get(id, {}).get("cost", {})})
	return ok


# ---------------------------------------------------------------- story beats

# The open beat's box (not one still fading out), or null.
func beat_box():
	for n in get_tree().get_nodes_in_group("story-beat-box"):
		if is_instance_valid(n) and not n._closing:
			return n
	return null


# Waits for a story beat to open, lets each page type out, shoots every page
# (`<label>_p<n>`), and turns pages with select until the box is gone. Returns
# the beat's id ("" if none opened within `timeout`).
func read_beat(label: String, timeout: float = 10.0, shots: bool = true) -> String:
	var sb = load(Story.MOD_DIR + "beats/story_beats.gd")
	if not await until(func(): return sb.is_open(), timeout):
		return ""
	var id: String = sb.instance().open_id
	var page: int = 0
	while sb.is_open() and sb.instance().open_id == id and page < 12:
		var box = beat_box()
		await until(func(): return box == null or not is_instance_valid(box) or not box.is_revealing(), 12.0)
		await wait(0.5)
		if shots:
			await shot("%s_p%d" % [label, page])
		page += 1
		await press("ui_select")
		await wait(0.4)
	await until(func(): return not sb.is_open() or sb.instance().open_id != id, 3.0)
	note("beat read", {"id": id, "pages": page})
	return id


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
