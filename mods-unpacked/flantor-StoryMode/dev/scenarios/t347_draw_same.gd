extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t347_meter.gd"

# Ticket 347: the reworked lava and gas drawing draws the same picture as
# before. With the game paused (so nothing moves between the two), one frame is
# drawn by the fields as they are now and one by the code from before #347
# (copied below from main, run on the same fields), and the two screenshots are
# compared pixel by pixel (since the ocean shader, a sliver may differ: see compare()). Pixels that change on their own (two shots of each
# drawing) are left out, and the keepers are hidden meanwhile. Run where there is lava, streams, magma, gas rock
# and puffs in view: the ocean scenario's shaft and the gas rooms.

const TIMEOUT := 300


const TOL := 4                 # colour steps (of 255) a channel may be off
const LF = preload("res://mods-unpacked/flantor-StoryMode/lava/lava_field.gd")
const GF = preload("res://mods-unpacked/flantor-StoryMode/gas/gas_field.gd")



func boot() -> Dictionary:
	return {"seed": 12345, "mapsize": "regular-medium"}


func _image(h) -> Image:
	await h.frames(3)
	await RenderingServer.frame_post_draw
	return h.get_viewport().get_texture().get_image()


# Draws the paused frame with the fields' own code (A) and with the old code
# twice (B1, B2), and counts pixels where A and B1 differ (leaving out those
# where B1 and B2 differ: they change on their own).
func compare(h, label: String) -> void:
	var tree: SceneTree = h.get_tree()
	tree.paused = true
	# The keepers animate even now; they are not what is compared.
	var ks: Array = h.local_keepers()
	for k in ks:
		k.visible = false
	# Each old drawer is its field's first child: drawn right after the
	# field's own (then invisible) drawing, before its other children, so it
	# sits where the field's drawing sits among everything else.
	var old_lava := LegacyLava.new()
	old_lava.f = _lava
	var old_gas := LegacyGas.new()
	old_gas.f = _gas
	_lava.add_child(old_lava)
	_lava.move_child(old_lava, 0)
	_gas.add_child(old_gas)
	_gas.move_child(old_gas, 0)
	old_lava.visible = false
	old_gas.visible = false
	_lava.queue_redraw()
	_lava._glow.queue_redraw()
	_gas.queue_redraw()
	var a: Image = await _image(h)
	_lava.self_modulate.a = 0.0
	_lava._glow.visible = false
	if _lava._ob != null:
		_lava._ob.visible = false
		_lava._og.visible = false
	_gas.self_modulate.a = 0.0
	old_lava.visible = true
	old_gas.visible = true
	old_lava.redraw()
	old_gas.queue_redraw()
	var b1: Image = await _image(h)
	old_lava.redraw()
	old_gas.queue_redraw()
	var b2: Image = await _image(h)
	_lava.self_modulate.a = 1.0
	_lava._glow.visible = true
	if _lava._ob != null:
		_lava._ob.visible = true
		_lava._og.visible = true
	_gas.self_modulate.a = 1.0
	old_lava.visible = false
	old_gas.visible = false
	_lava.queue_redraw()
	_lava._glow.queue_redraw()
	_gas.queue_redraw()
	var a2: Image = await _image(h)
	old_lava.queue_free()
	old_gas.queue_free()
	for k in ks:
		k.visible = true
	tree.paused = false
	var diff := 0
	var small := 0
	var noisy := 0
	var lavaish := 0
	var box := Rect2i()
	var dimg := Image.create(a.get_width(), a.get_height(), false, Image.FORMAT_RGBA8)
	for y in a.get_height():
		for x in a.get_width():
			var pa: Color = a.get_pixel(x, y)
			var pb: Color = b1.get_pixel(x, y)
			if not pb.is_equal_approx(b2.get_pixel(x, y)) or not pa.is_equal_approx(a2.get_pixel(x, y)):
				noisy += 1
				continue
			small = maxi(small, maxi(absi(pa.r8 - pb.r8), maxi(absi(pa.g8 - pb.g8), absi(pa.b8 - pb.b8))))
			if absi(pa.r8 - pb.r8) > TOL or absi(pa.g8 - pb.g8) > TOL or absi(pa.b8 - pb.b8) > TOL:
				diff += 1
				dimg.set_pixel(x, y, Color.MAGENTA)
				box = Rect2i(x, y, 1, 1) if box.size == Vector2i.ZERO else box.expand(Vector2i(x, y))
			# A pixel lit warm (lava, its glow, cracks): how much of the frame the check covered.
			if pa.r > 0.35 and pa.r > pa.b * 1.5:
				lavaish += 1
	a.save_png(h.out_dir.path_join("%s_new.png" % label))
	b1.save_png(h.out_dir.path_join("%s_old.png" % label))
	if diff > 0:
		dimg.save_png(h.out_dir.path_join("%s_diff.png" % label))
	var info := {"differing pixels": diff, "largest channel difference": small, "left out (moving)": noisy, "lava-lit pixels": lavaish, "diff box": [box.position, box.size],
		"lava cells drawn": _lava._vis_cache.size(), "magma": _lava.magma.size(), "gas rock": _gas.rock.size(), "lava puffs": _lava._puffs.size(), "gas puffs": _gas._puffs.size()}
	# Allowed: a few px where the ocean shader's cells sit under something an
	# earlier cell spilled into them (a film's 1 px surface line on a full cell
	# below it), which the old drawing painted over (#347).
	# Colour distance too: the ocean's glow is now summed in one pass, so its
	# light can be a step or two off in a channel where many cells overlap.
	h.check("%s: the new drawing matches the old (%d px differ by more than %d steps; at most 0.2%% of the lava-lit %d)" % [label, diff, TOL, lavaish], diff <= lavaish * 0.002 and lavaish > 500, info)


func run(h) -> void:
	h.disable_waves()
	var map = Level.map
	var td = map.tileData
	var o: Dictionary = td.get_meta("story_ocean", {})
	var ceiling: int = int(o["ceiling"])
	_lava = map.get_node("StoryLavaField")
	_gas = map.get_node("StoryGasField")
	_gas.freeze_toxin = true
	_hold_heat = true
	Engine.get_main_loop().process_frame.connect(_on_frame)
	var x := 4
	for y in range(ceiling - 12, ceiling + 1):
		for dx in range(-3, 4):
			var c := Vector2i(x + dx, y)
			td.set_resourcev(c, Data.TILE_DIRT_START)
			if td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE or td.get_hardnessv(c) < 0:
				td.set_hardnessv(c, Data.HARDNESS_MEDIUM)
	await h.dig_room(Vector2i(x, ceiling - 12), Vector2i(x, ceiling))
	# A ledge with lava on it beside the shaft: it pours down the shaft as a stream.
	await h.dig_room(Vector2i(x + 1, ceiling - 9), Vector2i(x + 2, ceiling - 9))
	var ledge := Vector2i(x + 2, ceiling - 9)
	_lava.mass[ledge] = 6.0
	_lava.shown[ledge] = 6.0
	_lava.wake_all()
	# Magma and gas rock in the shaft's walls, where the player can see them.
	_lava.add_pocket([Vector2i(x - 1, ceiling - 5), Vector2i(x - 1, ceiling - 6)])
	_gas.add_pocket([Vector2i(x + 1, ceiling - 4), Vector2i(x + 1, ceiling - 3)])
	await h.teleport_tile(Vector2i(x, ceiling - 6))
	await h.wait(3.0)
	await h.shot("shaft")
	await compare(h, "shaft")
	await h.wait(2.5)
	await compare(h, "shaft_later")
	# The ocean filling the screen.
	await h.teleport_tile(Vector2i(x, ceiling + 9))
	await h.wait(1.5)
	await h.shot("ocean")
	await compare(h, "ocean")
	# The lava's own cost a redraw here, with and without the ocean shader.
	var per: Dictionary = {}
	for i in 2:
		for off in [false, true]:
			_lava.no_ocean_shader = off
			_lava._view_dirty = true
			await h.frames(5)
			var d0: int = _lava.draw_us
			var g0: int = _lava.glow_us
			var s0: int = _lava.sorts
			var p0: int = _lava.phys_frames
			await h.wait(3.0)
			var k: String = "cpu only" if off else "ocean shader"
			var nf: int = maxi(1, _lava.phys_frames - p0)
			per[k] = per.get(k, []) + [{"ms": snappedf(float(_lava.draw_us + _lava.glow_us - d0 - g0) / nf / 1000.0, 0.001),
				"glow ms": snappedf(float(_lava.glow_us - g0) / nf / 1000.0, 0.001), "sorted share": snappedf(float(_lava.sorts - s0) / nf, 0.01)}]
	_lava.no_ocean_shader = false
	_lava._view_dirty = true
	h.note("lava draw ms a redraw, in the ocean", per)
	ModLoaderLog.info("t347 lava draw a redraw: %s" % JSON.stringify(per), "flantor-StoryMode")
	meter_stop()


class LegacyLava extends Node2D:
	var f
	var glow: Node2D

	func _ready() -> void:
		glow = Node2D.new()
		glow.material = f._glow.material
		glow.z_index = f._glow.z_index
		glow.draw.connect(func(): draw_glow_old(glow))
		add_child(glow)

	func redraw() -> void:
		queue_redraw()
		glow.queue_redraw()

	func _draw() -> void:
		# Magma rock the player can see: glowing cracks that pulse. (The view boxes
		# come from f._visible_cells(), so it runs first.)
		var vis: Array = f._visible_cells()
		for c in f.magma:
			if not f._in_boxes(c) or not f.map.tiles.has(Vector2(c)):
				continue
			var o = f._cell_origin(c)
			var pulse: float = 0.55 + 0.45 * sin(f._time * 3.0 + c.x * 1.7 + c.y * 0.9)
			for i in 5:
				var p = Vector2(3 + floor(f._noise(c, i) * 17.0), 3 + floor(f._noise(c, i + 9) * 17.0))
				var horizontal = f._noise(c, i + 20) > 0.5
				var length: float = 3.0 + floor(f._noise(c, i + 30) * 5.0)
				var size = Vector2(length, 1) if horizontal else Vector2(1, length)
				draw_rect(Rect2(o + p, size), Color(LF.COL_HOT, 0.35 + 0.65 * pulse))
				draw_rect(Rect2(o + p, Vector2(1, 1)), Color(LF.COL_CORE, pulse))

		for c in vis:
			var fl = f._fill_of(c)
			if fl <= 0.02 or not f._FieldUtil.seen(f.map, c):
				continue
			var o = f._cell_origin(c)
			var sh: Dictionary = f._lava_shape(c)
			var above_has: bool = sh["above_has"]
			if sh["stream"]:
				draw_stream_old(c, o)
				continue
			var h: float = sh["rect"].size.y
			var top: float = LF.TILE - h
			# A thin film with nothing under it is cooling away (#41): it dulls from
			# bright to a dark crust as it goes.
			var warm: float = 1.0
			if fl < LF.FILM_MASS and not above_has and f.shown.get(c + Vector2i.DOWN, 0.0) < LF.LavaData.HOLDS_MASS:
				warm = clampf(fl / LF.FILM_MASS, 0.0, 1.0)
			draw_rect(Rect2(o + Vector2(0, top), Vector2(LF.TILE, h)), LF.COL_CRUST.lerp(LF.COL_BODY, warm))
			# Darker toward the bottom of a deep pool.
			if h > 10:
				draw_rect(Rect2(o + Vector2(0, LF.TILE - floor(h * 0.35)), Vector2(LF.TILE, floor(h * 0.35))), LF.COL_DEEP)
			# Slow drifting crust plates and hot veins.
			for i in 4:
				var px: float = floor(fposmod(f._noise(c, i) * LF.TILE + f._time * (2.0 + 3.0 * f._noise(c, i + 5)), LF.TILE - 4.0))
				var py: float = top + 3.0 + floor(f._noise(c, i + 11) * max(1.0, h - 6.0))
				if py + 2.0 > LF.TILE:
					continue
				var hot = i % 2 == 0
				draw_rect(Rect2(o + Vector2(px, py), Vector2(4 if hot else 3, 1 if hot else 2)), LF.COL_HOT if hot else LF.COL_CRUST)
			if not above_has:
				# Bright rippling surface.
				for x in range(0, int(LF.TILE), 2):
					var ripple: float = round(sin(f._time * 4.0 + (c.x * LF.TILE + x) * 0.35))
					draw_rect(Rect2(o + Vector2(x, top + max(0.0, ripple)), Vector2(2, 2)), LF.COL_DEEP.lerp(LF.COL_CORE, warm))
				draw_rect(Rect2(o + Vector2(0, top + 2), Vector2(LF.TILE, 1)), LF.COL_CRUST.lerp(LF.COL_HOT, warm))
				# Embers that pop off the surface.
				for i in (2 if warm > 0.6 else 0):
					var t: float = fposmod(f._time * (0.5 + f._noise(c, i + 40)) + f._noise(c, i + 50), 1.0)
					var ex: float = floor(f._noise(c, i + 60 + int(f._time * 0.5)) * (LF.TILE - 1.0))
					draw_rect(Rect2(o + Vector2(ex, top - t * 14.0), Vector2(1, 1)), Color(LF.COL_CORE, 1.0 - t))

		# Steam where water just hardened lava: a white-grey flash that fades.
		for e in f._steam:
			var a: float = clampf(e[1] / LF.LavaData.STEAM_SECONDS, 0.0, 1.0)
			var o = f._cell_origin(e[0])
			draw_rect(Rect2(o - Vector2(3, 6 + (1.0 - a) * 10.0), Vector2(LF.TILE + 6, LF.TILE + 6)), Color(0.92, 0.92, 0.95, 0.45 * a))
		draw_puffs_old()
		draw_barrier_old()
		draw_heat_bar_old()
		if f.debug_boxes:
			var k = f._Story.local_keeper()
			if k != null and is_instance_valid(k):
				var r = f._FieldUtil.keeper_rect(k)
				draw_rect(Rect2(to_local(r.position), r.size), Color(0.3, 1.0, 0.4, 0.9), false, 1.0)


	# A pouring stream (#135): a ribbon of 2 px slices along stream_edges(), so it
	# runs on unbroken from cell to cell (#122). It starts at the surface of the
	# lava it pours from, with a rounded shoulder; runs on down to the lava it
	# lands on, where it spreads into a foot and throws sparks; and ends in a
	# rounded tip while it is still falling through empty space.


	func draw_stream_old(c: Vector2i, o: Vector2) -> void:
		var p: Array = f._stream_params(c)
		var a: float = p[0]
		var top: float = p[3]
		var end: int = p[5]
		var bottom: float = LF.TILE + p[4]
		var y: float = top
		var last_mid: float = LF.TILE * 0.5
		while y < bottom:
			var hgt: float = minf(LF.STREAM_SLICE, bottom - y)
			var e: Vector2 = f._edges(p, c, (y + hgt * 0.5) / LF.TILE, true)
			var w: float = e.y - e.x
			# Rounded ends.
			var k: float = 1.0
			if top > 0.0 and y - top < 6.0:
				k = sqrt(1.0 - pow(1.0 - (y - top + 2.0) / 8.0, 2.0))
			elif p[6] and y < 8.0:
				k = (y + 2.0) / 10.0
			if end == 2 and y >= LF.TILE - 6.0:
				k *= sqrt(maxf(0.0, 1.0 - pow((y + hgt - (LF.TILE - 6.0)) / 6.5, 2.0)))
			if k < 1.0:
				var nw: float = round(w * k)
				if a < 0.0:
					e.y = e.x + nw
				elif a > 0.0:
					e.x = e.y - nw
				else:
					e.x = round((e.x + e.y - nw) * 0.5)
					e.y = e.x + nw
			# The foot: the last few px spread out over the lava it lands on.
			if end == 1 and w > 0.0 and bottom - y <= 4.0:
				var spread: float = 1.0 if bottom - y > 2.0 else 2.0
				if a <= 0.0:
					e.y = minf(LF.TILE, e.y + spread)
				if a >= 0.0:
					e.x = maxf(0.0, e.x - spread)
			w = e.y - e.x
			if w >= 1.0:
				last_mid = (e.x + e.y) * 0.5
				draw_rect(Rect2(o + Vector2(e.x, y), Vector2(w, hgt)), LF.COL_BODY)
				if w > 2.0:
					# The dark rim is on the stream's free sides only.
					var l: float = e.x + (0.0 if a < 0.0 else 1.0)
					var r: float = e.y - (0.0 if a > 0.0 else 1.0)
					draw_rect(Rect2(o + Vector2(l, y), Vector2(r - l, hgt)), LF.COL_HOT)
					if w > 5.0:
						var cw: float = maxf(2.0, round(w * 0.3))
						draw_rect(Rect2(o + Vector2(round((l + r - cw) * 0.5), y), Vector2(cw, hgt)), LF.COL_CORE)
			y += LF.STREAM_SLICE
		if end == 1:
			# Sparks thrown up where the stream lands.
			for i in 3:
				var ph: float = f._time * (1.3 + f._noise(c, i + 70)) + f._noise(c, i + 75)
				var t: float = fposmod(ph, 1.0)
				var dx: float = (f._noise(c, i + 80 + int(ph)) - 0.5) * 22.0 * t
				draw_rect(Rect2(o + Vector2(round(last_mid + dx), round(bottom - 1.0 - 28.0 * t * (1.0 - t))), Vector2(1, 1)), Color(LF.COL_CORE, 1.0 - t * t))


	func draw_puffs_old() -> void:
		for q in f._puffs:
			var age: float = f._time - q[2]
			var t: float = age / q[3]
			if t < 0.0 or t >= 1.0:
				continue
			var s: float = q[4]
			var x: float = round(q[0] + sin(age * 2.6 + s * TAU) * (1.0 + 3.0 * t) + (s - 0.5) * 8.0 * t)
			var y: float = round(q[1] - (20.0 + 12.0 * s) * (1.0 - (1.0 - t) * (1.0 - t)))
			var col = Color(LF.COL_STEAM_LIT.lerp(LF.COL_STEAM, minf(1.0, t * 2.5)), 0.42 * pow(1.0 - t, 1.3) * minf(1.0, age * 10.0))
			var r: float = 1.0 + floor(t * 2.6 + s * 0.9)
			# A soft round puff: stacked bars, so its middle is denser than its rim.
			draw_rect(Rect2(x - r, y - 1.0, r * 2.0, 2.0), col)
			if r > 1.0:
				draw_rect(Rect2(x - r + 1.0, y - r + 1.0, r * 2.0 - 2.0, r * 2.0 - 2.0), col)
				draw_rect(Rect2(x - 1.0, y - r, 2.0, r * 2.0), col)


	func draw_barrier_old() -> void:
		for x in f.barrier_columns():
			var cell = Vector2i(x, f._chamber.position.y)
			if not (f._FieldUtil.seen(f.map, cell) or f._FieldUtil.seen(f.map, cell + Vector2i.UP)):
				continue
			var o = f._cell_origin(cell)
			var pulse: float = 0.75 + 0.25 * sin(f._time * 3.2 + x * 0.6)
			# Haze above and below the membrane.
			draw_rect(Rect2(o + Vector2(0, -6), Vector2(LF.TILE, 14)), Color(LF.COL_BARRIER_MID, 0.16 * pulse))
			draw_rect(Rect2(o + Vector2(0, -4), Vector2(LF.TILE, 10)), Color(LF.COL_BARRIER_MID, 0.16 * pulse))
			# The membrane: a deep band with a bright core line.
			draw_rect(Rect2(o + Vector2(0, -3), Vector2(LF.TILE, 6)), Color(LF.COL_BARRIER_DEEP, 0.92))
			draw_rect(Rect2(o + Vector2(0, -2), Vector2(LF.TILE, 3)), Color(LF.COL_BARRIER_MID, pulse))
			# A light ripple running along it, and sparks drifting across.
			for px in range(0, int(LF.TILE), 2):
				var w: float = sin(f._time * 5.0 + (x * LF.TILE + px) * 0.45)
				if w > 0.55:
					draw_rect(Rect2(o + Vector2(px, -1 + round(w)), Vector2(2, 1)), Color(LF.COL_BARRIER_LIGHT, pulse))
			for i in 2:
				var sx: float = fposmod(f._time * (9.0 + 5.0 * f._noise(cell, i)) + f._noise(cell, i + 7) * LF.TILE, LF.TILE)
				draw_rect(Rect2(o + Vector2(floor(sx), -1), Vector2(1, 1)), LF.COL_BARRIER_SPARK)


	func draw_heat_bar_old() -> void:
		# A bar over each local keeper (#231): f.shown whenever there is heat, and
		# while passive heat is building.
		for keeper in f._Story.local_keepers():
			var h: float = f.heat_of(keeper)
			if h <= 0.5 and f.passive_rate_of(keeper) <= 0.0:
				continue
			var frac: float = h / LF.HEAT_MAX
			f._FieldUtil.draw_bar(self, (to_local(keeper.global_position) + Vector2(-9, -20)).round(), frac,
				LF.COL_CORE.lerp(Color("ff2a1a"), frac), frac > 0.7 and fposmod(f._time * 8.0, 1.0) < 0.5)


	func draw_glow_old(glow: CanvasItem) -> void:
		# Soft additive light around lava and around f.magma rock the player can see.
		for c in f._visible_cells():
			var fl = f._fill_of(c)
			if fl <= 0.05 or not f._FieldUtil.seen(f.map, c):
				continue
			var center = f._cell_origin(c) + Vector2(LF.TILE, LF.TILE) * 0.5
			var flick: float = 0.85 + 0.15 * sin(f._time * 6.0 + c.x * 2.1 + c.y)
			var r: float = 30.0 + 18.0 * fl
			glow.draw_texture_rect(f._glow_tex, Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1, 1, 1, 0.22 * flick * (0.4 + 0.6 * fl)))
		for c in f.magma:
			if f._in_boxes(c) and f.map.tiles.has(Vector2(c)):
				var center = f._cell_origin(c) + Vector2(LF.TILE, LF.TILE) * 0.5
				var pulse: float = 0.5 + 0.5 * sin(f._time * 3.0 + c.x * 1.7 + c.y * 0.9)
				glow.draw_texture_rect(f._glow_tex, Rect2(center - Vector2(22, 22), Vector2(44, 44)), false, Color(1, 1, 1, 0.10 + 0.14 * pulse))
		# The chamber barrier's violet glow.
		for x in f.barrier_columns():
			var cell = Vector2i(x, f._chamber.position.y)
			if not (f._FieldUtil.seen(f.map, cell) or f._FieldUtil.seen(f.map, cell + Vector2i.UP)):
				continue
			var p = f._cell_origin(cell) + Vector2(LF.TILE * 0.5, 0)
			var pulse: float = 0.75 + 0.25 * sin(f._time * 3.2 + x * 0.6)
			glow.draw_texture_rect(f._barrier_glow_tex, Rect2(p - Vector2(30, 24), Vector2(60, 48)), false, Color(1, 1, 1, 0.55 * pulse))



class LegacyGas extends Node2D:
	var f

	func _draw() -> void:
		# Gas f.rock the player can see: green seeping cracks that breathe.
		for c in f.rock:
			if not f.map.tiles.has(Vector2(c)):
				continue
			var o = f._cell_origin(c)
			var pulse: float = 0.5 + 0.5 * sin(f._time * 2.2 + c.x * 1.3 + c.y * 0.7)
			for i in 5:
				var p = Vector2(3 + floor(f._noise(c, i) * 17.0), 3 + floor(f._noise(c, i + 9) * 17.0))
				var horizontal = f._noise(c, i + 20) > 0.5
				var length: float = 3.0 + floor(f._noise(c, i + 30) * 5.0)
				var size = Vector2(length, 1) if horizontal else Vector2(1, length)
				draw_rect(Rect2(o + p, size), Color(GF.COL_ROCK_SEEP, 0.3 + 0.6 * pulse))
				draw_rect(Rect2(o + p, Vector2(1, 1)), Color(GF.COL_ROCK_CORE, pulse))
		draw_puffs_old()


	# Fallback look, a flat tint by density, when there is no GasLook (headless runs).

	func draw_puffs_old() -> void:
		for q in f._puffs:
			var age: float = f._time - q[2]
			var t: float = age / q[3]
			if t < 0.0 or t >= 1.0:
				continue
			var s: float = q[4]
			var x: float = round(q[0] + sin(age * 2.2 + s * TAU) * (1.0 + 5.0 * t) + (s - 0.5) * 14.0 * t)
			var y: float = round(q[1] - q[5] * (1.0 - (1.0 - t) * (1.0 - t)))
			var col: Color
			if q[7] == GF.EMBER:
				col = Color(GF.COL_EMBER.lerp(GF.COL_EMBER_OUT, minf(1.0, t * 1.6)), 1.0 - t * t)
			else:
				col = Color(GF.COL_PUFF_LIT.lerp(GF.COL_PUFF, minf(1.0, t * 2.0)), 0.6 * pow(1.0 - t, 1.2) * minf(1.0, age * 12.0))
			var r: float = floor(q[6] * (0.6 + 1.2 * t))
			if r < 1.0:
				draw_rect(Rect2(x, y, 1.0, 1.0), col)
				continue
			draw_rect(Rect2(x - r, y - 1.0, r * 2.0, 2.0), col)
			if r > 1.0:
				draw_rect(Rect2(x - r + 1.0, y - r + 1.0, r * 2.0 - 2.0, r * 2.0 - 2.0), col)
				draw_rect(Rect2(x - 1.0, y - r, 2.0, r * 2.0), col)

