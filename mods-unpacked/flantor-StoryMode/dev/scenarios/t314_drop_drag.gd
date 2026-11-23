extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 314: Story Mode drops drag and slide over rock the way vanilla iron
# does. Each floor kind (plain rock, a vanilla iron ore floor, Story Mode metal,
# a Story Mode mineral) gets a lane: two one-tile channels, one over the other,
# whose floors are that tile. Vanilla's own IronDrop scene is the reference.
#
#  - pressed: the drop lies in the upper channel and the Engineer flies right
#    along the lower one for HOLD seconds, so the line pulls the drop down into
#    its floor as it drags it (a keeper below a ledge, or going down stairs).
#    The drop's mean lag behind the keeper (gap) is what friction shows in.
#  - fling: the Engineer drags the drop along the lower channel at full speed
#    and lets go; how far it slides on before it stops.
#  - nudge (host only, no keeper): a drop at rest in the upper channel is
#    given 150 px/s along its floor; how far it slides. Friction alone.
#
# Also checks each floor tile is one body with one 24 x 24 box and nothing
# else at its centre (no doubled or extra collision). Shared by
# t314_split_drag (both splitscreen keepers) and t314_mp_drag_host / _client
# (online, host and client keeper).

const TIMEOUT := 420
const VANILLA_IRON := "res://content/drop/iron/IronDrop.tscn"
const LANE_W := 16     # tiles per channel (the Engineer flies 56 px/s, 2.3 tiles/s)
const HOLD := 4.0      # seconds of a pressed drag
const FLING_HOLD := 2.0
const FROM := 1.0      # drag numbers are taken from here on (the line is taut by then)
const NUDGE := 150.0   # px/s
# Story drops must come within this of vanilla iron. A fling's slide repeats
# to the pixel; the mean gap varies by up to ~15% (vanilla's line pull has a
# random kick); a nudged drop tumbles for 12-14 tiles and stops at one of a few
# spots (vanilla iron: 287, 312 or 344 px, rock and metal alike). Before #314
# Story drops lagged 85% further, flung 60% shorter and nudged 162 px.
const TOLERANCE := 0.10
const GAP_TOLERANCE := 0.25
const NUDGE_TOLERANCE := 0.25

# Floor tile ids (Data.TILE_DIRT_START, Data.TILE_IRON, Metal.TILE_ID, bronze).
const FLOORS := {"rock": 10, "ironore": 0, "metal": 48, "bronze": 40}
# Tile ids a lane may be carved through (overwritten): rock, iron, water, sand,
# supplements, Story minerals, metal and bones; never borders, gates or caves.
const OK_IDS := [10, 11, 0, 1, 2, 7, 40, 41, 42, 43, 44, 45, 46, 47, 48, 50]


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	var k = h.keeper()
	h.check("the keeper is the Engineer", k.techId == "keeper1", k.techId)
	var by_floor: Dictionary = await make_lanes(h, FLOORS.keys())
	if by_floor.is_empty():
		return
	var mover := keyboard_mover(h)
	var res := {}
	# Every drop Story Mode makes, on plain rock (vanilla and gold twice, to
	# show the spread between runs).
	for kind in ["vanilla_iron", "iron", "gold", "ruby", "diamond", "minerbones", "vanilla_iron", "gold"]:
		await both(h, k, by_floor["rock"], kind, "rock", mover, res)
	# Vanilla iron and a Story piece over each of the other floors.
	for f in ["ironore", "metal", "bronze"]:
		for kind in ["vanilla_iron", "gold"]:
			await both(h, k, by_floor[f], kind, f, mover, res)
	judge(h, res, "")


# A pressed drag, a fling and (host) a nudge of `kind` on floor `f`, into res.
static func both(h, k, lane: Dictionary, kind: String, f: String, mover: Dictionary, res: Dictionary, who: String = "") -> void:
	var key: String = kind + "@" + f
	if res.has(key):
		key += "#2"
	var r: Dictionary = await pressed(h, k, lane, kind, mover, who + key)
	r.merge(await fling(h, k, lane, kind, mover, who + key))
	if h.multiplayer.is_server():
		r.merge(await nudge(h, lane, kind, who + key))
	res[key] = r


# --- lanes ---------------------------------------------------------------------

static var lane_misses := {}   # why candidate lanes were turned down, for the log


# Host: finds, checks and digs a lane per floor name (keys of FLOORS).
static func make_lanes(h, floors: Array) -> Dictionary:
	var lanes: Array = find_lanes(floors.size())
	if not h.check("found a lane for every floor", lanes.size() == floors.size(), {"lanes": lanes, "misses": lane_misses}):
		return {}
	var by_floor := {}
	for i in floors.size():
		by_floor[floors[i]] = lanes[i]
		set_lane_tiles(lanes[i], FLOORS[floors[i]])
	for f in floors:
		await dig_lane(h, by_floor[f])
	# Tiles next to dug ones are revealed in slices (#159): let them all land.
	if Level.map.has_method("finish_flood"):
		Level.map.finish_flood()
	await h.wait(0.5)
	check_lanes(h, by_floor)
	return by_floor


# `n` lanes: rows y - 3 .. y + 1, x0 - 1 .. x1 + 1 of unrevealed, drillable
# tiles (all overwritten) with no lava or gas, apart from each other. The
# channels are rows y - 2 and y; rows y - 1 and y + 1 are their floors.
static func find_lanes(n: int) -> Array:
	var td = Level.map.tileData
	var lava = Level.map.get_node_or_null("StoryLavaField")
	var gas = Level.map.get_node_or_null("StoryGasField")
	var lanes: Array = []
	for y in range(12, 80):
		for x0 in range(-13, -50, -1) + range(-12, 30, 1):
			var x1: int = x0 + LANE_W - 1
			var ok := true
			for l in lanes:
				if absi(int(l["y"]) - y) < 5 and absi(int(l["x0"]) - x0) < LANE_W + 3:
					ok = false
			for yy in range(y - 3, y + 2):
				if not ok:
					break
				for x in range(x0 - 1, x1 + 2):
					var c := Vector2i(x, yy)
					var why := ""
					if lava != null and (lava.magma.has(c) or lava.mass.has(c)):
						why = "lava"
					elif gas != null and (gas.rock.has(c) or gas.mass.has(c)):
						why = "gas"
					elif not OK_IDS.has(td.get_resourcev(c)):
						why = "id %d" % td.get_resourcev(c)
					elif td.get_hardnessv(c) < 0 or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE:
						why = "hardness"
					elif Level.map.tiles.has(Vector2(c)):
						why = "revealed"
					if why != "":
						ok = false
						lane_misses[why] = lane_misses.get(why, 0) + 1
						break
			if ok:
				lanes.append({"y": y, "x0": x0, "x1": x1})
				break
		if lanes.size() == n:
			break
	return lanes


# Rock all round, both floors `floor_id`. On the host, and on a client before
# the host digs (so its tiles look the same; physics runs on the host).
static func set_lane_tiles(lane: Dictionary, floor_id: int) -> void:
	var td = Level.map.tileData
	var y: int = int(lane["y"])
	for x in range(int(lane["x0"]) - 1, int(lane["x1"]) + 2):
		for yy in range(y - 3, y + 2):
			td.set_resourcev(Vector2i(x, yy), floor_id if (yy == y - 1 or yy == y + 1) else Data.TILE_DIRT_START)
	lane["floor_id"] = floor_id


static func dig_lane(h, lane: Dictionary) -> void:
	var y: int = int(lane["y"])
	await h.dig_room(Vector2i(int(lane["x0"]), y - 2), Vector2i(int(lane["x1"]), y - 2))
	await h.dig_room(Vector2i(int(lane["x0"]), y), Vector2i(int(lane["x1"]), y))


# Each lane open, both floors of one tile type, and each floor tile a single
# body with a single 24 x 24 box, the only thing a drop can hit at its centre,
# on the same collision layers as a plain rock tile.
static func check_lanes(h, by_floor: Dictionary) -> void:
	var info := {}
	var open := true
	var odd: Array = []
	var space: PhysicsDirectSpaceState2D = Level.map.get_world_2d().direct_space_state
	var drop_mask: int = 10   # MineralDrop.tscn collision_mask
	var rock_layer := -1
	for f: String in by_floor:
		var lane: Dictionary = by_floor[f]
		var y: int = int(lane["y"])
		var types := {}
		for x in range(int(lane["x0"]), int(lane["x1"]) + 1):
			for row in [y - 2, y]:
				if not Level.map.is_tile_empty(Vector2i(x, row)):
					open = false
			for row in [y - 1, y + 1]:
				var t = Level.map.tiles.get(Vector2(x, row))
				var ty: String = t.type if t != null else "<none> row %d (td %d)" % [row, Level.map.tileData.get_resourcev(Vector2i(x, row))]
				types[ty] = types.get(ty, 0) + 1
				if t == null:
					continue
				if f == "rock" and rock_layer < 0:
					rock_layer = t.collision_layer
				var shapes: Array = t.get_children().filter(func(c): return c is CollisionShape2D or c is CollisionPolygon2D)
				var q := PhysicsPointQueryParameters2D.new()
				q.position = t.get_node("CollisionShape2D").global_position
				q.collision_mask = drop_mask
				var hits: Array = space.intersect_point(q, 8)
				var box: bool = shapes.size() == 1 and shapes[0] is CollisionShape2D and shapes[0].shape is RectangleShape2D \
						and shapes[0].shape.size == Vector2(24, 24) and not shapes[0].disabled
				if not box or hits.size() != 1 or hits[0]["collider"] != t:
					odd.append({"tile": [x, row, ty], "shapes": shapes.size(), "hits": hits.map(func(r): return str(r["collider"]))})
				info[f + " layer"] = t.collision_layer
		info[f] = types
		if types.size() != 1:
			open = false
	h.check("every lane is open, each floor all one tile type", open, info)
	h.check("every floor tile is one 24x24 box, alone at its centre", odd.is_empty(), odd.slice(0, 10))
	var layers_same := true
	for f in by_floor:
		if info.get(f + " layer", rock_layer) != rock_layer:
			layers_same = false
	h.check("mod floor tiles sit on the same collision layers as rock", layers_same, info)


# --- one drag --------------------------------------------------------------------

static func keyboard_mover(h) -> Dictionary:
	return {"start": func(): h.down("ui_right"), "stop": func(): h.up("ui_right")}


# A gamepad keeper (splitscreen) flies with the left stick.
static func pad_mover(device: int) -> Dictionary:
	var stick := func(x: float):
		var e := InputEventJoypadMotion.new()
		e.device = device - 1
		e.axis = JOY_AXIS_LEFT_X
		e.axis_value = x
		Input.parse_input_event(e)
	return {"start": stick.bind(1.0), "stop": stick.bind(0.0)}


# Host: a drop of `kind` ("vanilla_iron" = vanilla's own IronDrop scene) at `pos`.
static func spawn(kind: String, pos: Vector2):
	var type: String = kind
	var was: PackedScene = null
	if kind == "vanilla_iron":
		type = "iron"
		was = Data.DROP_SCENES["iron"]
		Data.DROP_SCENES["iron"] = load(VANILLA_IRON)
	var d = Level.drops.network_spawn({"type": type, "position": pos, "impulse": Vector2.ZERO})
	if was != null:
		Data.DROP_SCENES["iron"] = was
	return d


# Where the drop starts and the keeper starts, by mode ("pressed": drop in
# the upper channel; "fling": both in the lower one).
static func drop_tile(lane: Dictionary, mode: String) -> Vector2i:
	return Vector2i(int(lane["x0"]) + 1, int(lane["y"]) - (2 if mode == "pressed" else 0))


static func keeper_tile(lane: Dictionary) -> Vector2i:
	return Vector2i(int(lane["x0"]) + 2, int(lane["y"]))


static func material_info(d) -> Dictionary:
	var mat = d.physics_material_override
	return {"friction": snappedf(mat.friction, 0.01) if mat else null, "bounce": snappedf(d.bounciness, 0.01)}


# Puts keeper k at the lane start and the drop (spawned here on the host, or
# `d` from the host) at its start, picks it up. Returns the drop, or null.
static func set_up(h, k, lane: Dictionary, kind: String, mode: String, d = null):
	await h.teleport_tile(keeper_tile(lane), k)
	if d == null:
		d = spawn(kind, Level.map.getTilePos(Vector2(drop_tile(lane, mode))))
		await h.frames(3)
	await h.wait(1.2)
	k.pickup(d)
	if not await h.until(func(): return is_instance_valid(d) and d.isCarriedBy(k), 3.0):
		h.check("picked the %s up for %s" % [kind, mode], false)
		return null
	return d


static func finish(h, k, d) -> void:
	if is_instance_valid(d) and d.isCarriedBy(k):
		k.dropCarry(d)
	await h.frames(5)
	if h.multiplayer.is_server() and is_instance_valid(d):
		Level.drops.network_free_drop(d.UID)
	await h.frames(5)


static func pressed(h, k, lane: Dictionary, kind: String, mover: Dictionary, label: String, d = null) -> Dictionary:
	d = await set_up(h, k, lane, kind, "pressed", d)
	if d == null:
		return {}
	var info: Dictionary = material_info(d)
	var out: Dictionary = await sample(h, k, d, HOLD, mover, "pressed_" + label)
	out.merge(info)
	h.note("pressed " + label, out)
	await finish(h, k, d)
	return out


static func fling(h, k, lane: Dictionary, kind: String, mover: Dictionary, label: String, d = null) -> Dictionary:
	d = await set_up(h, k, lane, kind, "fling", d)
	if d == null:
		return {}
	var info: Dictionary = material_info(d)
	mover["start"].call()
	await h.wait(FLING_HOLD)
	k.dropCarry(d)
	mover["stop"].call()
	var out: Dictionary = await slide_of(h, d)
	out.merge(info)
	h.note("fling " + label, out)
	await finish(h, k, d)
	return out


# Host: a drop at rest in the upper channel, pushed along its floor.
static func nudge(h, lane: Dictionary, kind: String, label: String) -> Dictionary:
	var d = spawn(kind, Level.map.getTilePos(Vector2(drop_tile(lane, "pressed"))))
	await h.frames(3)
	await h.wait(1.2)
	d.linear_velocity = Vector2(NUDGE, 0)
	var s: Dictionary = await slide_of(h, d)
	var out := {"nudge": s.get("slide"), "nudge_s": s.get("slide_s")}
	h.note("nudge " + label, out)
	if is_instance_valid(d):
		Level.drops.network_free_drop(d.UID)
	await h.frames(5)
	return out


# Watches a let-go drop until it has stopped (from its positions, so it reads
# the same on a client): how far and how long it slid.
static func slide_of(h, d) -> Dictionary:
	await h.until(func(): return not is_instance_valid(d) or not d.isCarried(), 6.0)
	if not is_instance_valid(d):
		return {}
	var x0: float = d.global_position.x
	var last: float = x0
	var t0: int = Time.get_ticks_usec()
	var t_moved := 0.0
	var v0 := 0.0
	var n := 0
	while true:
		await h.get_tree().physics_frame
		if not is_instance_valid(d):
			break
		var t: float = (Time.get_ticks_usec() - t0) / 1e6
		var x: float = d.global_position.x
		n += 1
		if n == 3:
			v0 = (x - x0) / maxf(t, 1e-3)
		if absf(x - last) > 0.05:
			t_moved = t
		last = x
		if t - t_moved > 0.5 or t > 6.0:
			break
	return {"slide": snappedf(last - x0, 0.1), "slide_s": snappedf(t_moved, 0.01), "v_release": snappedf(v0, 0.1)}


# Logs keeper and drop every physics frame for `secs` (moving the keeper with
# `mover` if given) and sums it up over the frames from FROM on.
static func sample(h, k, d, secs: float, mover: Dictionary, shot_label: String) -> Dictionary:
	var rows: Array = []
	if not mover.is_empty():
		mover["start"].call()
	var t0: int = Time.get_ticks_usec()
	var shot_taken := false
	while true:
		await h.get_tree().physics_frame
		if not is_instance_valid(d) or not is_instance_valid(k):
			break
		var t: float = (Time.get_ticks_usec() - t0) / 1e6
		rows.append([t, k.global_position.x, d.global_position.x, d.global_position.y, d.isCarried()])
		if shot_label != "" and not shot_taken and t > 2.5:
			shot_taken = true
			h.shot(shot_label.replace("@", "_on_").replace("#", "_"))
		if t >= secs:
			break
	if not mover.is_empty():
		mover["stop"].call()
	return summarize(rows)


static func summarize(rows: Array) -> Dictionary:
	var w: Array = rows.filter(func(r): return r[0] >= FROM)
	if w.size() < 3:
		return {"frames": rows.size()}
	var a: Array = w.front()
	var b: Array = w.back()
	var dt: float = b[0] - a[0]
	var gap_sum := 0.0
	var gap_max := 0.0
	for r: Array in w:
		gap_sum += r[1] - r[2]
		gap_max = maxf(gap_max, r[1] - r[2])
	return {
		"frames": rows.size(),
		"drop_speed": snappedf((b[2] - a[2]) / dt, 0.1),
		"keeper_speed": snappedf((b[1] - a[1]) / dt, 0.1),
		"drop_dx": snappedf(rows.back()[2] - rows.front()[2], 0.1),
		"keeper_dx": snappedf(rows.back()[1] - rows.front()[1], 0.1),
		"gap": snappedf(gap_sum / w.size(), 0.1),
		"gap_max": snappedf(gap_max, 0.1),
		"carried_to_end": bool(b[4]),
	}


# --- verdict ---------------------------------------------------------------------

static func _rel(a, b) -> float:
	return absf(float(a) - float(b)) / maxf(1.0, absf(float(b)))


# What a Story drop must match vanilla iron in: the pressed drag's gap and
# distance, and, where measured, the fling's and the nudge's slide.
static func _close(r: Dictionary, ref: Dictionary, fling_too: bool) -> bool:
	if not (r.has("gap") and ref.has("gap")):
		return false
	var ok: bool = _rel(r["gap"], ref["gap"]) < GAP_TOLERANCE and _rel(r["drop_dx"], ref["drop_dx"]) < TOLERANCE
	if fling_too:
		ok = ok and r.has("slide") and ref.has("slide") and _rel(r["slide"], ref["slide"]) < TOLERANCE
	if r.has("nudge") and ref.has("nudge"):
		ok = ok and _rel(r["nudge"], ref["nudge"]) < NUDGE_TOLERANCE
	return ok


static func _nums(r: Dictionary) -> Array:
	return [r.get("gap"), r.get("drop_dx"), r.get("slide"), r.get("nudge")]


# Every Story drop drags and slides like vanilla iron on the same floor, and
# vanilla iron the same on every floor. `material` false on a client, whose
# drops are its own (story iron for vanilla iron too) and only follow the host.
# `fling_too` false for a client's keeper: online, where its let-go drop ends
# up depends on when the release reaches the host (vanilla iron slid 9 px one
# time and 54 the next), so it says nothing about friction; the nudge does.
static func judge(h, res: Dictionary, who: String, material: bool = true, fling_too: bool = true) -> void:
	var rows: Array = []
	for key: String in res:
		var r: Dictionary = res[key]
		rows.append("%-22s pressed: gap %5s (max %5s) drop dx %6s / keeper %6s | fling: slide %5s px in %4s s from %5s px/s | nudge: %5s px in %4s s | friction %s bounce %s" % [key, r.get("gap"), r.get("gap_max"), r.get("drop_dx"), r.get("keeper_dx"), r.get("slide"), r.get("slide_s"), r.get("v_release"), r.get("nudge"), r.get("nudge_s"), r.get("friction"), r.get("bounce")])
	h.note(who + "drag table", rows)
	for line in rows:
		print("T314 ", who, line)
	var ref_key := "vanilla_iron@rock"
	if not res.has(ref_key) or not res[ref_key].has("gap"):
		h.check(who + "vanilla reference measured", false, res.keys())
		return
	var ref: Dictionary = res[ref_key]
	for key: String in res:
		var r: Dictionary = res[key]
		if not r.has("gap") or (fling_too and not r.has("slide")):
			h.check(who + key + ": measured", false, r)
			continue
		h.check(who + key + ": still on the line after the pressed drag", r["carried_to_end"], r)
		if key.begins_with("vanilla_iron"):
			continue
		if material:
			h.check(who + key + ": vanilla iron's friction and bounce", r["friction"] == ref["friction"] and r["bounce"] == ref["bounce"], [r["friction"], r["bounce"], ref["friction"], ref["bounce"]])
		var fref: Dictionary = res.get("vanilla_iron@" + key.split("@")[1].split("#")[0], ref)
		h.check(who + key + ": drags and slides like vanilla iron on that floor", _close(r, fref, fling_too),
			{"story [gap, dx, fling, nudge]": _nums(r), "vanilla": _nums(fref)})
	for key: String in res:
		if key.begins_with("vanilla_iron@") and key != ref_key and not key.contains("#"):
			h.check(who + "vanilla iron drags and slides the same on %s as on rock" % key.split("@")[1], _close(res[key], ref, fling_too),
				{"floor [gap, dx, fling, nudge]": _nums(res[key]), "rock": _nums(ref)})
