extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #364: the lava ocean's two climbable tentacles on a generated Story Mode map.
#   - placement: two, one each side of the boss chamber's middle, standing on
#     rock, tip pads under the ceiling with two rows clear, every swing cell
#     open, kept clear of the chamber's entries; a map picture with them on;
#   - hidden until the ocean is seen, then shown;
#   - no body ever overlaps rock over a full cycle at 10 chains (sampled);
#   - wake: chains 0, 2, 5, 8, 10 broken -> the tip swing grows step by step,
#     barely moving at 0 (under 1.5 tiles) and several tiles at 10 (over 6);
#     the pad's tilt at each; screenshots of each and a burst at 10;
#   - set_chains_broken clamps and saves to Data; `--chains=N` is read at setup.
# `-Extra "--mapsize=regular-small"` (or medium, large) checks a smaller map.

const Ocean = preload("res://mods-unpacked/flantor-StoryMode/map/ocean_tentacles.gd")
static var _Ocean = Ocean  # calls go through this: lazy_preload makes const-preload calls slow
const LavaData = preload("res://mods-unpacked/flantor-StoryMode/data/lava.gd")
const TentData = preload("res://mods-unpacked/flantor-StoryMode/data/tentacles.gd")
const TIMEOUT := 420
const T := 24.0


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	var td = Level.map.tileData
	var ocean: Dictionary = td.get_meta("story_ocean", {})
	var ch: Rect2i = td.get_meta("story_boss_chamber", Rect2i())
	var places: Array = td.get_meta("story_tentacles", [])
	h.note("ocean", {"top": ocean.get("top"), "bottom": ocean.get("bottom"), "ceiling": ocean.get("ceiling"), "x0": ocean.get("x0"), "x1": ocean.get("x1"), "chamber": [ch.position.x, ch.size.x]})
	h.note("placements", places)
	if not h.check("the generator placed two tentacles", places.size() == 2, places.size()):
		return
	h.check("one on each side of the chamber's middle", int(places[0]["side"]) == -1 and int(places[1]["side"]) == 1 and int(places[0]["x"]) < 0 and int(places[1]["x"]) > -1, [places[0]["x"], places[1]["x"]])
	var ceiling: int = int(ocean["ceiling"])
	var bad_open: Array = []
	var near_entry: Array = []
	for p: Dictionary in places:
		var x: int = int(p["x"])
		h.check("tentacle at x %d: its pad's top row is the ceiling + %d" % [x, 1 + TentData.TIP_CLEAR_ROWS], int(p["tip_row"]) == ceiling + 1 + TentData.TIP_CLEAR_ROWS, p["tip_row"])
		h.check("tentacle at x %d stands on rock (row %d)" % [x, int(p["base_row"])], not Level.map.is_tile_empty(Vector2i(x, int(p["base_row"]))))
		h.check("tentacle at x %d is %d+ tiles tall" % [x, TentData.MIN_TILES], int(p["base_row"]) - int(p["tip_row"]) >= TentData.MIN_TILES, int(p["base_row"]) - int(p["tip_row"]))
		for y in range(ceiling + 1, int(p["base_row"])):
			if not Level.map.is_tile_empty(Vector2i(x, y)) and td.get_resourcev(Vector2i(x, y)) != Data.TILE_EMPTY:
				bad_open.append(Vector2i(x, y))
		for col in LavaData.BOSS_CHAMBER_ENTRY:
			if absi(x - (ch.position.x + int(col))) <= TentData.ENTRY_GAP:
				near_entry.append([x, col])
	h.check("every tentacle's column is open from the ceiling down to its base", bad_open.is_empty(), bad_open.slice(0, 6))
	h.check("no base next to a chamber entry", near_entry.is_empty(), near_entry)

	var tents = _Ocean.find()
	if not h.check("the ocean tentacles are built", tents != null and tents.rigs.size() == 2):
		return
	h.note("rigs", tents.rigs.map(func(r): return {"segments": r.count, "seg_len": snappedf(r.seg_len, 0.01), "base": r.base, "amp": snappedf(r.amp, 0.001)}))
	h.check("hidden before the ocean is seen", not tents.visible)
	h.check("the swing starts at 0 chains broken (wake 0)", _Ocean.chains_broken() == 0 and is_equal_approx(tents.rigs[0].share, TentData.WAKE_SHARE[0]))

	# Rock overlap over a full cycle at 10 chains, sampled from the rigs' own
	# pose math (transforms_at: the bodies sync to physics, so moving them
	# from here would not take).
	var hits: Array = []
	var points: int = 0
	var overlay: Dictionary = {}
	var root_cells: Dictionary = {}   # where each stands, sunk into its rock by design
	for p: Dictionary in places:
		for dx in range(-2, 3):
			root_cells[Vector2i(int(p["x"]) + dx, int(p["base_row"]))] = true
			root_cells[Vector2i(int(p["x"]) + dx, int(p["base_row"]) + 1)] = true
	for r in tents.rigs:
		var bodies: Array = r.bodies()
		for s in 64:
			var xfs: Array = r.transforms_at(TAU * 2.0 * float(s) / 64.0, 1.0)
			for i in bodies.size():
				for pt in _body_points(bodies[i], xfs[i]):
					points += 1
					var c: Vector2i = Vector2i(Level.map.getTileCoord(pt))
					if s % 8 == 0:
						overlay[c] = Color(1.0, 0.3, 0.9)
					if not root_cells.has(c) and not Level.map.is_tile_empty(c) and td.get_resourcev(c) != Data.TILE_EMPTY:
						hits.append([r.name, s, c])
	h.note("swing sampled", {"points": points, "cells": overlay.size()})
	h.check("the swing was sampled (tens of thousands of points, hundreds of cells)", points > 20000 and overlay.size() > 200, [points, overlay.size()])
	h.check("no tentacle body overlaps rock anywhere in a full swing at 10 chains (bar its root in the floor)", hits.is_empty(), hits.slice(0, 6))
	# Map picture: the tentacles' cells over the swing, their bases white.
	for p: Dictionary in places:
		overlay[Vector2i(int(p["x"]), int(p["base_row"]))] = Color(1, 1, 1)
	h.map_png("ocean_tentacles_reach", {}, 6, null, overlay)

	# See the ocean: reveal round the tentacles, gear, onto the left tip.
	var cells: Array = []
	for p: Dictionary in places:
		for y in range(int(p["tip_row"]) - 3, int(p["base_row"]) + 1):
			for dx in range(-9, 10):
				cells.append(Vector2i(int(p["x"]) + dx, y))
	await h.reveal(cells)
	await h.wait(1.0)
	h.check("shown once the ocean is seen", tents.visible and tents.seen)
	load("res://mods-unpacked/flantor-StoryMode/dev/boss_dev.gd").give_gear()
	var k = h.keeper()
	var rig0 = tents.rigs[0]
	k.teleport(rig0.pad_top_now() + Vector2(0, -14))
	tents.refresh_near()
	h.snap_camera(k)
	await h.wait(1.0)
	await h.shot("left_tip_0_chains")
	_cool(k)

	# Wake by chains broken.
	var swings: Array = []
	for n in [0, 2, 5, 8, 10]:
		_Ocean.set_chains_broken(n)
		await h.wait(0.2)
		for r in tents.rigs:
			r.snap_to_target()
		var m: Dictionary = await _measure(h, tents.rigs)
		swings.append(m["swing"])
		h.note("%d chains: wake %.1f, share %.2f, speed %.2f, tip swing %.1f px, pad tilt max %.1f deg" % [n, _Ocean.wake_for(n), tents.rigs[0].share, tents.rigs[0].speed, m["swing"], m["tilt"]])
		_cool(k)
		k.teleport(rig0.pad_top_now() + Vector2(0, -14))
		tents.refresh_near()
		h.snap_camera(k)
		await h.wait(0.4)
		await h.shot("tip_%d_chains" % n)
		if n == 10:
			await h.burst("tip_10_chains", 10, 6)
			# The middle: where it leaves the lava.
			var mid = rig0.segments[rig0.count - 7]
			k.teleport(mid.global_position + Vector2(-60, -30))
			tents.refresh_near()
			h.snap_camera(k)
			await h.wait(0.3)
			await h.shot("waterline_10_chains")
			_cool(k)
	h.check("0 chains: barely moving (tip swing under 1.5 tiles)", swings[0] > 1.0 and swings[0] < 36.0, swings[0])
	h.check("10 chains: swinging hard (tip swing over 6 tiles)", swings[4] > 144.0, swings[4])
	var rising: bool = true
	for i in range(1, swings.size()):
		if swings[i] <= swings[i - 1]:
			rising = false
	h.check("each step of chains broken swings it wider", rising, swings)

	# The API: clamps, saves to Data, a wake per count.
	_Ocean.set_chains_broken(14)
	h.check("set_chains_broken clamps to 10", _Ocean.chains_broken() == 10 and int(Data.ofOr(_Ocean.CHAINS_KEY, -1)) == 10)
	_Ocean.set_chains_broken(-3)
	h.check("... and to 0", _Ocean.chains_broken() == 0)
	h.check("wake_for maps 0..10 onto 0..4", is_equal_approx(_Ocean.wake_for(0), 0.0) and is_equal_approx(_Ocean.wake_for(5), 2.0) and is_equal_approx(_Ocean.wake_for(10), 4.0))
	# The ease: from 0 to 10 chains takes a while, never a snap.
	await h.wait(0.2)
	for r in tents.rigs:
		r.snap_to_target()
	_Ocean.set_chains_broken(10)
	await h.wait(1.0)
	var s1: float = tents.rigs[0].share
	h.check("a new wake eases in (one second after 0 -> 10 the swing is part way)", s1 > TentData.WAKE_SHARE[0] and s1 < 0.5, s1)


func _cool(k) -> void:
	var lava = Level.map.get_node_or_null("StoryLavaField")
	if lava != null:
		lava.set_heat_of(k, 0.0)


# Points round a body's outline, global, with the body at `xf`.
func _body_points(b, xf: Transform2D) -> Array:
	var out: Array = []
	if "length" in b:
		var hl: float = b.length * 0.5
		var a: float = b.w_root * 0.5
		var c: float = b.w_tip * 0.5
		for f in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var x: float = lerpf(-hl, hl, f)
			var w: float = lerpf(a, c, f)
			out.append(xf * Vector2(x, -w))
			out.append(xf * Vector2(x, w))
		out.append(xf * Vector2(-hl - a, 0))
	else:
		for p in b.outline(0.0):
			out.append(xf * p)
	return out


# Peak-to-peak tip movement and the pad's largest tilt (degrees) over one full
# cycle of the wave clock (4 pi: the slow lean's period).
func _measure(h, rigs: Array) -> Dictionary:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var tilt: float = 0.0
	var t0: float = rigs[0].t
	var frames: int = 0
	while rigs[0].t - t0 < TAU * 2.0 and frames < 60 * 45:
		await h.get_tree().physics_frame
		frames += 1
		var p: Vector2 = rigs[0].tip()
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		for r in rigs:
			tilt = maxf(tilt, rad_to_deg(r.pad_tilt()))
	return {"swing": (hi - lo).length(), "tilt": tilt, "seconds": frames / 60.0}
