extends Node

# Dev-only test room for moving tentacles (#359, from #324): does climbing a
# living, waving tentacle feel good with every keeper? Inert unless the game
# is launched with `-- --story --tentacles` (any keeper: `--keeper=keeper3`).
#
# Once the run starts, it digs a room under the dome, gives the keeper the
# boss gear, stops the monster waves and puts the keeper in the room with two
# tentacles made of moving bodies (not tiles):
#   - a platform tentacle: out of the left wall, waving up and down;
#   - a wall tentacle: up from the floor, swaying side to side.
# Keys: F6 calmer / F7 wilder (wake stage 0..4, as each broken chain would free
# them a little more), F8 back into the room.
#
# The test carries the grip fix from #324: both keepers grip a fixed point in
# the world, so a Beastmaster claw or an Infiltrator hook on a segment is moved
# with that segment each physics frame (before the keepers move), and a
# Beastmaster's body rides along with its claws.
#
# Lives in dev/, which release/package_mod.py leaves out of the mod.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow

const T := 24.0                 # tile size, px
const ROOM_W := 30              # tiles: about one screen
const ROOM_H := 16
const MARGIN := 3               # tiles of plain rock kept round the room

# Wake stages: per-joint swing (degrees) and wave speed (rad/s). Stage 0 is
# "alive but held down", stage 4 is every chain broken.
const WAKE_AMP := [2.0, 6.0, 10.0, 15.0, 20.0]
const WAKE_SPEED := [0.8, 1.1, 1.4, 1.7, 2.0]

var wake: int = 0
var room: Rect2i = Rect2i()     # tile rect, empty until built
var rigs: Array = []
var _map: Node = null
var _label: Label
var _wave_timer: float = 0.0
# Grip followers: instance id of the claw/hook -> {seg, local, last}
var _grips: Dictionary = {}


func _ready() -> void:
	if not OS.has_feature("editor") or not _Story.has_user_arg("tentacles"):
		queue_free()
		return
	process_physics_priority = -5   # after the rigs (-10), before keepers (0)
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
		_grips.clear()
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
			_map = Level.map
			_build()
		return
	_wave_timer -= delta
	if _wave_timer <= 0.0:
		_wave_timer = 5.0
		_stop_waves()
	_label.text = "Tentacle test (#359) · wake %d/4 · F6 calmer · F7 wilder · F8 back to the room" % wake


func _input(event: InputEvent) -> void:
	if room == Rect2i() or not (event is InputEventKey) or not event.pressed or event.echo:
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
		r.target_amp = deg_to_rad(WAKE_AMP[wake])
		r.target_speed = WAKE_SPEED[wake]
	print("[tentacles] wake %d: %.1f deg per joint, %.1f rad/s" % [wake, WAKE_AMP[wake], WAKE_SPEED[wake]])


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
	var plat = TentacleRig.new()
	plat.name = "TentaclePlatform"
	plat.base = _tile_edge(Vector2i(room.position.x, room.position.y + 9), Vector2(-0.5, 0.0)) + Vector2(-6, 0)
	plat.base_angle = 0.0
	plat.count = 10
	# Wall: up from the floor at the right, 12 tiles tall, swaying side to side.
	var wall = TentacleRig.new()
	wall.name = "TentacleWall"
	wall.base = _tile_edge(Vector2i(room.position.x + 21, room.end.y - 1), Vector2(0.0, 0.5)) + Vector2(0, 6)
	wall.base_angle = -PI / 2.0
	wall.count = 12
	wall.phase = 1.7
	for r in [plat, wall]:
		_map.add_child(r)
		rigs.append(r)
	set_wake(wake)
	for r in rigs:
		r.amp = r.target_amp
		r.speed = r.target_speed
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
	var ocean: Dictionary = _map.tileData.get_meta("story_ocean", {})
	var ocean_top: int = int(ocean.get("top", 1 << 20))
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


# ---------------------------------------------------------------- the grip fix

func _physics_process(_delta: float) -> void:
	if rigs.is_empty():
		return
	var segs: Dictionary = {}
	for r in rigs:
		if is_instance_valid(r):
			for s in r.segments:
				segs[s] = true
	var seen: Dictionary = {}
	for k in Keepers.getAll():
		if k == null or not is_instance_valid(k):
			continue
		# Beastmaster: each planted claw keeps a world point (Tentacle.attachmentPoint).
		var tents = k.get_node_or_null("Tentacles")
		if tents != null and "tentacles" in tents:
			# The body rides along: vanilla never pulls it toward its claws (it
			# just hangs), so it moves by the claws' average shift, each claw on
			# rock counting as a still one.
			var shift := Vector2.ZERO
			var planted: int = 0
			for t in tents.tentacles:
				if not is_instance_valid(t) or not t.is_grounded():
					continue
				planted += 1
				if not is_instance_valid(t.attachedTile) or not segs.has(t.attachedTile):
					continue
				var id: int = t.get_instance_id()
				seen[id] = true
				var before: Vector2 = t.attachmentPoint
				var p: Vector2 = _follow(id, t.attachedTile, before)
				shift += p - before
				t.attachmentPoint = p
				if t.arc_active:
					t.arc_end = p
			if planted > 0 and shift != Vector2.ZERO:
				k.move_and_collide(shift / float(planted))
		# Infiltrator: the hook freezes where it hit (Hook.connectHook).
		if "hook" in k and k.hook != null and is_instance_valid(k.hook) and k.hook.has_hit:
			var h = k.hook
			if is_instance_valid(h.attached_target) and segs.has(h.attached_target):
				var id: int = h.get_instance_id()
				seen[id] = true
				h.global_position = _follow(id, h.attached_target, h.global_position)
	for id in _grips.keys():
		if not seen.has(id):
			_grips.erase(id)


# Where a grip on `seg` that is now at `point` should be after the segment
# moved. A grip whose point changed since we last set it is a new grip.
func _follow(id: int, seg: Node2D, point: Vector2) -> Vector2:
	var g = _grips.get(id)
	if g == null or g.seg != seg or not point.is_equal_approx(g.last):
		g = {"seg": seg, "local": seg.global_transform.affine_inverse() * point, "last": point}
		_grips[id] = g
	var p: Vector2 = seg.global_transform * g.local
	g.last = p
	return p


# ---------------------------------------------------------------- the rig

# A tentacle as a chain of moving bodies on the tile layer (layer 1: keepers
# stand on it, the Beastmaster's attach ray, the kunai and the hook hit it). No
# "destructable" meta, so nobody mines it. A wave runs from the base to the tip.
class TentacleRig extends Node2D:
	var base: Vector2
	var base_angle: float = 0.0
	var count: int = 10
	var seg_len: float = 24.0
	var width0: float = 30.0
	var width1: float = 16.0
	var phase: float = 0.0
	var amp: float = 0.0
	var speed: float = 1.0
	var target_amp: float = 0.0
	var target_speed: float = 1.0
	var segments: Array = []
	var _t: float = 0.0

	func _ready() -> void:
		process_physics_priority = -10
		z_index = 2
		for i in count:
			var s := Segment.new()
			var f: float = float(i) / maxf(1.0, float(count - 1))
			var f1: float = float(i + 1) / maxf(1.0, float(count - 1))
			s.w_root = lerpf(width0, width1, f)
			s.w_tip = lerpf(width0, width1, minf(f1, 1.0))
			s.width = (s.w_root + s.w_tip) * 0.5
			s.length = seg_len
			s.last = i == count - 1
			s.index = i
			add_child(s)
			segments.append(s)
		_pose()

	func _physics_process(delta: float) -> void:
		# Ease between wake stages so a change never snaps.
		amp = move_toward(amp, target_amp, delta * 0.12)
		speed = move_toward(speed, target_speed, delta * 0.5)
		_t += delta * speed
		_pose()

	func _pose() -> void:
		var pos: Vector2 = base
		var ang: float = base_angle
		for i in segments.size():
			var f: float = float(i) / maxf(1.0, float(segments.size() - 1))
			# Small at the root, more toward the tip; a breath on top.
			var a: float = amp * (0.35 + 0.65 * f)
			ang += a * sin(_t * 2.0 + phase - float(i) * 0.55) + amp * 0.15 * sin(_t * 0.7 + phase)
			var dir := Vector2.from_angle(ang)
			var s = segments[i]
			s.global_transform = Transform2D(ang, pos + dir * seg_len * 0.5)
			pos += dir * seg_len


class Segment extends AnimatableBody2D:
	var width: float = 24.0     # mean width, for callers
	var w_root: float = 24.0    # at the joint toward the base
	var w_tip: float = 24.0     # at the joint toward the tip
	var length: float = 24.0    # joint to joint: neighbours meet exactly
	var index: int = 0
	var last: bool = false

	func _ready() -> void:
		sync_to_physics = true
		# Unshaded: seen in the dark room, not only in the keeper's light.
		var mat := CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		material = mat
		collision_layer = 1
		collision_mask = 0
		# A taper from joint to joint, so each piece's edge lines up with
		# the next (a rect per piece left a small ledge at every joint, which
		# stopped a keeper walking toward the thicker end), plus a round
		# knuckle on the root joint to smooth over the bend between pieces.
		var shape := CollisionShape2D.new()
		var poly := ConvexPolygonShape2D.new()
		poly.points = _outline()
		shape.shape = poly
		add_child(shape)
		var knuckle := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = w_root * 0.5
		knuckle.shape = c
		knuckle.position = Vector2(-length * 0.5, 0)
		add_child(knuckle)
		if last:
			var tip := CollisionShape2D.new()
			var ct := CircleShape2D.new()
			ct.radius = w_tip * 0.5
			tip.shape = ct
			tip.position = Vector2(length * 0.5, 0)
			add_child(tip)
		queue_redraw()

	func _outline() -> PackedVector2Array:
		var hl: float = length * 0.5
		return PackedVector2Array([Vector2(-hl, -w_root * 0.5), Vector2(hl, -w_tip * 0.5),
			Vector2(hl, w_tip * 0.5), Vector2(-hl, w_root * 0.5)])

	func _draw() -> void:
		var hl: float = length * 0.5
		var hw: float = width * 0.5
		var body := Color(0.33, 0.17, 0.52)
		var dark := Color(0.16, 0.08, 0.27)
		var light := Color(0.50, 0.30, 0.72)
		draw_colored_polygon(_outline(), dark)
		draw_circle(Vector2(-hl, 0), w_root * 0.5, dark)
		if last:
			draw_circle(Vector2(hl, 0), w_tip * 0.5, dark)
		var a: float = w_root * 0.5 - 2.0
		var b: float = w_tip * 0.5 - 2.0
		draw_colored_polygon(PackedVector2Array([Vector2(-hl, -a), Vector2(hl, -b), Vector2(hl, b), Vector2(-hl, a)]), body)
		draw_circle(Vector2(-hl, 0), a, body)
		draw_colored_polygon(PackedVector2Array([Vector2(-hl, -a), Vector2(hl, -b), Vector2(hl, -b + 3), Vector2(-hl, -a + 3)]), light)
		# Suckers along the underside.
		draw_circle(Vector2(0, hw - 5), 3.0, Color(0.72, 0.55, 0.85))
		draw_circle(Vector2(0, hw - 5), 1.5, dark)
		if index % 2 == 0:
			draw_line(Vector2(-4, -2), Vector2(2, 3), Color(1.0, 0.55, 0.2), 1.5)
