extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 203: the gas's look. A pocket of gas rock is breached; the gas jets
# out, climbs the shaft, mushrooms into the room and rolls under its ceiling.
# The keeper flies through it; the camera jumps. Frame bursts for the eye.
#
#   ...##...........      an alcove in the ceiling (a trap)   y -1
#   ................      the room                            y 0..2
#   ########.#######      the shaft                           y 3..5
#   #GGG####.#######      G gas rock (the pocket)             y 4..5
#   #GGG.....#######

const TIMEOUT := 300

var OX := 0
var OY := 30
var td
var field
var look


func boot() -> Dictionary:
	return {"seed": 12345}


func _c(x: int, y: int) -> Vector2i:
	return Vector2i(OX + x, OY + y)


func _fits(ox: int, oy: int) -> bool:
	for y in range(oy - 3, oy + 8):
		for x in range(ox - 2, ox + 18):
			var c := Vector2i(x, y)
			if td.get_biomev(c) < 0 or td.get_resourcev(c) == Data.TILE_EMPTY or td.get_resourcev(c) == Data.TILE_BORDER or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE:
				return false
	return true


func _frame_ms(h, frames: int) -> float:
	var t0 := Time.get_ticks_usec()
	await h.frames(frames)
	return float(Time.get_ticks_usec() - t0) / 1000.0 / frames


func run(h) -> void:
	h.disable_waves()
	td = Level.map.tileData
	await h.until(func(): return Level.map.get_node_or_null("StoryGasField") != null, 10.0)
	field = Level.map.get_node("StoryGasField")
	look = field.look
	h.check("the gas field has its look", look != null)
	var lava = Level.map.get_node("StoryLavaField")
	lava.magma.clear()
	lava.mass.clear()
	lava.shown.clear()
	field.rock.clear()
	field.mass.clear()
	var found := false
	for oy in range(20, 110):
		for ox in range(-40, 30):
			if not found and _fits(ox, oy):
				OX = ox
				OY = oy
				found = true
	h.check("found solid rock for the cavern", found, [OX, OY])
	var around: Array = []
	for y in range(-3, 8):
		for x in range(-2, 18):
			around.append(_c(x, y))
			td.set_resourcev(_c(x, y), Data.TILE_DIRT_START)
	await h.reveal(around)
	var open: Array = [_c(3, -1), _c(4, -1)]
	for x in 16:
		for y in 3:
			open.append(_c(x, y))
	for y in range(3, 6):
		open.append(_c(8, y))
	for x in range(4, 8):
		open.append(_c(x, 5))
	await h.clear_tiles(open)
	var pocket: Array = []
	for x in range(1, 4):
		for y in range(4, 6):
			pocket.append(_c(x, y))
	field.add_pocket(pocket)
	await h.teleport_tile(_c(10, 2))
	h.keeper().set("gravity_scale", 0.0)
	h.snap_camera()
	await h.wait(3.0)
	h.snap_camera()
	var fmt: int = look._vel_a.get_texture().get_image().get_format()
	h.check("the fields are float", fmt == Image.FORMAT_RGBAH or fmt == Image.FORMAT_RGBAF, fmt)
	var idle_ms: float = await _frame_ms(h, 120)
	var idle_cpu: float = float(look.cpu_us) / 1000.0 / maxi(look.cpu_frames, 1)
	var idle_rebuilds: int = look.rebuilds
	await h.frames(60)
	h.check("no gas, nothing moving: the tile texture is left alone", look.rebuilds == idle_rebuilds, [idle_rebuilds, look.rebuilds])
	await h.teleport_tile(_c(6, 5))
	h.keeper().set("gravity_scale", 0.0)
	await h.wait(1.5)
	await h.burst("sealed", 6, 12)
	h.check("wisps seep from the gas rock", field._puffs.size() > 0, field._puffs.size())
	await h.teleport_tile(_c(10, 2))
	h.keeper().set("gravity_scale", 0.0)
	await h.wait(0.5)

	# ---- 1. the breach
	Level.map.destroyTile("team1", "", Level.map.getTile(Vector2(_c(3, 5))))
	await h.burst("breach", 30, 4)
	await h.burst("climb", 24, 8)
	await h.wait(3.0)
	await h.burst("settling", 16, 10)
	await h.until(func(): return field.stats()["awake"] == 0, 40.0)
	await h.wait(2.0)
	await h.burst("trapped", 16, 10)
	h.check("gas is drawn thick where the grid is full (the alcove)", look.dye_at(_c(3, -1)) > 0.7 and field.mass.get(_c(3, -1), 0.0) > 0.95, [look.dye_at(_c(3, -1)), field.mass.get(_c(3, -1), 0.0)])
	h.check("no gas is drawn where the grid has none", look.dye_at(_c(12, 2)) < 0.12, look.dye_at(_c(12, 2)))

	# ---- 2. the keeper flies through it
	await h.teleport_tile(_c(14, 0))
	h.keeper().set("gravity_scale", 0.0)
	await h.wait(0.5)
	h.down("ui_left")
	await h.burst("wake", 30, 5)
	h.up("ui_left")
	await h.burst("after_wake", 8, 10)
	var gas_ms: float = await _frame_ms(h, 120)

	# ---- 3. the camera jumps: the gas stays where it is in the world
	await h.teleport_tile(_c(9, 1))
	h.keeper().set("gravity_scale", 0.0)
	await h.wait(1.0)
	var cell: Vector2i = _c(3, -1)
	var before: float = look.dye_at(cell)
	var c0_before: Vector2i = look.c0
	await h.teleport_tile(_c(4, 1))
	h.keeper().set("gravity_scale", 0.0)
	await h.frames(4)
	var after: float = look.dye_at(cell)
	h.check("the window moved with the camera", look.c0 != c0_before, [c0_before, look.c0])
	h.check("the gas stayed put in the world", before > 0.5 and absf(after - before) < 0.25, [before, after])

	h.note("cost", {"frame_ms_idle": idle_ms, "frame_ms_gas": gas_ms, "look_cpu_ms_idle": idle_cpu,
		"look_cpu_ms_overall": float(look.cpu_us) / 1000.0 / maxi(look.cpu_frames, 1), "fps": Engine.get_frames_per_second()})
	look.debug_view(1)
	await h.shot("raw_field")
	look.debug_view(2)
	await h.shot("raw_velocity")
	look.debug_view(0)

	# ---- 4. the surface: a plume over the shaft mouth while gas leaves the mine
	var GasSfx = load("res://mods-unpacked/cejdan-StoryMode/gas/gas_sfx.gd")
	h.check("the burst hissed", int(GasSfx.played.get("burst", 0)) >= 1, GasSfx.played)
	var col := -999
	for x in range(-4, 9):
		if col == -999 and field._is_sky(Vector2i(x, -1)) and not Level.map.is_tile_empty(Vector2i(x, 0)) and td.get_hardnessv(Vector2i(x, 3)) < Data.HARDNESS_INDESTRUCTIBLE:
			col = x
	h.check("found a column under open sky", col != -999, col)
	var shaft: Array = []
	for y in 5:
		shaft.append(Vector2i(col, y))
	for x in range(col - 2, col + 3):
		shaft.append(Vector2i(x, 4))
	await h.reveal(shaft)
	await h.clear_tiles(shaft)
	await h.teleport_tile(Vector2i(col + 2, 4))
	await h.wait(0.3)
	await h.teleport_tile(Vector2i(col, 1))
	h.keeper().set("gravity_scale", 0.0)
	await h.wait(1.0)
	field.fill([Vector2i(col - 2, 4), Vector2i(col - 1, 4), Vector2i(col, 4), Vector2i(col + 1, 4)], 3.0)
	await h.burst("plume", 20, 6)
	# The gas climbs at 4 tiles a second (#211): give it time to reach the surface.
	await h.until(func(): return field.vented > 5.0, 10.0)
	h.check("gas left through the surface", field.vented > 5.0, field.vented)
	h.check("the vent sounded", int(GasSfx.played.get("vent", 0)) >= 1, GasSfx.played)
