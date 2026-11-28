extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #369: the rising lava through real dug tunnels (huge map, seed 12345, the
# Engineer with the boss gear). The chains are broken quietly (`free`), a
# winding way up is dug from the ocean's ceiling to the dome (three shafts
# joined by short jogs, a side tunnel off each of the lower two, a gas-free
# dip at the end of one), then the rise starts at the ocean (dev_start, the
# path t369_live checks from the cutscene). Checks and shots on the way up:
#   the ocean's air rows fill first, flat across the cavern; the level rises
#   at the set speed (and eases in); the band stays a thin strip of real cells
#   (no more cells stored however deep the flood gets: the cells under it are
#   implied); rock stays rock (no lava in any tile); the keeper below the line
#   is in lava; a side tunnel fills when the line reaches it, its dip first;
#   the warning grows as the line comes closer below the keeper (closeness
#   and the camera's shake); the keeper flies up its shaft with the lava close
#   behind (bursts). Saves slot 69 mid-rise (t369_reload).

const RisingLava = preload("res://mods-unpacked/flantor-StoryMode/endgame/rising_lava.gd")
static var _RisingLava = RisingLava  # calls go through this: lazy_preload makes const-preload calls slow
const EndGame = preload("res://mods-unpacked/flantor-StoryMode/endgame/end_game.gd")
static var _EndGame = EndGame  # calls go through this: lazy_preload makes const-preload calls slow
const Flood = preload("res://mods-unpacked/flantor-StoryMode/data/rising_lava.gd")
const TIMEOUT := 400
const SLOT := 69

var lava
var rise
var ocean: Dictionary
var ceiling: int = 0
var top: int = 0


func boot() -> Dictionary:
	return {"seed": 12345, "free": true}


# --- shared with the other t369_* scenarios ---------------------------------------

func setup(h, gear: bool = true) -> bool:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	var ok: bool = await h.until(func(): return _RisingLava.find() != null and h.keeper() != null, 30.0)
	if not h.check("the run has the rising lava", ok):
		return false
	await h.wait(1.0)
	rise = _RisingLava.find()
	lava = Level.map.get_node("StoryLavaField")
	ocean = Level.map.tileData.get_meta("story_ocean")
	ceiling = int(ocean["ceiling"])
	top = int(ocean["top"])
	h.disable_waves()
	if gear and not Network.is_client():
		load("res://mods-unpacked/flantor-StoryMode/dev/boss_dev.gd").give_gear()
	return true


func cool(h) -> void:
	if lava != null:
		for k in h.local_keepers():
			lava.set_heat_of(k, 0.0)


# The way up: [rect top-left, bottom-right] in dig order, bottom first.
const ROUTE := [
	[Vector2i(3, 98), Vector2i(4, 151)],      # shaft A, through the ocean's ceiling
	[Vector2i(-12, 128), Vector2i(2, 129)],   # side tunnel S1 off A, to the left ...
	[Vector2i(-12, 130), Vector2i(-10, 131)], # ... with a dip at its end
	[Vector2i(3, 98), Vector2i(12, 99)],      # jog to shaft B
	[Vector2i(11, 48), Vector2i(12, 99)],     # shaft B
	[Vector2i(13, 70), Vector2i(26, 71)],     # side tunnel S2 off B, to the right
	[Vector2i(0, 48), Vector2i(12, 49)],      # jog to shaft C
	[Vector2i(0, 0), Vector2i(1, 49)],        # shaft C, up to the dome
]


func dig_route(h) -> void:
	for r in ROUTE:
		await dig_clean(h, r[0], r[1])
	clear_pocket_lava()
	await h.wait(0.5)


# The lava of pools and pockets the digging opened (it would pour into the
# shafts and blur what the flood line does): gone, the ocean's kept.
func clear_pocket_lava() -> void:
	for c: Vector2i in lava.mass.keys():
		if c.y < ceiling:
			lava.mass.erase(c)
	for c: Vector2i in lava.sources.keys():
		if c.y < ceiling:
			lava.sources.erase(c)
	lava.wake_all()


# dig_room without the magma pockets' lava (a pocket in the way would pour
# into the shafts) and with the gas held harmless.
func dig_clean(h, a: Vector2i, b: Vector2i) -> void:
	for y in range(a.y - 1, b.y + 2):
		for x in range(a.x - 1, b.x + 2):
			lava.magma.erase(Vector2i(x, y))
	var gas = Level.map.get_node_or_null("StoryGasField")
	if gas != null:
		gas.freeze_toxin = true
	await h.dig_room(a, b)
	clear_pocket_lava()


func row_y(r: float) -> float:
	return Level.map.getTilePos(Vector2(0, 0)).y - 12.0 + r * 24.0


# Rows from the keeper down to the lava's surface (negative: under it).
func rows_below(k) -> float:
	return (lava.flood_y() - k.global_position.y) / 24.0


func wait_until_below(h, k, rows: float, timeout: float = 60.0) -> bool:
	return await h.until(func():
		cool(h)
		return lava.flood_active() and rows_below(k) <= rows, timeout)


# No lava in any tile (rock stays rock), over the rows the flood has passed.
func lava_in_rock() -> Array:
	var out: Array = []
	for c: Vector2i in lava.mass:
		if not Level.map.is_tile_empty(c):
			out.append(c)
	return out


func place(h, k, cell: Vector2i) -> void:
	await h.teleport_tile(cell, k)
	await h.wait(0.3)


# --- the run ----------------------------------------------------------------------

func run(h) -> void:
	if not await setup(h):
		return
	var k = h.keeper()
	h.check("free, nothing rising yet (a dev route rises only when asked)", _EndGame.is_free() and _RisingLava.state() == "" and not lava.flood_active(), [_EndGame.state(), _RisingLava.state()])
	await dig_route(h)
	# The keeper in shaft A, just over the ocean's ceiling.
	await place(h, k, Vector2i(3, ceiling - 3))
	var cells0: int = lava.mass.size()
	rise.dev_start()
	await h.frames(2)
	h.check("the rise starts at the ocean's surface", _RisingLava.state() == "rising" and lava.flood_active() and absf(rise.row - float(top)) < 0.2, [_RisingLava.state(), rise.row, top])
	var r0: float = rise.row
	var t0: float = h.now()
	await h.wait(2.0)
	var eased: float = (r0 - rise.row) / 2.0
	h.note("the first 2 s (eases in)", {"rows": r0 - rise.row, "rows_per_s": eased})
	h.check("it eases in (slower than full speed at first)", eased > 0.1 and eased < Flood.RISE_PX_PER_S / 24.0 * 0.8, eased)
	# The ocean's air rows, filling flat across the cavern.
	var probe := Vector2i(-20, top - 1)
	h.check("the ocean's air row just over the lava is filling", lava.mass.get(probe, 0.0) > 0.2 or lava.flooded(probe), [lava.mass.get(probe, 0.0), lava.flood_stats()])
	k.teleport(Level.map.getTilePos(Vector2(3, ceiling + 2)))
	h.snap_camera(k)
	await h.wait(0.4)
	cool(h)
	await h.shot("ocean_air_rows_filling")
	await place(h, k, Vector2i(3, ceiling - 4))
	# Full speed, measured over 6 s.
	await h.wait(3.0)
	var ra: float = rise.row
	var ta: float = h.now()
	await h.wait(6.0)
	var full: float = (ra - rise.row) / (h.now() - ta) * 24.0
	h.note("full speed", {"px_per_s": full, "want": Flood.RISE_PX_PER_S})
	h.check("at full speed: %.0f px/s (want %.0f)" % [full, Flood.RISE_PX_PER_S], absf(full - Flood.RISE_PX_PER_S) < 4.0, full)
	h.check("the band: a thin strip of real cells (the ocean's own cells aside)", lava.flood_stats()["band_cells"] <= 3 * (Level.map.tileData.get_used_rect().size.x), lava.flood_stats())
	# The side tunnel S1 (rows 128-131) fills as the line gets there, the dip first.
	await place(h, k, Vector2i(1, 124))
	var keep_cool := func(): cool(h)
	await wait_until_below(h, k, 7.0, 60.0)
	h.check("the warning grows as it comes: closeness near 1 a few rows below", float(rise.closeness.get(k.playerId, 0.0)) > 0.85, rise.closeness)
	var cam = Level.viewports.getPlayerCam(k.playerId)
	h.check("and the camera shakes", cam.shake_strength > 0.0, cam.shake_strength)
	# Look along the side tunnel while it fills.
	cam.targetOffset = Vector2(-150, 60)
	h.snap_camera(k)
	await h.until(func():
		keep_cool.call()
		return rise.row < 131.0, 20.0)
	await h.wait(0.2)
	await h.shot("side_tunnel_dip_filling")
	var dip := Vector2i(-11, 131)
	h.check("the dip at the side tunnel's end fills first", lava.flooded(dip) or lava.mass.get(dip, 0.0) > 0.5, [lava.mass.get(dip, 0.0), rise.row])
	await h.until(func():
		keep_cool.call()
		return rise.row < 128.4, 20.0)
	await h.shot("side_tunnel_filling")
	await h.until(func():
		keep_cool.call()
		return rise.row < 127.5, 10.0)
	var tunnel_far := Vector2i(-12, 128)
	h.check("the whole side tunnel is lava once the line is over it", lava.flooded(tunnel_far) and lava.flooded(Vector2i(-5, 129)), [lava.flooded(tunnel_far), rise.row])
	await h.shot("side_tunnel_full")
	cam.targetOffset = Vector2.ZERO
	# Below the band the lava is implied: stored cells stay few.
	h.check("no lava in rock", lava_in_rock().is_empty(), lava_in_rock().slice(0, 8))
	var deep := Vector2i(3, 140)
	h.check("deep in shaft A: lava by the level, not stored", lava.flooded(deep) and not lava.mass.has(deep), [lava.flooded(deep), lava.mass.has(deep)])
	# Fleeing up shaft B with the lava close behind.
	await place(h, k, Vector2i(11, 96))
	await wait_until_below(h, k, 3.5, 60.0)
	await h.shot("lava_close_behind")
	h.down("ui_up")
	await h.burst("fleeing_up_shaft_b", 10, 6)
	h.up("ui_up")
	await h.wait(0.3)
	await h.shot("fled")
	h.check("it rises behind the fleeing keeper", rows_below(k) > 4.0, rows_below(k))
	# A keeper caught in it is in lava (the implied part too).
	k.teleport(Level.map.getTilePos(Vector2(3, int(ceil(rise.row)) + 5)))
	h.snap_camera(k)
	await h.frames(3)
	h.check("a keeper under the band is in lava (implied)", lava.keeper_in_lava(k), [rows_below(k), lava.flood_stats()])
	cool(h)
	await h.shot("keeper_under_the_line")
	await place(h, k, Vector2i(11, 60))
	# The side tunnel S2 (rows 70-71).
	await wait_until_below(h, k, 6.0, 60.0)
	cam.targetOffset = Vector2(160, 0)
	h.snap_camera(k)
	await h.until(func():
		keep_cool.call()
		return rise.row < 71.5, 20.0)
	await h.shot("side_tunnel_s2_filling")
	cam.targetOffset = Vector2.ZERO
	h.note("stored cells", {"before the flood": cells0, "now": lava.mass.size(), "flood": lava.flood_stats()})
	h.check("cells stored stay about the same however deep the flood (the ocean's own, plus a thin band)", lava.mass.size() <= cells0 + 60, [cells0, lava.mass.size()])
	h.check("no lava in rock", lava_in_rock().is_empty(), lava_in_rock().slice(0, 8))
	var row_at_save: float = rise.row
	SaveGame.saveGame("singleplayer", SLOT, true)
	h.check("saved mid-rise: the level in Data", Data.ofOr(RisingLava.STATE_KEY, "") == "rising" and absf(float(Data.ofOr(RisingLava.ROW_KEY, 0.0)) - row_at_save) < 0.2, [Data.ofOr(RisingLava.ROW_KEY, null), row_at_save])
	await h.wait(1.2)
	h.note("saved slot %d mid-rise" % SLOT, {"row": row_at_save, "state": _RisingLava.state(), "data": [Data.ofOr(RisingLava.ROW_KEY, null), Data.ofOr(RisingLava.STATE_KEY, null)]})
	# The view from higher up: the mine under it is lava.
	await place(h, k, Vector2i(0, 40))
	cam.targetOffset = Vector2(120, 140)
	h.snap_camera(k)
	await wait_until_below(h, k, 9.0, 60.0)
	await h.shot("lava_rising_through_the_tunnels")
	cam.targetOffset = Vector2.ZERO
	h.note("rise events", _RisingLava.events)
	h.note("timing", {"seconds since start": h.now() - t0, "row": rise.row})
