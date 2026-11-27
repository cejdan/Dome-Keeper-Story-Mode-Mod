extends Node2D

# The chain anchors (#365, End game 2.0 #363): ten round stones in the lava
# ocean, five round each ocean tentacle (map/story_gen.gd place_anchors, meta
# "story_anchors"), each holding one chain to its tentacle. The goal of the
# ocean: break all ten and the horror is unbound (endgame/end_game.gd).
#
# Each anchor is a 2 x 2 block of map tiles (data/anchors.gd TILE_ID) that
# every keeper mines its own way; the four tiles share every hit
# (extensions/content/map/tile/Tile.gd), so the stone breaks as one. This node
# draws the stone over its tiles (a dark round seal stone with a ring of
# glowing runes and an iron eye), its chain to the tentacle, and the feedback:
#   a hit:   the stone jolts, its runes flare, cracks spread with the damage,
#            a jerk runs up the chain, a low seal pulse sounds;
#   a break: a flash and a shock ring, the stone bursts into chunks, the chain
#            whips back to the tentacle and hangs off it as a stub for the
#            rest of the run, the tentacle flinches (a jump in its swing that
#            eases back) and flashes, the camera shakes near it, a snap, a
#            boom and, far below, the horror stirs.
# Intact anchors glow and send out a slow beacon ring, so they read as the
# goal in the dark and through the lava. Hidden until the player has seen
# them (their tiles or the cells round them).
#
# The host records each break (EndGame.record_break) and clears any of the
# anchor's tiles still standing. Every peer animates a break the moment its
# own copy of the tile goes; a break it only learns from Data (a late join, a
# lost race) shows as already broken, without the animation. A loaded run
# shows broken anchors as their chain stubs.
#
# Cost: chains are Line2Ds given new points only while a view shows them; the
# stones and effects draw only in a view.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const AnchorData = preload("res://mods-unpacked/flantor-StoryMode/data/anchors.gd")
static var _AnchorData = AnchorData  # calls go through this: lazy_preload makes const-preload calls slow
const EndGame = preload("res://mods-unpacked/flantor-StoryMode/endgame/end_game.gd")
static var _EndGame = EndGame  # calls go through this: lazy_preload makes const-preload calls slow
const Sfx = preload("res://mods-unpacked/flantor-StoryMode/boss/sfx.gd")
static var _Sfx = Sfx  # calls go through this: lazy_preload makes const-preload calls slow
const StoryNet = preload("res://mods-unpacked/flantor-StoryMode/net/story_net.gd")
static var _StoryNet = StoryNet  # calls go through this: lazy_preload makes const-preload calls slow

const NAME := "StoryChainAnchors"
const T := 24.0
const RADIUS := 23.0            # the stone, px
const EYE := 15.0               # its iron eye sits this far from the middle, toward the chain
const RUNES := 8
const STEP := 12.0              # px between a chain's points
const SLACK := 1.07             # a chain's length over its rest distance
const SNAP_TIME := 0.9
const FRAG_TIME := 1.6
const STUB_LINKS := 6
const BEACON_PERIOD := 3.2
const SEEN_EVERY := 0.5
const POLL_EVERY := 0.25
const DATA_GRACE := 0.8         # s a break known only from Data waits for the live one
const HIT_SOUND_GAP := 0.22
const CALM_HZ := 30.0           # chains and stones redraw this often when nothing moves fast

const OUTLINE := Color("120e17")
const STONE_DARK := Color("2a2133")
const STONE := Color("463a52")
const STONE_LIGHT := Color("6f5f7e")
const IRON := Color("2b2336")
const LIT := Color("8d84b8")
const SEAL := Color("6b5cff")
const SEAL_LIGHT := Color("b8b0ff")
const SPARK := Color("eeeaff")

static var _tex: ImageTexture

# Each: {id, cell, cells, tentacle, seg, centre (global), rest_len, side,
#   broken, snap_t (-1 none, else s since), dmg (0..1), hit_t, jolt, jolt_t,
#   phase, seen, line, frags, cracks, box}
var anchors: Array = []
var draw_count: int = 0         # chains given new points on the last frame
var process_us: int = 0         # time in _process, all frames (dev timing)
var frames: int = 0
var _by_cell: Dictionary = {}
var _tents = null
var _map = null
var _glow: Node2D
var _t: float = 0.0
var _seen_acc: float = 0.0
var _poll_acc: float = 0.0
var _pending: Dictionary = {}   # id -> s it has been broken in Data, not seen live
var _hit_sound_t: float = 0.0
var _dev_chains: int = -1
var _settled: bool = false
var _views: Array = []          # this frame's view rects (grown 96 px)
var _calm_acc: float = 0.0


static func find():
	if Level.map == null or not is_instance_valid(Level.map):
		return null
	return Level.map.get_node_or_null(NAME)


# --- called by the map and its tiles ------------------------------------------------

# The other tiles of the anchor `c` belongs to.
static func siblings(c: Vector2i) -> Array:
	var n = find()
	if n == null or not n._by_cell.has(c):
		return []
	return n.anchors[n._by_cell[c]]["cells"].filter(func(x): return x != c)


# A struck anchor tile (once per hit, on every peer): `rel` is its health left.
static func tile_hit(c: Vector2i, dmg: float, rel: float) -> void:
	var n = find()
	if n != null and n._by_cell.has(c):
		n._on_hit(n.anchors[n._by_cell[c]], dmg, rel)


# An anchor tile broke (Map.destroyTile, every peer).
static func tile_broken(c: Vector2i) -> void:
	var n = find()
	if n != null and n._by_cell.has(c):
		n._on_broken(n.anchors[n._by_cell[c]])


# --- setup --------------------------------------------------------------------------

func setup(map, tents) -> bool:
	var meta: Array = map.tileData.get_meta("story_anchors", [])
	if meta.is_empty() or tents == null or tents.rigs.is_empty():
		return false
	name = NAME
	z_index = 7          # over the lava (6), with the tentacles (added after: over us), under the keepers
	_map = map
	_tents = tents
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	_glow = Node2D.new()
	_glow.name = "Glow"
	_glow.z_index = 1
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	var lava = map.get_node_or_null("StoryLavaField")
	for m: Dictionary in meta:
		var cell: Vector2i = m["cell"]
		var cells: Array = []
		for dy in AnchorData.SIZE:
			for dx in AnchorData.SIZE:
				cells.append(cell + Vector2i(dx, dy))
		var centre: Vector2 = Vector2.ZERO
		for c: Vector2i in cells:
			centre += map.getTilePos(Vector2(c))
		centre /= cells.size()
		var ti: int = clampi(int(m["tentacle"]), 0, tents.rigs.size() - 1)
		var r = tents.rigs[ti]
		var seg: int = clampi(int(m["seg"]), 1, r.count)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([cell, 365])
		var a: Dictionary = {"id": int(m["id"]), "cell": cell, "cells": cells, "tentacle": ti, "seg": seg,
			"centre": centre, "side": signf(centre.x - r.base.x), "broken": false, "snap_t": -1.0, "dmg": 0.0,
			"hit_t": 99.0, "jolt": 0.0, "jolt_t": 99.0, "phase": rng.randf() * TAU, "seen": false,
			"frags": [], "cracks": _make_cracks(rng), "box": Rect2(centre, Vector2.ZERO)}
		# Its chain's length: a little over the distance at rest.
		var rest: Transform2D = r.transforms_at(0.0, 0.0)[seg - 1 if seg < r.count else r.count]
		a["rest_len"] = maxf(24.0, _eye(a, rest.origin).distance_to(rest.origin)) * SLACK
		var line := Line2D.new()
		line.texture = _link_texture()
		line.texture_mode = Line2D.LINE_TEXTURE_TILE
		line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		line.width = _tex.get_height()
		line.joint_mode = Line2D.LINE_JOINT_SHARP
		line.antialiased = false
		line.show_behind_parent = true    # the stones draw over their chain's end
		line.visible = false
		add_child(line)
		a["line"] = line
		for c: Vector2i in cells:
			_by_cell[c] = anchors.size()
			# An old save's ocean got its anchors on load (gamemode/legacy_saves.gd):
			# its saved lava may still sit in their cells.
			if lava != null and lava.mass.has(c):
				lava.mass.erase(c)
				lava.shown.erase(c)
		var t = map.tiles.get(Vector2(cells[0]))
		if t != null and is_instance_valid(t):
			a["dmg"] = 1.0 - t.relativeHealth()
		anchors.append(a)
	# Already broken (a loaded run): stubs, no snap.
	for a in anchors:
		if _EndGame.is_anchor_broken(a["id"]):
			a["broken"] = true
	if _Story.has_user_arg("chains") and not Network.is_client():
		_dev_chains = clampi(int(_Story.user_arg("chains", "0")), 0, anchors.size())
	_check_seen(true)
	ModLoaderLog.info("Chain anchors: %d, %d broken" % [anchors.size(), anchors.filter(func(x): return x["broken"]).size()], _Story.LOG)
	return true


# Cracks for the damage look: five crooked lines out from near the middle.
func _make_cracks(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var a0: float = rng.randf() * TAU
	for i in 5:
		var ang: float = a0 + TAU * float(i) / 5.0 + rng.randf_range(-0.4, 0.4)
		var p := Vector2.from_angle(ang) * rng.randf_range(2.0, 5.0)
		var pts := PackedVector2Array([p])
		for j in 3:
			ang += rng.randf_range(-0.6, 0.6)
			p += Vector2.from_angle(ang) * rng.randf_range(5.0, 7.0)
			pts.append(p)
		out.append(pts)
	return out


# --- what happens -------------------------------------------------------------------

func _on_hit(a: Dictionary, dmg: float, rel: float) -> void:
	if a["broken"]:
		return
	a["dmg"] = clampf(1.0 - rel, 0.0, 1.0)
	a["hit_t"] = 0.0
	a["jolt"] = clampf(3.0 + dmg * 0.6, 3.0, 9.0)
	a["jolt_t"] = 0.0
	if not a["seen"]:
		_show(a)
	if _hit_sound_t > HIT_SOUND_GAP and _in_view(a, 32.0):
		_hit_sound_t = 0.0
		_Sfx.play("seal", -16.0, 0.8 + 0.6 * a["dmg"])


func _on_broken(a: Dictionary) -> void:
	if a["broken"]:
		return
	a["broken"] = true
	a["snap_t"] = 0.0
	_pending.erase(a["id"])
	if not a["seen"]:
		_show(a)
	_burst(a)
	var last: bool = anchors.all(func(x): return x["broken"])
	var near: bool = _in_view(a, 160.0)
	# The look and the sound, every peer.
	var sh: Array = AnchorData.SHAKE
	InputSystem.shake(float(sh[0]) * (1.6 if last else 1.0), float(sh[1]) * (2.0 if last else 1.0), float(sh[2]), a["centre"])
	if near:
		_Sfx.play("keeper_down", -2.0, 0.75)
		_Sfx.play("boom", -8.0, 0.8)
	# Far below, the horror stirs.
	_Sfx.play("roar", -4.0 if last else -12.0, 0.5 if last else 0.6)
	var r = _tents.rigs[a["tentacle"]]
	var flash := create_tween()
	flash.tween_property(r, "modulate", Color.WHITE, 0.7).from(Color(1.9, 1.5, 2.3))
	# The host: the tentacles flinch (clients get the swing in its clock), the
	# break is recorded, and what is left of the stone goes.
	if Network.is_client():
		return
	for rig in _tents.rigs:
		var k: float = 1.0 if rig == r else 0.5
		rig.share = minf(1.0, rig.share + AnchorData.FLINCH_SHARE * k)
		rig.speed += AnchorData.FLINCH_SPEED * k
	_EndGame.record_break(a["id"])
	_clear_tiles(a)


# The host: any of the anchor's tiles still standing go too (on every peer).
func _clear_tiles(a: Dictionary) -> void:
	for c: Vector2i in a["cells"]:
		if _map.tileData.get_resourcev(c) != AnchorData.TILE_ID:
			continue
		if not _map.tiles.has(Vector2(c)):
			_map.revealTile(Vector2(c))
		var tile = _map.tiles.get(Vector2(c))
		if tile != null and is_instance_valid(tile):
			_StoryNet.tile_break(_map, c)
			_map.destroyTile("team1", "", tile)


# The stone bursts: chunks of it and shards of its runes.
func _burst(a: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([a["cell"], "burst"])
	var frags: Array = []
	for i in 14:
		var ang: float = TAU * float(i) / 14.0 + rng.randf_range(-0.2, 0.2)
		var rune: bool = i % 3 == 0
		frags.append({"p": a["centre"] + Vector2.from_angle(ang) * rng.randf_range(4.0, 16.0),
			"v": Vector2.from_angle(ang) * rng.randf_range(90.0, 220.0) + Vector2(0, -60.0),
			"rot": rng.randf() * TAU, "rv": rng.randf_range(-9.0, 9.0),
			"size": rng.randf_range(2.0, 3.5) if rune else rng.randf_range(3.5, 6.5), "rune": rune})
	a["frags"] = frags


func _show(a: Dictionary) -> void:
	a["seen"] = true
	a["line"].visible = true


# --- every frame -------------------------------------------------------------------

func _process(delta: float) -> void:
	if anchors.is_empty():
		return
	var us0: int = Time.get_ticks_usec()
	frames += 1
	var dt: float = 0.0 if GameWorld.paused else delta
	_t += dt
	_hit_sound_t += delta
	if not _settled:
		_settle()
	_seen_acc += delta
	if _seen_acc >= SEEN_EVERY:
		_seen_acc = 0.0
		_check_seen(false)
	_poll_acc += delta
	if _poll_acc >= POLL_EVERY:
		_poll(_poll_acc)
		_poll_acc = 0.0
	_views = _Story.view_rects(96)
	# Calm (no hit, jolt or break playing): chains and stones at CALM_HZ.
	var busy: bool = false
	for a in anchors:
		if a["hit_t"] < 1.0 or (a["snap_t"] >= 0.0 and a["snap_t"] < FRAG_TIME):
			busy = true
			break
	_calm_acc += delta
	if not busy and _calm_acc < 1.0 / CALM_HZ:
		for a in anchors:
			a["hit_t"] += dt
			a["jolt_t"] += dt
		process_us += Time.get_ticks_usec() - us0
		return
	_calm_acc = 0.0
	draw_count = 0
	var any: bool = false
	for a in anchors:
		a["hit_t"] += dt
		a["jolt_t"] += dt
		if a["snap_t"] >= 0.0 and a["snap_t"] < FRAG_TIME:
			a["snap_t"] += dt
			for f in a["frags"]:
				f["v"] += Vector2(0, 340.0) * dt
				f["v"] *= 1.0 - 1.5 * dt
				f["p"] += f["v"] * dt
				f["rot"] += f["rv"] * dt
		if not a["seen"]:
			continue
		var b: Vector2 = _attach(a)
		a["box"] = Rect2(a["centre"], Vector2.ZERO).expand(b).grow(RADIUS + 60.0)
		a["shown"] = _box_in_view(a["box"])
		if not a["shown"]:
			continue
		any = true
		_update_line(a, b)
		draw_count += 1
	if any or _drawn:
		queue_redraw()
		_glow.queue_redraw()
	_drawn = any
	process_us += Time.get_ticks_usec() - us0


var _drawn: bool = false


func _box_in_view(box: Rect2) -> bool:
	for v: Rect2 in _views:
		if v.intersects(box):
			return true
	return false


# The host, once, a moment after setup: a loaded run's record and its tiles
# agree, the tentacles follow it, and `--chains=N` (dev) breaks the first N.
func _settle() -> void:
	if not _map.isMapReady():
		return
	_settled = true
	if Network.is_client():
		return
	load(_Story.MOD_DIR + "gamemode/legacy_saves.gd").drop_data()
	for a in anchors:
		var standing: bool = a["cells"].any(func(c): return _map.tileData.get_resourcev(c) == AnchorData.TILE_ID)
		if a["broken"] and standing:
			_clear_tiles(a)
		elif not a["broken"] and not standing:
			# Its tiles are gone but the break was never recorded.
			a["broken"] = true
			_EndGame.record_break(a["id"])
	_EndGame._sync_tentacles()
	if _dev_chains > 0:
		for a in anchors:
			if not a["broken"] and anchors.filter(func(x): return x["broken"]).size() < _dev_chains:
				dev_break(a["id"], false)
	# `--free` (dev, boot key `free`): the run as a save made after the last chain.
	if _Story.has_user_arg("free"):
		dev_free_all()


# Dev and playtests (host): every anchor broken quietly, its stone gone and a
# stub left, no snap, no live moment (EndGame.dev_free): the lair seal (#366)
# just shows open. `--free` at a run's start; `--boss` before the fight.
func dev_free_all() -> void:
	if Network.is_client():
		return
	var gone: Array = []
	for a in anchors:
		if not a["broken"]:
			a["broken"] = true
			gone.append(a)
	_EndGame.dev_free()
	_clear_later(gone)


# The stones' tiles go once the view is real: right at a run's start an
# off-screen harness window reports a negative view rect, and vanilla's tile
# break particles then log "Rect2 size is negative" for every tile.
func _clear_later(list: Array) -> void:
	while is_inside_tree() and get_viewport().get_visible_rect().size.y <= 0.0:
		await get_tree().process_frame
	for a in list:
		_clear_tiles(a)


# Breaks anchor `id` as a keeper would (host; dev and playtests): its tiles
# go, and the break plays and is recorded through the same path.
func dev_break(id: int, animate: bool = true) -> void:
	if Network.is_client():
		return
	for a in anchors:
		if a["id"] != id or a["broken"]:
			continue
		if not animate:
			a["broken"] = true
			_EndGame.record_break(id)
			_clear_tiles(a)
		else:
			var c: Vector2i = a["cells"][0]
			if not _map.tiles.has(Vector2(c)):
				_map.revealTile(Vector2(c))
			var tile = _map.tiles.get(Vector2(c))
			if tile != null:
				_StoryNet.tile_break(_map, c)
				_map.destroyTile("team1", "", tile)
		return


# Breaks the record shows that this peer has not seen live: after a moment
# (the live one may be on its way), shown as already broken.
func _poll(step: float) -> void:
	for a in anchors:
		if a["broken"] or not _EndGame.is_anchor_broken(a["id"]):
			continue
		_pending[a["id"]] = float(_pending.get(a["id"], 0.0)) + step
		if _pending[a["id"]] >= DATA_GRACE:
			_pending.erase(a["id"])
			a["broken"] = true


func _check_seen(instant: bool) -> void:
	var vis: Dictionary = _map.visibleTileCoords
	for a in anchors:
		if a["seen"]:
			continue
		for c: Vector2i in a["cells"]:
			if vis.has(Vector2(c)) or vis.has(Vector2(c + Vector2i(-1, 0))) or vis.has(Vector2(c + Vector2i(0, -1))):
				_show(a)
				break


func _in_view(a: Dictionary, grow: float) -> bool:
	for v: Rect2 in _Story.view_rects(grow):
		if v.has_point(a["centre"]):
			return true
	return false


# Where the anchor's chain meets its tentacle, global: the side of its
# segment that faces the anchor (or the tip's), a little in from the edge so
# the tentacle covers the chain's end.
func _attach(a: Dictionary) -> Vector2:
	var r = _tents.rigs[a["tentacle"]]
	var body = r.pad if a["seg"] >= r.count else r.segments[a["seg"] - 1]
	var tr: Transform2D = body.global_transform
	var local: Vector2 = tr.affine_inverse() * a["centre"]
	var hw: float = (r.pad_width if body == r.pad else body.width) * 0.5
	var x: float = r.pad_height * 0.35 if body == r.pad else 0.0
	return tr * Vector2(x, signf(local.y) * hw * 0.6)


func _eye(a: Dictionary, toward: Vector2) -> Vector2:
	var c: Vector2 = a["centre"]
	return c + (toward - c).normalized() * EYE


func _update_line(a: Dictionary, b: Vector2) -> void:
	var line: Line2D = a["line"]
	var e: Vector2 = _eye(a, b)
	if not a["broken"]:
		line.points = _chain_points(e, b, a["rest_len"], a, 0.0)
		return
	var st: float = a["snap_t"]
	if st >= 0.0 and st < SNAP_TIME:
		# The free end whips back toward the tentacle, overshoots and drops.
		var u: float = st / SNAP_TIME
		var k: float = 1.0 - pow(1.0 - u, 3.0)
		var hang: Vector2 = b + _hang_dir(a, b).rotated(sin(_t * 1.7 + a["phase"]) * 0.25) * _stub_len()
		var free_end: Vector2 = e.lerp(hang, k) + (e - b).normalized().orthogonal() * sin(PI * u) * 28.0 * signf(a["side"])
		line.points = _chain_points(b, free_end, b.distance_to(free_end) * (1.0 + 0.3 * (1.0 - u)), a, 0.0)
		return
	# Broken: a stub of links hanging off the tentacle's side, swaying.
	var sway: float = sin(_t * 1.7 + a["phase"]) * 0.25
	var d: Vector2 = _hang_dir(a, b)
	var mid: Vector2 = b + d.rotated(sway * 0.5) * _stub_len() * 0.5
	var tip: Vector2 = b + d.rotated(sway) * _stub_len()
	line.points = PackedVector2Array([to_local(b), to_local(mid), to_local(tip)])


# Down and out from the tentacle toward where the anchor was, so the stub
# hangs clear of the tentacle's body.
func _hang_dir(a: Dictionary, b: Vector2) -> Vector2:
	return Vector2(signf(a["centre"].x - b.x) * 0.9, 1.0).normalized()


func _stub_len() -> float:
	return float(STUB_LINKS) * _link_texture().get_width() * 0.5


# From `a` to `b`: a sag by the slack left of `length`, a slow sway, and a jerk
# running from the anchor to the tentacle after a hit.
func _chain_points(a: Vector2, b: Vector2, length: float, anc: Dictionary, _extra: float) -> PackedVector2Array:
	var d: float = maxf(1.0, a.distance_to(b))
	var n: int = maxi(3, int(d / STEP))
	var dir: Vector2 = (b - a) / d
	var normal: Vector2 = Vector2(-dir.y, dir.x)
	var sag: float = sqrt(maxf(0.0, length * length - d * d)) * 0.5
	var jolt: float = anc["jolt"] * exp(-anc["jolt_t"] * 3.0)
	var front: float = anc["jolt_t"] * 2.2
	var out := PackedVector2Array()
	out.resize(n + 1)
	for i in n + 1:
		var s: float = float(i) / float(n)
		var arc: float = 4.0 * s * (1.0 - s)
		var off: Vector2 = Vector2(0, sag * arc)
		off += normal * sin(_t * 1.3 + anc["phase"] + s * 3.0) * 2.0 * arc
		if jolt > 0.05:
			off += normal * jolt * exp(-pow((s - front) * 5.0, 2.0)) * sin(s * 18.0)
		out[i] = to_local(a.lerp(b, s) + off)
	return out


# --- the look ------------------------------------------------------------------------

func _draw() -> void:
	for a in anchors:
		if not a["seen"] or not a.get("shown", false):
			continue
		if not a["broken"]:
			_draw_stone(a)
		elif a["snap_t"] >= 0.0 and a["snap_t"] < FRAG_TIME:
			_draw_frags(a)


func _draw_stone(a: Dictionary) -> void:
	var c: Vector2 = to_local(a["centre"])
	# A hit jolts the stone.
	var j: float = a["jolt"] * exp(-a["hit_t"] * 14.0) * 0.4
	if j > 0.05:
		c += Vector2(sin(a["hit_t"] * 90.0), cos(a["hit_t"] * 70.0)) * j
	var flare: float = exp(-a["hit_t"] * 6.0)
	var pulse: float = 0.5 + 0.5 * sin(_t * 2.2 + a["phase"])
	draw_circle(c, RADIUS + 1.5, OUTLINE)
	draw_circle(c, RADIUS, STONE_DARK)
	draw_circle(c + Vector2(-2.0, -2.0), RADIUS - 3.0, STONE)
	draw_arc(c, RADIUS - 2.5, PI * 1.05, PI * 1.6, 10, STONE_LIGHT, 2.0)
	# The rune ring: a groove, then glyphs that glow with the seal.
	draw_arc(c, 15.5, 0.0, TAU, 28, OUTLINE, 3.0)
	var rune: Color = SEAL.lerp(SEAL_LIGHT, 0.35 * pulse + 0.65 * flare)
	for i in RUNES:
		var ang: float = TAU * float(i) / float(RUNES) + 0.2
		var p: Vector2 = c + Vector2.from_angle(ang) * 15.5
		var t: Vector2 = Vector2.from_angle(ang + PI / 2.0)
		var rad: Vector2 = Vector2.from_angle(ang)
		match i % 3:
			0:
				draw_line(p - t * 2.5, p + t * 2.5, rune, 1.5)
				draw_line(p, p + rad * 2.5, rune, 1.5)
			1:
				draw_line(p - rad * 2.0 - t * 2.0, p + rad * 2.0 + t * 2.0, rune, 1.5)
				draw_line(p - t * 2.0, p + t * 2.0, rune, 1.0)
			_:
				draw_circle(p, 1.6, rune)
	# Cracks, more and longer as it takes damage, the seal showing through.
	var shown: int = ceili(a["dmg"] * 5.0)
	for i in mini(shown, a["cracks"].size()):
		var pts: PackedVector2Array = a["cracks"][i]
		var grow: float = clampf(a["dmg"] * 5.0 - float(i), 0.3, 1.0)
		var poly := PackedVector2Array()
		for p in pts:
			poly.append(c + p * grow)
		draw_polyline(poly, OUTLINE, 2.5)
		draw_polyline(poly, SEAL_LIGHT.lerp(SPARK, flare), 1.0)
	# The iron eye the chain runs from, on the rim facing it.
	var b: Vector2 = to_local(_attach(a))
	var e: Vector2 = c + (b - c).normalized() * EYE
	draw_circle(e, 5.5, OUTLINE)
	draw_circle(e, 4.5, IRON)
	draw_arc(e, 3.5, PI * 1.1, PI * 1.9, 6, LIT, 1.0)
	draw_circle(e, 2.0, OUTLINE)


func _draw_frags(a: Dictionary) -> void:
	var t: float = a["snap_t"] / FRAG_TIME
	var alpha: float = 1.0 - t * t
	for f in a["frags"]:
		var p: Vector2 = to_local(f["p"])
		var s: float = f["size"]
		var rot: Vector2 = Vector2.from_angle(f["rot"])
		var q := PackedVector2Array([p + rot * s, p + rot.orthogonal() * s * 0.8, p - rot * s * 0.9, p - rot.orthogonal() * s * 0.7])
		if f["rune"]:
			draw_colored_polygon(q, Color(SEAL_LIGHT, alpha))
		else:
			draw_colored_polygon(q, Color(OUTLINE, alpha))
			var inner := PackedVector2Array()
			for v in q:
				inner.append(p + (v - p) * 0.6)
			draw_colored_polygon(inner, Color(STONE, alpha))


# Additive: each intact stone's halo and beacon ring; a break's flash and
# shock ring.
func _draw_glow() -> void:
	for a in anchors:
		if not a["seen"] or not a.get("shown", false):
			continue
		var c: Vector2 = to_local(a["centre"])
		if not a["broken"]:
			var pulse: float = 0.5 + 0.5 * sin(_t * 2.2 + a["phase"])
			var flare: float = exp(-a["hit_t"] * 6.0)
			_glow.draw_circle(c, RADIUS + 10.0 + 6.0 * flare, Color(SEAL, 0.10 + 0.05 * pulse + 0.25 * flare))
			_glow.draw_circle(c, 15.5, Color(SEAL, 0.10 + 0.08 * pulse + 0.3 * flare))
			var f: float = fposmod(_t / BEACON_PERIOD + a["phase"] / TAU, 1.0)
			_glow.draw_arc(c, RADIUS + 4.0 + 46.0 * f, 0.0, TAU, 40, Color(SEAL_LIGHT, 0.32 * (1.0 - f)), 2.0)
			# The seal's pull: a glint running up the chain to the tentacle.
			var pts: PackedVector2Array = a["line"].points
			if pts.size() >= 2:
				var u: float = fposmod(_t * 0.45 + a["phase"] / TAU, 1.0) * float(pts.size() - 1)
				var i: int = mini(int(u), pts.size() - 2)
				var p: Vector2 = pts[i].lerp(pts[i + 1], u - float(i))
				_glow.draw_circle(p, 4.0, Color(SEAL, 0.35))
				_glow.draw_circle(p, 2.0, Color(SEAL_LIGHT, 0.6))
		elif a["snap_t"] >= 0.0 and a["snap_t"] < 0.6:
			var u: float = a["snap_t"] / 0.6
			_glow.draw_circle(c, 10.0 + 60.0 * u, Color(SPARK, 0.9 * (1.0 - u) * (1.0 - u)))
			_glow.draw_arc(c, 18.0 + 150.0 * u, 0.0, TAU, 48, Color(SEAL_LIGHT, 0.8 * (1.0 - u)), 4.0 * (1.0 - u) + 1.0)


static func _link_texture() -> ImageTexture:
	if _tex != null:
		return _tex
	# 14 x 7 px, x runs along the chain: a face-on ring (x 1..9, with a 5 x 3
	# hole the lava shows through) and an edge-on link, a bar from x 10 round to
	# x 0 of the next tile (the look of the seal chains, #101).
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
