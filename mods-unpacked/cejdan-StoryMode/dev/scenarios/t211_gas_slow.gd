extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 211: a slow, lingering cloud. Gas let out at the foot of a tall shaft
# climbs it as a cloud, at about 4 tiles a second (a keeper with Jetpack
# Speed II, 3.9 tiles/s, about keeps pace; III outruns it), with no thin wisps
# racing ahead and nothing lost on the way. A room
# of burning gas stays alight about 3.5x as long as before. Dense gas fills
# the toxin bar in about 3.3 s (was 2 s).
#
#   .#K      the shaft (x 0), a wall (x 1), the keeper's own column (x 2)
#   .#.      y 0..SHAFT-1; the gas starts in the bottom three cells
#   ...      a room at the bottom joins the two (y SHAFT..SHAFT+2), for the fire

const GasData = preload("res://mods-unpacked/cejdan-StoryMode/data/gas.gd")
const TIMEOUT := 240
const SHAFT := 28

var OX := 0
var OY := 30
var td
var field
var lava


func boot() -> Dictionary:
	return {"seed": 12345}


func _c(x: int, y: int) -> Vector2i:
	return Vector2i(OX + x, OY + y)


func _fits(ox: int, oy: int) -> bool:
	for y in range(oy - 2, oy + SHAFT + 5):
		for x in range(ox - 2, ox + 10):
			var c := Vector2i(x, y)
			if td.get_biomev(c) < 0 or td.get_resourcev(c) == Data.TILE_EMPTY or td.get_resourcev(c) == Data.TILE_BORDER or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE:
				return false
	return true


# The highest shaft row holding toxic gas, and the gas's centre of mass (rows).
func _front() -> Array:
	var top := 999
	var sum := 0.0
	var wy := 0.0
	for y in range(0, SHAFT + 3):
		var m: float = field.mass.get(_c(0, y), 0.0)
		if m >= GasData.TOXIC_MASS and y < top:
			top = y
		sum += m
		wy += m * y
	return [top, wy / maxf(sum, 0.0001), sum]


func _any_gas_above(y: int) -> float:
	var s := 0.0
	for yy in range(0, y):
		s += field.mass.get(_c(0, yy), 0.0)
	return s


func run(h) -> void:
	h.disable_waves()
	td = Level.map.tileData
	await h.until(func(): return Level.map.get_node_or_null("StoryGasField") != null, 10.0)
	field = Level.map.get_node("StoryGasField")
	lava = Level.map.get_node("StoryLavaField")
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
	h.check("found solid rock for the shaft", found, [OX, OY])
	var around: Array = []
	for y in range(-2, SHAFT + 5):
		for x in range(-2, 10):
			around.append(_c(x, y))
			td.set_resourcev(_c(x, y), Data.TILE_DIRT_START)
	await h.reveal(around)
	var open: Array = []
	for y in SHAFT:
		open.append(_c(0, y))
		open.append(_c(2, y))
	for y in range(SHAFT, SHAFT + 3):
		for x in 8:
			open.append(_c(x, y))
	await h.clear_tiles(open)
	# The depth's own heat would recall the keeper (this deep) before the end.
	var cool := func(): lava.heat = 0.0
	Level.map.get_tree().process_frame.connect(cool)
	await h.teleport_tile(_c(2, SHAFT - 6))
	h.keeper().set("gravity_scale", 0.0)
	h.snap_camera()
	await h.wait(1.0)

	# ---- 1. the climb: three cells of dense gas at the shaft's foot
	field.fill([_c(0, SHAFT - 1), _c(0, SHAFT - 2), _c(0, SHAFT - 3)], 1.0)
	var start: float = h.now()
	var c0: float = _front()[1]
	var samples: Array = []
	var reached := -1.0
	var shot_rows := [SHAFT - 6, SHAFT - 14, SHAFT - 22, 4]
	var next_shot := 0
	while h.now() - start < 20.0:
		await h.wait(0.25)
		var f: Array = _front()
		var t: float = h.now() - start
		samples.append([snappedf(t, 0.01), f[0], snappedf(f[1], 0.01), snappedf(_any_gas_above(maxi(int(f[0]) - 3, 0)), 0.001)])
		if next_shot < shot_rows.size() and f[0] <= shot_rows[next_shot] + 2:
			await h.teleport_tile(_c(2, shot_rows[next_shot]))
			h.keeper().set("gravity_scale", 0.0)
			h.snap_camera()
			await h.shot("climb_%d" % next_shot)
			if next_shot == 1:
				await h.burst("glide", 10, 3)
			next_shot += 1
		if reached < 0.0 and f[0] <= 1:
			reached = t
		if reached > 0.0 and t > reached + 2.0:
			break
	h.note("climb samples [s, toxic front row, centre row, gas more than 3 rows above the front]", samples)
	# Speed of the centre of mass over the middle of the climb (the shaft's top
	# stops it).
	var t_a := -1.0
	var y_a := 0.0
	var t_b := -1.0
	var y_b := 0.0
	for s in samples:
		if t_a < 0.0 and s[2] <= SHAFT - 6:
			t_a = s[0]
			y_a = s[2]
		if t_b < 0.0 and s[2] <= 8:
			t_b = s[0]
			y_b = s[2]
	var speed: float = (y_a - y_b) / maxf(t_b - t_a, 0.01)
	# The leading edge (toxic gas) between the same rows.
	var f_a := -1.0
	var f_b := -1.0
	for s in samples:
		if f_a < 0.0 and s[1] <= SHAFT - 6:
			f_a = s[0]
		if f_b < 0.0 and s[1] <= 6:
			f_b = s[0]
	var front: float = float(SHAFT - 12) / maxf(f_b - f_a, 0.01)
	h.note("cloud speed, tiles a second", {"body": speed, "front": front, "from": [t_a, y_a], "to": [t_b, y_b], "keeper speeds (tiles/s)": [56 / 24.0, 74 / 24.0, 94 / 24.0, 116 / 24.0, 140 / 24.0]})
	h.check("the cloud's body climbs at 3.0-4.4 tiles a second: Jetpack Speed II (3.9) about keeps pace", speed > 3.0 and speed < 4.4, speed)
	h.check("its leading edge climbs at 3.5-4.5 tiles a second: Speed III (4.8) outruns it", front > 3.5 and front < 4.5, front)
	h.check("it took more than 5 s to climb the shaft", reached > 5.0, reached)
	var wisps := 0.0
	for s in samples:
		wisps = maxf(wisps, s[3])
	h.check("no thin wisps race far ahead of the cloud", wisps < 0.15, wisps)
	h.check("the gas is all there: little of it faded on the way", field.faded < 0.3 and absf(field.total() + field.vented + field.faded - 3.0) < 0.01, field.stats())

	# ---- 2. fire: the room at the foot, full of gas, lit at one end
	field.mass.clear()
	field.wake_all()
	await h.teleport_tile(_c(2, SHAFT - 3))
	h.keeper().set("gravity_scale", 0.0)
	h.snap_camera()
	var room: Array = []
	for y in range(SHAFT, SHAFT + 3):
		for x in range(3, 8):
			room.append(_c(x, y))
	field.freeze_flow = true
	field.fill(room, 1.0)
	await h.wait(0.3)
	var lit_at: float = h.now()
	field.ignite(_c(7, SHAFT + 2))
	await h.wait(1.2)
	await h.shot("fire_1s")
	await h.wait(1.3)
	await h.shot("fire_2_5s")
	var out: bool = await h.until(func(): return field.fire.is_empty(), 20.0)
	var dur: float = h.now() - lit_at
	field.freeze_flow = false
	h.note("fire in a 5 x 3 room of dense gas, seconds", dur)
	# Before #211 (burn 4.0/s, ember 0.4 s, spread 0.06 s): about 0.9 s here
	# (4 spreads of 0.06 s across the room, 0.25 s burning, 0.4 s of embers).
	h.check("the room burned out", out)
	h.check("the fire lasted 2.7-4.5 s (3-4x the 0.9 s it took before)", dur > 2.7 and dur < 4.5, dur)
	h.keeper().set("gravity_scale", 1.0)

	# ---- 3. toxin: dense gas around the keeper
	field.mass.clear()
	field.fire.clear()
	field.toxin = 0.0
	await h.teleport_tile(_c(4, SHAFT + 2))
	await h.wait(0.5)
	var kc: Vector2i = h.keeper_tile()
	var cells: Array = []
	for ox in range(-1, 2):
		for oy in range(-1, 2):
			if Level.map.is_tile_empty(kc + Vector2i(ox, oy)):
				cells.append(kc + Vector2i(ox, oy))
	field.freeze_flow = true
	field.fill(cells, 1.2)
	var t0: float = h.now()
	var full: bool = await h.until(func(): return field.toxin >= 99.0 or field.gassed > 0, 10.0)
	var fill_t: float = h.now() - t0
	field.freeze_flow = false
	h.note("dense gas: seconds to a full toxin bar", fill_t)
	h.check("dense gas fills the bar in 2.8-3.9 s (was 2 s)", full and fill_t > 2.8 and fill_t < 3.9, fill_t)
