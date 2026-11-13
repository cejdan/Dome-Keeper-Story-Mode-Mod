extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 122: a long falling lava column draws as one steady stream. A pool
# drains through a 1-wide shaft 14 cells tall into a basin; every frame the
# shaft's drawn shapes are logged. Counted: shape flips (a cell switching
# between stream, body and nothing while the column runs), width jumps
# between frames, and steps between neighbouring cells (the column's edge
# jumping sideways or in width at a cell border). Frame bursts for the eye.

const SHAFT := 14


func boot() -> Dictionary:
	return {"seed": 12345}


var field
var td


func _room(h, a: Vector2i, b: Vector2i) -> void:
	for y in range(a.y - 2, b.y + 3):
		for x in range(a.x - 2, b.x + 3):
			if td.get_resourcev(Vector2i(x, y)) != Data.TILE_EMPTY:
				td.set_resourcev(Vector2i(x, y), Data.TILE_DIRT_START)
	await h.dig_room(a, b)


func _kind(sh: Dictionary) -> String:
	if sh["rect"].size.x <= 0.0 or sh["rect"].size.y <= 0.0:
		return "none"
	return "stream" if sh["stream"] else "body"


# Samples the shaft for `sec` seconds; returns the counts.
func _sample(h, cells: Array, sec: float) -> Dictionary:
	var last: Dictionary = {}
	var flips: int = 0
	var width_jumps: int = 0
	var seam_steps: int = 0
	var frames: int = 0
	var worst_seam: float = 0.0
	var kinds_seen: Dictionary = {}
	var masses: Array = []
	var t0: float = h.now()
	while h.now() - t0 < sec:
		await h.frames(1)
		frames += 1
		if frames % 30 == 1:
			masses.append(cells.map(func(c): return snappedf(field.mass.get(c, 0.0), 0.01)))
		var prev_rect = null
		for c: Vector2i in cells:
			var sh: Dictionary = field._lava_shape(c)
			var k: String = _kind(sh)
			kinds_seen[k] = kinds_seen.get(k, 0) + 1
			var r: Rect2 = sh["rect"]
			if last.has(c):
				var lk: String = last[c][0]
				var lr: Rect2 = last[c][1]
				if lk != k:
					flips += 1
				elif k == "stream" and absf(lr.size.x - r.size.x) >= 4.0:
					width_jumps += 1
			last[c] = [k, r]
			# The seam with the cell above: where both draw as streams, compare the
			# bottom of the upper one with the top of this one.
			if prev_rect != null and k == "stream":
				var a: Rect2 = prev_rect
				var step: float = maxf(absf(a.position.x - r.position.x), absf(a.end.x - r.end.x))
				if field.has_method("stream_edges"):
					var e_up: Vector2 = field.stream_edges(c + Vector2i.UP, 1.0)
					var e_dn: Vector2 = field.stream_edges(c, 0.0)
					step = maxf(absf(e_up.x - e_dn.x), absf(e_up.y - e_dn.y))
				worst_seam = maxf(worst_seam, step)
				if step >= 3.0:
					seam_steps += 1
			prev_rect = r if k == "stream" else null
	return {"masses": masses, "frames": frames, "flips": flips, "width_jumps": width_jumps, "seam_steps": seam_steps, "worst_seam_px": worst_seam, "kinds": kinds_seen}


func run(h) -> void:
	h.disable_waves()
	field = Level.map.get_node("StoryLavaField")
	td = Level.map.tileData
	field.magma.clear()
	field.mass.clear()
	field.shown.clear()
	field.sources.clear()

	# A reservoir 5 wide, 2 tall at row y0; the shaft under its middle; a basin.
	var x0: int = 10
	var y0: int = 30
	var top: Vector2i = Vector2i(x0, y0)
	await _room(h, top + Vector2i(-2, 0), top + Vector2i(2, 1))
	var shaft: Array = []
	for i in SHAFT:
		shaft.append(top + Vector2i(0, 2 + i))
	await h.reveal(shaft)
	await h.clear_tiles(shaft)
	var floor_y: int = y0 + 2 + SHAFT
	await h.dig_room(Vector2i(x0 - 8, floor_y), Vector2i(x0 + 3, floor_y + 4))
	# A viewing gallery beside the shaft for the keeper (and the camera).
	await h.dig_room(Vector2i(x0 + 4, y0 + 6), Vector2i(x0 + 5, y0 + 11))
	await h.teleport_tile(Vector2i(x0 + 5, y0 + 9))
	h.keeper().set("gravity_scale", 0.0)
	h.snap_camera()
	await h.wait(0.5)

	# ---- 1. a steady pour: a source over the shaft keeps it fed
	for x in range(-2, 3):
		field.mass[top + Vector2i(x, 0)] = 1.0
		field.mass[top + Vector2i(x, 1)] = 1.0
	field.sources[top] = 14.0
	field.wake_all()
	await h.wait(1.0)
	var steady: Dictionary = await _sample(h, shaft, 3.0)
	h.note("steady pour", steady)
	await h.burst("steady", 24, 2)

	# ---- 2. the tail: the source stops, the reservoir drains, the column thins
	field.sources.clear()
	await h.burst("tail", 30, 4)
	var tail: Dictionary = await _sample(h, shaft, 4.0)
	h.note("draining tail", tail)
	var fps_total: float = float(steady["frames"] + tail["frames"])
	h.check("the column doesn't flicker between stream and block (shape flips per cell-second < 0.5)", (steady["flips"] + tail["flips"]) / (fps_total / 60.0 * SHAFT) < 0.5, {"steady": steady["flips"], "tail": tail["flips"], "frames": fps_total})
	h.check("stream widths don't jump frame to frame (< 1 per cell-second)", (steady["width_jumps"] + tail["width_jumps"]) / (fps_total / 60.0 * SHAFT) < 1.0, {"steady": steady["width_jumps"], "tail": tail["width_jumps"]})
	h.check("the stream is continuous across cell borders (no seam steps of 3 px or more)", steady["seam_steps"] + tail["seam_steps"] == 0, {"steady": [steady["seam_steps"], steady["worst_seam_px"]], "tail": [tail["seam_steps"], tail["worst_seam_px"]]})
	h.check("the steady pour draws as a stream, not blocks", steady["kinds"].get("stream", 0) > 3 * steady["kinds"].get("body", 0), steady["kinds"])
