extends Node

# Dev-only tentacle tests (#359, #364). Inert unless the game is launched with
# `-- --story --tentacles` (any keeper: `--keeper=keeper3`).
#
# `--tentacles` (the test room, #359): once the run starts, it digs a room
# under the dome, gives the keeper the boss gear, stops the monster waves and
# puts the keeper in the room with two tentacles built like the lava ocean's
# (map/tentacle_rig.gd):
#   - a platform tentacle: out of the left wall, waving up and down;
#   - a wall tentacle: up from the floor, swaying side to side, with the
#     ocean tentacles' flat, levelled tip.
# Keys: F6 calmer / F7 wilder (wake stage 0..4, `--wake=N` to start at one),
# F8 back into the room.
#
# `--tentacles=ocean` (#364): the real ones in the lava ocean. Gives the gear,
# stops the waves, reveals the ocean round the tentacles and puts the keeper
# on the left tentacle's tip. Keys: F6 / F7 one chain fewer / more broken
# (0..10, host only; `--chains=N` to start at a count), F8 onto the other
# tentacle's tip.
#
# The grip fix (claws and hook follow the segment they hold, the Beastmaster
# rides with its claws) is in the script extensions (extensions/content/
# keeper/), so both modes test the real thing.
#
# Lives in dev/, which release/package_mod.py leaves out of the mod.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const Rig = preload("res://mods-unpacked/flantor-StoryMode/map/tentacle_rig.gd")
static var _Rig = Rig  # calls go through this: lazy_preload makes const-preload calls slow
const Ocean = preload("res://mods-unpacked/flantor-StoryMode/map/ocean_tentacles.gd")
static var _Ocean = Ocean  # calls go through this: lazy_preload makes const-preload calls slow
const TentData = preload("res://mods-unpacked/flantor-StoryMode/data/tentacles.gd")

const T := 24.0                 # tile size, px
const ROOM_W := 30              # tiles: about one screen
const ROOM_H := 16
const MARGIN := 3               # tiles of plain rock kept round the room
# How far each tip swings each way at stage 4 (px); the stages are the
# ocean's (data/tentacles.gd WAKE_SHARE, WAKE_SPEED).
const PLAT_SWEEP := 96.0
const WALL_SWEEP := 72.0

var wake: int = 0
var room: Rect2i = Rect2i()     # tile rect, empty until built
var rigs: Array = []
var ocean_mode: bool = false
var ocean = null                # map/ocean_tentacles.gd, in ocean mode
var _map: Node = null
var _label: Label
var _wave_timer: float = 0.0
var _tip_i: int = 0


func _ready() -> void:
	if not OS.has_feature("editor") or not _Story.has_user_arg("tentacles"):
		queue_free()
		return
	ocean_mode = _Story.user_arg("tentacles", "") == "ocean"
	wake = clampi(int(_Story.user_arg("wake", "0")), 0, 4)   # `--wake=3` starts wilder
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(12, 40)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)


func _process(delta: float) -> void:
	if _map != null and not is_instance_valid(_map):
		# The run ended: the rigs went with the map.
		_map = null
		rigs.clear()
		ocean = null
		room = Rect2i()
	if _map == null:
		_label.text = ""
		var k = _Story.local_keeper()
		# Wait for a real view too: early on, an off-screen harness window
		# reports a visible rect of height -2^31, and vanilla's tile-break
		# particles (Tile.position_in_view) then log "Rect2 size is negative"
		# for every tile the dig breaks.
		var map_ok: bool = Level.map != null and is_instance_valid(Level.map) and Level.map.is_inside_tree()
		# And for the lava and gas fields (added once the map is ready), so
		# the room can keep clear of their magma and gas rock.
		var fields_ok: bool = map_ok and (not _Story.is_story() or (Level.map.has_node("StoryLavaField") and Level.map.has_node("StoryGasField")))
		if fields_ok and Level.map.get_viewport().get_visible_rect().size.y > 0.0 and k != null and is_instance_valid(k) and Level.stage != null:
			if ocean_mode:
				if _Ocean.find() == null:
					return
				_map = Level.map
				_build_ocean()
			else:
				_map = Level.map
				_build()
		return
	_wave_timer -= delta
	if _wave_timer <= 0.0:
		_wave_timer = 5.0
		_stop_waves()
	if ocean_mode:
		_label.text = "Ocean tentacles (#364) · %d/%d chains broken · F6 fewer · F7 more · F8 the other tip" % [_Ocean.chains_broken(), TentData.CHAINS]
	else:
		_label.text = "Tentacle test (#359) · wake %d/4 · F6 calmer · F7 wilder · F8 back to the room" % wake


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if ocean_mode:
		if ocean == null:
			return
		match event.keycode:
			KEY_F6:
				_Ocean.set_chains_broken(_Ocean.chains_broken() - 1)
			KEY_F7:
				_Ocean.set_chains_broken(_Ocean.chains_broken() + 1)
			KEY_F8:
				_tip_i = (_tip_i + 1) % maxi(1, ocean.rigs.size())
				put_keepers_on_tip(_tip_i)
		return
	if room == Rect2i():
		return
	match event.keycode:
		KEY_F6:
			set_wake(wake - 1)
		KEY_F7:
			set_wake(wake + 1)
		KEY_F8:
			put_keepers_in_room()


func set_wake(w: int) -> void:
	wake = clampi(w, 0, 4)
	for r in rigs:
		r.target_share = _Ocean.share_for(float(wake))
		r.target_speed = _Ocean.speed_for(float(wake))
	print("[tentacles] wake %d: %.2f of the full swing, wave speed %.1f" % [wake, _Ocean.share_for(float(wake)), _Ocean.speed_for(float(wake))])


# ---------------------------------------------------------------- the ocean

func _build_ocean() -> void:
	ocean = _Ocean.find()
	var dev = load(_Story.MOD_DIR + "dev/boss_dev.gd")
	if not _Story.has_user_arg("nogear"):
		var gear: Array = dev.give_gear()
		print("[tentacles] gear: " + ", ".join(PackedStringArray(gear)))
	_stop_waves()
	var cells: Array = []
	for p: Dictionary in ocean.places:
		var x: int = int(p["x"])
		for y in range(int(p["tip_row"]) - 3, int(p["base_row"]) + 1):
			for dx in range(-8, 9):
				cells.append(Vector2i(x + dx, y))
	_map.tileCoordsToReveal.append_array(cells)
	_map.floodRevealTiles()
	if _map.has_method("finish_flood"):
		_map.finish_flood()
	await get_tree().physics_frame
	await get_tree().physics_frame
	put_keepers_on_tip(0)


# Every local keeper just over tentacle `i`'s rounded tip, on the side facing
# the ocean's middle (the tips are not for standing on: they slide off, ready
# to wall-jump or grab).
func put_keepers_on_tip(i: int) -> void:
	if ocean == null or ocean.rigs.is_empty():
		return
	var r = ocean.rigs[clampi(i, 0, ocean.rigs.size() - 1)]
	# Where the tip is now by the rig's clock (it may not have posed yet).
	var top: Vector2 = r.pad_top_now()
	var side: float = 1.0 if r.base.x < 0.0 else -1.0
	var j: int = 0
	for k in _Story.local_keepers():
		k.teleport(top + Vector2(side * (r.pad_width * 0.5 + 10.0 + 16.0 * j), -14.0))
		ocean.refresh_near()
		var cam = Level.viewports.getPlayerCam(k.playerId) if Level.viewports != null else null
		if cam != null:
			cam.position = k.position
		j += 1


# ---------------------------------------------------------------- the room

func _build() -> void:
	var dev = load(_Story.MOD_DIR + "dev/boss_dev.gd")
	room = _find_room()
	_clear_hazards(room.grow(MARGIN))
	var cells: Array = []
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			cells.append(Vector2i(x, y))
	dev.carve(cells)
	print("[tentacles] room %s" % str(room))
	if not _Story.has_user_arg("nogear"):
		var gear: Array = dev.give_gear()
		print("[tentacles] gear: " + ", ".join(PackedStringArray(gear)))
	_stop_waves()
	# Platform: out of the left wall, 6 tiles over the floor, 10 tiles long,
	# waving up and down.
	var plat = _Rig.new()
	plat.name = "TentaclePlatform"
	plat.base = _tile_edge(Vector2i(room.position.x, room.position.y + 9), Vector2(-0.5, 0.0)) + Vector2(-6, 0)
	plat.base_angle = 0.0
	plat.count = 10
	plat.seg_len = 24.0
	plat.width0 = 30.0
	plat.width1 = 16.0
	plat.sweep = PLAT_SWEEP
	plat.pad_width = 22.0
	plat.pad_height = 14.0
	# Wall: up from the floor at the right, 12 tiles tall, swaying side to
	# side, its pad kept level like the ocean's.
	var wall = _Rig.new()
	wall.name = "TentacleWall"
	wall.base = _tile_edge(Vector2i(room.position.x + 21, room.end.y - 1), Vector2(0.0, 0.5)) + Vector2(0, 6)
	wall.base_angle = -PI / 2.0
	wall.count = 11
	wall.seg_len = 24.0
	wall.width0 = 32.0
	wall.width1 = 18.0
	wall.sweep = WALL_SWEEP
	wall.pad_width = 24.0
	wall.pad_height = 16.0
	wall.tip_level = TentData.TIP_LEVEL
	wall.phase = 1.7
	for r in [plat, wall]:
		r.wave_k = 0.55
		r.z_index = 2
		_map.add_child(r)
		rigs.append(r)
	set_wake(wake)
	for r in rigs:
		r.snap_to_target()
	await get_tree().physics_frame
	put_keepers_in_room()
	# Metal, gates or special tiles that freeTiles would not take.
	for i in 3:
		for f in 12:
			await get_tree().physics_frame
		if not is_instance_valid(_map):
			return
		dev.carve_leftovers(cells)
	# The dig drops the room's ore: sweep it away, so nothing litters the floor
	# or rides the tentacles.
	var world := Rect2(_map.getTilePos(Vector2(room.position)) - Vector2(T, T) * 0.5, Vector2(room.size) * T)
	var swept: int = 0
	if Level.drops != null and is_instance_valid(Level.drops):
		for d in Level.drops.get_children():
			if d is Node2D and world.has_point(d.global_position):
				d.queue_free()
				swept += 1
	print("[tentacles] swept %d drops from the room" % swept)


# The first spot under the dome, 10+ tiles down, with no lava pool, magma, lava,
# gas rock or ocean within MARGIN tiles of the room.
func _find_room() -> Rect2i:
	var avoid: Dictionary = {}
	for pool in _map.tileData.get_meta("story_pools", []):
		for c in pool:
			avoid[Vector2i(c)] = true
	if _map.has_node("StoryGasField"):
		for c in _map.get_node("StoryGasField").rock:
			avoid[Vector2i(c)] = true
	# Magma rock and standing lava (lava/lava_field.gd): a dig next to either
	# floods the room.
	if _map.has_node("StoryLavaField"):
		var lava = _map.get_node("StoryLavaField")
		for d in [lava.magma, lava.mass, lava.sources]:
			for c in d:
				avoid[Vector2i(c)] = true
	var ocean_meta: Dictionary = _map.tileData.get_meta("story_ocean", {})
	var ocean_top: int = int(ocean_meta.get("top", 1 << 20))
	print("[tentacles] keeping clear of %d hazard cells" % avoid.size())
	for y0 in range(10, 200, 2):
		if y0 + ROOM_H + MARGIN >= ocean_top:
			break
		for x0 in [-ROOM_W / 2, -ROOM_W / 2 - 8, -ROOM_W / 2 + 8, -ROOM_W / 2 - 16, -ROOM_W / 2 + 16]:
			if _clear(avoid, x0, y0):
				return Rect2i(x0, y0, ROOM_W, ROOM_H)
	# The map is dense with pockets: take the spot under the dome and clear
	# what's near it (_clear_hazards).
	return Rect2i(-ROOM_W / 2, 10, ROOM_W, ROOM_H)


# Dev room only: turns magma, lava and gas rock in and around the room into
# plain rock and empties any lava or gas there, so the dig doesn't flood it.
func _clear_hazards(area: Rect2i) -> void:
	var n: int = 0
	var lava = _map.get_node_or_null("StoryLavaField")
	var gas = _map.get_node_or_null("StoryGasField")
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := Vector2i(x, y)
			for f in [lava, gas]:
				if f == null:
					continue
				for key in ["magma", "rock", "mass", "sources"]:
					if key in f and f.get(key).has(c):
						f.get(key).erase(c)
						n += 1
			if lava != null and "_shown_dirty" in lava:
				lava._shown_dirty[c] = true
	if lava != null and lava.has_method("wake_all"):
		lava.wake_all()
	print("[tentacles] cleared %d hazard cells round the room" % n)


func _clear(avoid: Dictionary, x0: int, y0: int) -> bool:
	for y in range(y0 - MARGIN, y0 + ROOM_H + MARGIN):
		for x in range(x0 - MARGIN, x0 + ROOM_W + MARGIN):
			if avoid.has(Vector2i(x, y)):
				return false
	return true


# A world point on tile `c`, offset by `f` tiles from its centre.
func _tile_edge(c: Vector2i, f: Vector2) -> Vector2:
	return _map.getTilePos(Vector2(c)) + f * T


func put_keepers_in_room() -> void:
	var i: int = 0
	for k in _Story.local_keepers():
		var c := Vector2i(room.position.x + 14 + 2 * i, room.end.y - 2)
		k.teleport(_map.getTilePos(Vector2(c)))
		var cam = Level.viewports.getPlayerCam(k.playerId) if Level.viewports != null else null
		if cam != null:
			cam.position = k.position
		i += 1


func _stop_waves() -> void:
	for mm in Level.monstersByTeamId.values():
		mm.disabled = true
