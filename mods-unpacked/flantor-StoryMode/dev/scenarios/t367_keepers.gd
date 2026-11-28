extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t365_keepers.gd"

# #367: every keeper breaks the last chain by real input from an awkward
# place, and is safe and sensible when play resumes. The Engineer by default;
# `-Extra "--keeper=keeper2"` (keeper3, keeper4; the Beastmaster only through
# this dev harness). Nine chains break quietly; the keeper goes to the last
# one and digs it its own way (t365_keepers): the Engineer and the Beastmaster
# the lowest, deep in the lava by the floor (in the lava, hot); the Assessor
# and the Infiltrator the highest, under the ceiling (in the air; the
# Infiltrator hanging from its hook on the stone itself). Keys stay held as
# the stone breaks. Then the cutscene: frozen all through (the keeper never
# moves, its heat never rises); after it: alive, not in rock, its heat no more
# than the resume cap, still in the ocean, and it moves by real input.

const LastChain = preload("res://mods-unpacked/flantor-StoryMode/endgame/last_chain.gd")
static var _LastChain = LastChain  # calls go through this: lazy_preload makes const-preload calls slow
const Cut = preload("res://mods-unpacked/flantor-StoryMode/data/last_chain.gd")


func run(h) -> void:
	if not await setup(h):
		return
	var k = h.keeper()
	var kid: String = _Story.user_arg("keeper", "keeper1")
	h.check("the keeper is the %s" % kid, k.techId == kid, k.techId)
	await Keeper2Run.close_tutorials(h)
	await reveal_ocean(h)
	var cut = _LastChain.find()
	var list: Array = anchors.anchors.duplicate()
	list.sort_custom(func(x, y): return x["centre"].y > y["centre"].y)
	var high: bool = kid in ["keeper2", "keeper3"]
	var a: Dictionary = list[-1] if high else list[0]
	for b in list:
		if b["id"] != a["id"]:
			anchors.dev_break(b["id"], false)
	await h.wait(1.0)
	h.check("nine chains broken", _EndGame.chains_broken() == 9, _EndGame.state())
	var spot: Dictionary = stand_by(a)
	if not h.check("an open cell beside the last anchor", not spot.is_empty(), a["cell"]):
		return
	var dir: String = dir_action(spot["dir"])
	await h.teleport_tile(spot["cell"])
	tents.refresh_near()
	cool(h)
	await h.wait(0.4)
	var where: String = "high" if high else "low"
	await h.shot("%s_by_the_last_anchor_%s" % [kid, where])
	var t0: float = h.now()
	var st := {"heat": -1.0, "at": Vector2.INF}
	cut.step_changed.connect(func(s):
		if s == "hold":
			# Some heat so the cap shows (the lowest anchor is in the lava).
			if not high:
				lava.set_heat_of(k, lava.HEAT_MAX * 0.9)
			st["heat"] = lava.heat_of(k)
			st["at"] = k.global_position)
	while not a["broken"] and h.now() - t0 < 40.0:
		if k.global_position.distance_to(a["centre"]) > (160.0 if kid == "keeper3" else 70.0):
			await h.teleport_tile(spot["cell"])
		if kid == "keeper3":
			await _infiltrator(h, k, a)
		else:
			await Keeper2Run.dig(h, k, dir, 2.0)
		if not a["broken"]:
			# Cool only while it digs; not once the last chain has gone.
			cool(h)
	h.check("the %s breaks the last chain its own way (%s)" % [kid, where], a["broken"] and _EndGame.is_free(), {"seconds": snappedf(h.now() - t0, 0.1)})
	h.note("state at the break", {"in_lava": lava.keeper_in_lava(k), "hooked": is_instance_valid(k.get("hook")) and k.hook.has_hit if "hook" in k else false, "pos": k.global_position})
	var started: bool = await h.until(func(): return cut.step != "idle", 3.0)
	h.check("the cutscene plays", started, cut.step)
	# Held keys don't matter now.
	h.down(dir if dir != "" else "ui_left")
	await h.until(func(): return cut.step == "beat" or cut.step == "return" or cut.step == "done", 40.0)
	h.up(dir if dir != "" else "ui_left")
	var at: Vector2 = st["at"]
	var frozen_ok: bool = at != Vector2.INF and k.global_position.distance_to(at) < 0.5 and is_equal_approx(lava.heat_of(k), float(st["heat"]))
	h.check("frozen all through: the keeper never moved, its heat never rose", frozen_ok and GameWorld.paused, [k.global_position - at if at != Vector2.INF else null, lava.heat_of(k), st["heat"]])
	var done: bool = await h.until(func(): return cut.step == "done", 30.0)
	h.check("the cutscene ends and play resumes", done and not GameWorld.paused, [cut.step, GameWorld.paused])
	await h.wait(0.1)
	var heat_after: float = lava.heat_of(k)
	await h.shot("%s_play_resumes" % kid)
	h.check("safe when play resumes: alive, its heat at most the cap", not k.killed and heat_after <= lava.HEAT_MAX * Cut.RESUME_HEAT_MAX + 0.5, [k.killed, heat_after, lava.HEAT_MAX])
	var cell: Vector2i = Level.map.getTileCoord(k.global_position)
	var ocean: Dictionary = Level.map.tileData.get_meta("story_ocean")
	h.check("not in rock, still in the ocean", Level.map.tileData.get_resourcev(cell) == Data.TILE_EMPTY and cell.y > int(ocean["ceiling"]) and cell.x >= int(ocean["x0"]) - 1 and cell.x <= int(ocean["x1"]) + 1, [cell, Level.map.tileData.get_resourcev(cell)])
	var p0: Vector2 = k.global_position
	if kid == "keeper3" and is_instance_valid(k.hook):
		h.down("ui_down")
		await h.wait(0.6)
		h.up("ui_down")
	await h.hold("ui_up", 1.0)
	await h.hold("ui_left", 0.6)
	await h.hold("ui_right", 0.6)
	h.check("it moves by real input", k.global_position.distance_to(p0) > 4.0, k.global_position - p0)
	await h.wait(1.0)
	await h.shot("%s_moving_again" % kid)
	h.check("and is still alive", not k.killed, k.killed)
