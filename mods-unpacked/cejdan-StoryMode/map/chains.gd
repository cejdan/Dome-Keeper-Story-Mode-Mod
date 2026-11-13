extends Node2D

# Chains of the seal (#101, stretch): every unobtainium deposit in the lava
# ocean is bound to the boss chamber by a chain, so mining unobtainium is
# physically freeing the horror.
#
# The chains form a tree, like roots: each deposit's chain runs to a knot (an
# iron ring) shared by nearby deposits, and one trunk chain runs from each knot
# down to the chamber's roof. Fifty separate chains to one roof read as a
# tangle; a dozen trunks fanning out of the roof and branching to the crystals
# read as one thing holding the seal.
#
# Background only: drawn over the lava (so it reads) but under the keeper, never
# collides. Every chain bows and sways slowly as if floating in the lava.
# Mining any tile of a deposit breaks its chain: a white snap at the deposit,
# the loose chain drifts down and fades, leaving a short stub on the knot. When
# a knot's last deposit goes, its trunk snaps too. Broken chains stay broken
# across a save and reload (they read beats/awakening.gd's record of mined
# cells).
#
# A chain stays hidden until the player has seen part of it (its deposit or a
# cell along it), so the chains don't give the ocean away through the dark;
# breaching the ocean reveals them all at once.
#
# Cost: each chain is one Line2D with a tiled link texture (one draw call, culled
# by the renderer). Only chains crossing the camera get new points, at 30 Hz.

const Awakening = preload("res://mods-unpacked/cejdan-StoryMode/beats/awakening.gd")

const UNOB_ID := 47
const STEP := 16.0              # px between a chain's points
const SWAY := 8.0               # px at the middle of a chain
const SWAY_PERIOD := 6.5        # seconds per sway
const BOW := 0.06               # a resting bow, as a share of the chain's length
const PER_KNOT := 4.5           # deposits per knot, on average
const SNAP_TIME := 2.2
const FADE_IN := 1.2
const STUB := 2                 # links left hanging after a break
const REDRAW := 1.0 / 30.0
const SEEN_EVERY := 0.5         # s between checks for chains coming into sight

# Colours: dark iron that reads on the lava's orange and on the unobtainium's
# and the barrier's violet, a cool highlight that reads in the dark.
const OUTLINE := Color("120e17")
const IRON := Color("2b2336")
const LIT := Color("8d84b8")
const SEAL := Color("8a7cff")
const FLASH := Color(1, 1, 1)

static var _tex: ImageTexture

# Deposit chains. Each: {cells, a (deposit), b (its knot), knot (index),
#   bow (signed px), phase, broken, snap_t (-1 never, else seconds since),
#   seen, fade, line, box, probe}
var chains: Array = []
# Trunk chains, one per knot, the same shape: a (knot), b (roof), members
# (indices into chains), cells empty.
var trunks: Array = []
var _all: Array = []
var _t: float = 0.0
var _acc: float = 0.0
var _seen_acc: float = 0.0
var _cells_rec: String = ""
var _freed: Dictionary = {}
var _map
var _dirty: bool = true
var draw_count: int = 0         # chains given new points on the last update


func setup(map) -> void:
	name = "StoryChains"
	z_index = 7        # over the lava field (6), under the keeper
	_map = map
	var td = map.tileData
	var room: Rect2i = td.get_meta("story_boss_chamber", Rect2i())
	var ocean: Dictionary = td.get_meta("story_ocean", {})
	if room.size == Vector2i.ZERO or ocean.is_empty():
		return
	_read_freed()
	# Trunks are bolted to the ocean floor right over the chamber (the soft row
	# above its roof), so they never cross rock.
	var roof_y: float = map.getTilePos(Vector2i(0, room.position.y - 1)).y - 12.0
	var roof_l: float = map.getTilePos(Vector2i(room.position.x, 0)).x + 18.0
	var roof_r: float = map.getTilePos(Vector2i(room.end.x - 1, 0)).x - 18.0
	var ox0: float = map.getTilePos(Vector2i(int(ocean["x0"]), 0)).x
	var ox1: float = map.getTilePos(Vector2i(int(ocean["x1"]), 0)).x
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	# Seeded from the map itself: a loaded run gets a new levelSeed.
	rng.seed = hash([room, ocean.get("x0"), ocean.get("x1"), 101])
	var deps: Array = _deposits(td)
	var centres: Array = []
	for dep: Array in deps:
		var centre: Vector2 = Vector2.ZERO
		for c: Vector2i in dep:
			centre += map.getTilePos(c)
		centres.append(centre / dep.size())
	if deps.is_empty():
		return
	var groups: Array = _cluster(centres, clampi(roundi(deps.size() / PER_KNOT), 1, 16))
	for g: Array in groups:
		var knot: Vector2 = Vector2.ZERO
		for i: int in g:
			knot += centres[i]
		knot /= g.size()
		# Anchor on the chamber's roof, spread along it by where the knot lies
		# across the ocean, so the trunks fan out of the roof.
		var u: float = clampf(inverse_lerp(ox0, ox1, knot.x), 0.0, 1.0)
		var anchor: Vector2 = Vector2(lerpf(roof_l, roof_r, u), roof_y)
		# The knot sits a little toward the roof from its deposits' middle, so no
		# deposit chain is too short to read.
		knot = knot.move_toward(anchor, 56.0)
		var members: Array = []
		for i: int in g:
			members.append(chains.size())
			chains.append(_chain(map, rng, deps[i], centres[i], knot, deps[i]))
			chains[-1]["knot"] = trunks.size()
		var trunk: Dictionary = _chain(map, rng, [], knot, anchor, [])
		trunk["members"] = members
		trunks.append(trunk)
	_all = chains + trunks
	for t: Dictionary in trunks:
		t["broken"] = t["members"].all(func(i): return chains[i]["broken"])
	for ch: Dictionary in _all:
		if ch["broken"]:
			_stub(ch)
	_check_seen(true)


func _chain(map, rng: RandomNumberGenerator, cells: Array, a: Vector2, b: Vector2, probe: Array) -> Dictionary:
	var length: float = maxf(1.0, a.distance_to(b))
	var dir: Vector2 = (b - a) / length
	# Chains lying across the ocean arch upward, as if buoyed by the lava;
	# steep ones bow either way.
	var up: float = -1.0 if dir.x > 0.0 else 1.0
	var sgn: float = up if absf(dir.x) > 0.5 else (1.0 if rng.randf() < 0.5 else -1.0)
	var bow: float = length * BOW * sgn * rng.randf_range(0.6, 1.0)
	var line := Line2D.new()
	line.texture = _link_texture()
	line.texture_mode = Line2D.LINE_TEXTURE_TILE
	line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	line.width = _tex.get_height()
	line.joint_mode = Line2D.LINE_JOINT_SHARP
	line.antialiased = false
	line.show_behind_parent = true    # knots and snaps draw over the chain ends
	line.visible = false
	add_child(line)
	# Sight of a deposit, or of any third tile along the chain, reveals it.
	var p: Array = probe.duplicate()
	var n: int = maxi(1, int(length / 72.0))
	for i in range(0, n + 1):
		p.append(map.getTileCoord(a.lerp(b, float(i) / n)))
	return {"cells": cells, "a": a, "b": b, "bow": bow, "phase": rng.randf() * TAU,
		"broken": cells.any(func(c): return _freed.has(c)), "snap_t": -1.0, "seen": false, "fade": 0.0,
		"line": line, "box": Rect2(a, Vector2.ZERO).expand(b).grow(absf(bow) + SWAY + 16.0), "probe": p}


# k-means on the deposits' centres, seeded from their order across the ocean.
# Returns k groups of indices (empty groups dropped).
func _cluster(points: Array, k: int) -> Array:
	var order: Array = range(points.size())
	order.sort_custom(func(i, j): return points[i].x < points[j].x)
	var means: Array = []
	for j in k:
		means.append(points[order[int((j + 0.5) * points.size() / k)]])
	var assign: Array = []
	assign.resize(points.size())
	for _it in 10:
		for i in points.size():
			var best: int = 0
			for j in k:
				if points[i].distance_squared_to(means[j]) < points[i].distance_squared_to(means[best]):
					best = j
			assign[i] = best
		for j in k:
			var sum: Vector2 = Vector2.ZERO
			var cnt: int = 0
			for i in points.size():
				if assign[i] == j:
					sum += points[i]
					cnt += 1
			if cnt > 0:
				means[j] = sum / cnt
	var out: Array = []
	for j in k:
		var g: Array = []
		for i in points.size():
			if assign[i] == j:
				g.append(i)
		if not g.is_empty():
			out.append(g)
	return out


func _deposits(td) -> Array:
	var left: Dictionary = {}
	for c: Vector2i in td.get_resource_cells_by_id(UNOB_ID):
		left[c] = true
	# Mined deposits are gone from the tile data; rebuild them from the record.
	for c: Vector2i in _freed:
		left[c] = true
	var cells: Array = left.keys()
	cells.sort()
	var out: Array = []
	for s: Vector2i in cells:
		if not left.has(s):
			continue
		left.erase(s)
		var open: Array = [s]
		var grp: Array = []
		while open.size() > 0:
			var c: Vector2i = open.pop_back()
			grp.append(c)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
				if left.has(c + d):
					left.erase(c + d)
					open.append(c + d)
		grp.sort()
		out.append(grp)
	return out


func intact() -> int:
	return chains.filter(func(c): return not c["broken"]).size()


func shown() -> int:
	return _all.filter(func(c): return c["seen"]).size()


func _read_freed() -> bool:
	var rec: String = str(Data.ofOr(Awakening.CELLS, ""))
	if rec == _cells_rec:
		return false
	_cells_rec = rec
	_freed.clear()
	for s: String in rec.split(";", false):
		var p: PackedStringArray = s.split(",")
		_freed[Vector2i(int(p[0]), int(p[1]))] = true
	return true


func _check_seen(instant: bool = false) -> void:
	var vis: Dictionary = _map.visibleTileCoords
	for ch in _all:
		if ch["seen"]:
			continue
		for c: Vector2i in ch["probe"]:
			if vis.has(Vector2(c)):
				_show(ch, instant)
				break


func _show(ch: Dictionary, instant: bool) -> void:
	ch["seen"] = true
	ch["fade"] = 1.0 if instant else 0.0
	ch["line"].visible = true
	ch["line"].modulate.a = ch["fade"]
	_dirty = true


func _snap(ch: Dictionary) -> void:
	ch["broken"] = true
	ch["snap_t"] = 0.0
	if not ch["seen"]:
		_show(ch, true)
	_dirty = true


func _process(delta: float) -> void:
	if _all.is_empty():
		return
	_t += 0.0 if GameWorld.paused else delta
	if _read_freed():
		for ch in chains:
			if not ch["broken"] and ch["cells"].any(func(c): return _freed.has(c)):
				_snap(ch)
		for t in trunks:
			if not t["broken"] and t["members"].all(func(i): return chains[i]["broken"]):
				_snap(t)
	_seen_acc += delta
	if _seen_acc >= SEEN_EVERY:
		_seen_acc = 0.0
		_check_seen()
	for ch in _all:
		if ch["snap_t"] >= 0.0 and ch["snap_t"] < SNAP_TIME:
			ch["snap_t"] += delta
			_dirty = true
			if ch["snap_t"] >= SNAP_TIME:
				_stub(ch)
		if ch["seen"] and ch["fade"] < 1.0:
			ch["fade"] = minf(1.0, ch["fade"] + delta / FADE_IN)
			ch["line"].modulate.a = ch["fade"]
			_dirty = true
	if _dirty:
		_dirty = false
		queue_redraw()
	_acc += delta
	if _acc < REDRAW:
		return
	_acc = 0.0
	draw_count = 0
	var view: Rect2 = _view()
	if view.size == Vector2.ZERO:
		return
	for ch in _all:
		if not ch["seen"] or not view.intersects(ch["box"]):
			continue
		if not ch["broken"]:
			ch["line"].points = _points(ch["a"], ch["b"], ch["bow"], ch["phase"], 0.0)
			draw_count += 1
		elif ch["snap_t"] >= 0.0 and ch["snap_t"] < SNAP_TIME:
			var t: float = ch["snap_t"] / SNAP_TIME
			# The loose end drifts down and away, and fades.
			var a: Vector2 = ch["a"] + Vector2(signf(ch["bow"]) * 30.0 * t, 70.0 * t * t)
			ch["line"].points = _points(a, ch["b"], ch["bow"], ch["phase"], t)
			ch["line"].modulate.a = 1.0 - t * t
			draw_count += 1
			# A snapping trunk takes its knot's hanging stubs with it.
			if ch.has("members"):
				for i in ch["members"]:
					var m: Dictionary = chains[i]
					if m["snap_t"] < 0.0 or m["snap_t"] >= SNAP_TIME:
						m["line"].modulate.a = 1.0 - t * t


func _view() -> Rect2:
	var k = Keepers.first()
	if k == null or Level.viewports == null:
		return Rect2()
	var cam = Level.viewports.getPlayerCam(k.playerId)
	if cam == null:
		return Rect2()
	var vs: Vector2 = cam.get_viewport_rect().size / cam.zoom
	return Rect2(cam.get_screen_center_position() - vs / 2.0, vs).grow(48)


# The chain's points (this node's space) from `a` to `b`: a resting bow plus a
# slow wave travelling along it, both zero at the ends. `slack` (0..1) loosens a
# snapping chain.
func _points(a: Vector2, b: Vector2, bow: float, phase: float, slack: float) -> PackedVector2Array:
	var length: float = maxf(1.0, a.distance_to(b))
	var n: int = maxi(2, int(length / STEP))
	var dir: Vector2 = (b - a) / length
	var normal: Vector2 = Vector2(-dir.y, dir.x)
	var w: float = TAU / SWAY_PERIOD
	var out := PackedVector2Array()
	out.resize(n + 1)
	for i in n + 1:
		var s: float = float(i) / n
		var arc: float = sin(PI * s)
		var off: float = bow * (1.0 + slack * 2.0) * arc
		off += sin(_t * w + phase - s * 2.4) * SWAY * arc
		out[i] = to_local(a.lerp(b, s) + normal * off)
	return out


# A broken chain: a couple of links hanging from where it was fixed (its knot,
# or the roof for a trunk) toward where it led.
func _stub(ch: Dictionary) -> void:
	var b: Vector2 = ch["b"]
	var dir: Vector2 = (ch["a"] - b).normalized()
	var tip: Vector2 = b + (dir + Vector2(0, 1.2)).normalized() * _link_texture().get_width() * STUB
	ch["line"].points = PackedVector2Array([to_local(b), to_local(tip)])
	ch["line"].modulate.a = 1.0
	# A deposit chain's stub hangs from its knot, and goes when the knot does.
	ch["line"].visible = ch["seen"] and not (ch.has("knot") and trunks[ch["knot"]]["broken"])
	if ch.has("members"):
		for i in ch["members"]:
			if chains[i]["snap_t"] < 0.0 or chains[i]["snap_t"] >= SNAP_TIME:
				_stub(chains[i])
	_dirty = true


# Knots (iron rings where deposit chains meet their trunk), roof plates where
# trunks are fixed, and the white snap where a chain breaks.
func _draw() -> void:
	for t in trunks:
		if not t["seen"]:
			continue
		var al: float = t["fade"]
		var r: Vector2 = to_local(t["b"])
		draw_rect(Rect2(r + Vector2(-5, -2), Vector2(10, 5)), Color(OUTLINE, al))
		draw_rect(Rect2(r + Vector2(-4, -1), Vector2(8, 1)), Color(LIT, al))
		if t["broken"]:
			continue
		var k: Vector2 = to_local(t["a"])
		draw_circle(k, 7.5, Color(OUTLINE, al))
		draw_circle(k, 6.0, Color(IRON, al))
		draw_arc(k, 5.0, PI * 1.1, PI * 1.9, 6, Color(LIT, al), 1.0)
		draw_circle(k, 2.5, Color(OUTLINE, al))
		draw_circle(k, 1.5, Color(SEAL, al))
	for ch in _all:
		if ch["snap_t"] < 0.0 or ch["snap_t"] >= SNAP_TIME:
			continue
		var t: float = ch["snap_t"] / SNAP_TIME
		if t >= 0.2:
			continue
		var f: float = 1.0 - t / 0.2
		var p: Vector2 = to_local(ch["a"])
		draw_circle(p, 22.0 * (1.0 - f) + 6.0, Color(SEAL, 0.5 * f))
		draw_circle(p, 10.0 * f + 3.0, Color(FLASH, 0.95 * f))
		# Two broken links flung off.
		for j in 2:
			var d: Vector2 = Vector2.from_angle(ch["phase"] + j * PI) * (8.0 + 30.0 * t / 0.2)
			draw_rect(Rect2(p + d - Vector2(2, 2), Vector2(4, 4)), Color(LIT, f))


static func _link_texture() -> ImageTexture:
	if _tex != null:
		return _tex
	# 14 x 7 px, x runs along the chain: a face-on ring (x 1..9, with a 5 x 3
	# hole the lava shows through) and an edge-on link, a bar from x 10 round to
	# x 0 of the next tile.
	var rows: Array = [
		"..ooooooo.....",
		".oLLLLLLLo....",
		"BoI.....IoBBBB",
		"BoI.....IoBBBB",
		"BoI.....IoBBBB",
		".oIIIIIIIo....",
		"..ooooooo.....",
	]
	var img := Image.create(14, 7, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		var r: String = rows[y]
		for x in r.length():
			match r[x]:
				"o": img.set_pixel(x, y, OUTLINE)
				"I": img.set_pixel(x, y, IRON)
				"L": img.set_pixel(x, y, LIT)
				"B": img.set_pixel(x, y, LIT if y == 2 else (IRON if y == 3 else OUTLINE))
	_tex = ImageTexture.create_from_image(img)
	return _tex
