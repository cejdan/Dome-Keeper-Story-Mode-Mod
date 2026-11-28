extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t369_rise.gd"

# #369: the rising lava in splitscreen (#231). The chains broken quietly, the
# route of t369_rise dug. Keeper 1 waits in shaft A just over the ocean's
# ceiling, keeper 2 far up in shaft B. The rise starts: each keeper's warning
# is its own (keeper 1's grows as the lava comes up under it, keeper 2's stays
# low; each camera shakes by its own keeper's), the lava shows in keeper 1's
# view, then in keeper 2's when it comes down to meet it (shots of both
# halves), each keeper is in lava only when the line is over it, and keeper 1
# caught in it doesn't end the run while its heat holds.

const Split = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t231_split_restart.gd")
static var _Split = Split  # calls go through this: lazy_preload makes const-preload calls slow


func boot() -> Dictionary:
	return {"loadout": true, "splitscreen": true}


func run(h) -> void:
	if not await _Split.start_split(h):
		return
	if not await setup(h):
		return
	var k1 = Keepers.getLocalKeeperByDeviceId(0)
	var k2 = Keepers.getLocalKeeperByDeviceId(1)
	load("res://mods-unpacked/flantor-StoryMode/map/chain_anchors.gd").find().dev_free_all()
	_EndGame.dev_free()
	await dig_route(h)
	await h.teleport_tile(Vector2i(3, ceiling - 6), k1)
	await h.teleport_tile(Vector2i(11, 70), k2)
	h.snap_camera(k1)
	h.snap_camera(k2)
	await h.wait(1.0)
	cool(h)
	rise.dev_start()
	await h.until(func():
		cool(h)
		return rows_below(k1) <= 3.0, 30.0)
	var u1: float = float(rise.closeness.get(k1.playerId, 0.0))
	var u2: float = float(rise.closeness.get(k2.playerId, 0.0))
	h.check("each keeper's warning is its own: keeper 1 (lava close) strong, keeper 2 (far up) none", u1 > 0.9 and u2 < 0.05, rise.closeness)
	var c1 = Level.viewports.getPlayerCam(k1.playerId)
	var c2 = Level.viewports.getPlayerCam(k2.playerId)
	h.check("keeper 1's camera shakes, keeper 2's doesn't", c1.shake_strength > c2.shake_strength, [c1.shake_strength, c2.shake_strength])
	await h.shot("split_lava_under_keeper1")
	# Keeper 1 caught in it; keeper 2 not.
	await h.until(func():
		cool(h)
		return rows_below(k1) <= -1.0, 20.0)
	h.check("keeper 1 is in lava, keeper 2 isn't", lava.keeper_in_lava(k1) and not lava.keeper_in_lava(k2), [rows_below(k1), rows_below(k2)])
	h.check("caught, its heat held: the run goes on", not Level.mode.is_ending(), Level.mode.is_ending())
	# Keeper 1 goes up to keeper 2's shaft; the lava comes up to meet keeper 2.
	await h.teleport_tile(Vector2i(11, 60), k1)
	h.snap_camera(k1)
	rise.dev_set_row(80.0)
	await h.until(func():
		cool(h)
		return rows_below(k2) <= 4.0, 30.0)
	await h.wait(0.3)
	await h.shot("split_lava_in_both_views")
	h.check("now both keepers feel it", float(rise.closeness.get(k1.playerId, 0.0)) > 0.5 and float(rise.closeness.get(k2.playerId, 0.0)) > 0.9, rise.closeness)
	h.check("the band and implied lava keep to one strip", lava.flood_stats()["band_cells"] < 120, lava.flood_stats())
