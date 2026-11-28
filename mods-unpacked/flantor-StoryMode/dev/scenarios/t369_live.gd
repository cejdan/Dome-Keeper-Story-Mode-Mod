extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t367_cutscene.gd"

# #369: the rise, live, from the end of the last-chain cutscene (huge map,
# seed 12345, the Engineer). Nine chains break quietly, a shaft is dug up from
# the ocean's ceiling, the keeper hovers by the last anchor and it breaks:
# the rise is armed (not rising) through the cutscene (play is frozen, the
# level doesn't move), the beat is read; the moment the cutscene ends and play
# resumes, the lava starts rising from the ocean's surface (live: the roar,
# the shake), slowly at first. Shots of the ocean's air rows filling under the
# keeper and the lava climbing into the shaft over the ocean's ceiling.

const RisingLava = preload("res://mods-unpacked/flantor-StoryMode/endgame/rising_lava.gd")
static var _RisingLava = RisingLava  # calls go through this: lazy_preload makes const-preload calls slow
const TIMEOUT := 420

var rise


func run(h) -> void:
	if not await setup(h):
		return
	ship = _Ship.find()
	cut = _LastChain.find()
	rise = _RisingLava.find()
	if not h.check("the run has the ship, the cutscene and the rising lava", ship != null and cut != null and rise != null):
		return
	unmute_cut_beat()
	var k = h.keeper()
	var ocean: Dictionary = Level.map.tileData.get_meta("story_ocean")
	var top: int = int(ocean["top"])
	var ceiling: int = int(ocean["ceiling"])
	await reveal_ocean(h)
	var last: Dictionary = await break_all_but_last(h)
	# A way up from the ocean, above the last anchor.
	var ax: int = Level.map.getTileCoord(last["centre"]).x
	for y in range(ceiling - 30, ceiling + 1):
		for x in [ax, ax + 1]:
			lava.magma.erase(Vector2i(x, y))
	await h.dig_room(Vector2i(ax, ceiling - 30), Vector2i(ax + 1, ceiling))
	for c: Vector2i in lava.mass.keys():
		if c.y < ceiling:
			lava.mass.erase(c)
	h.check("nine chains: nothing rising", _RisingLava.state() == "" and not lava.flood_active(), _RisingLava.state())
	var spot: Dictionary = stand_by(last)
	await h.teleport_tile(spot["cell"])
	cool(h)
	await h.wait(1.0)
	var started: Array = []
	rise.started.connect(func(l): started.append([l, snappedf(cut.total, 0.01), cut.step]))
	anchors.dev_break(last["id"], true)
	await h.until(func(): return cut.step == "hold", 3.0)
	await h.frames(2)
	h.check("the last chain arms it; nothing rises while the cutscene plays", _RisingLava.state() == "armed" and not lava.flood_active() and str(Data.ofOr(_RisingLava.STATE_KEY, "")) == "armed", [_RisingLava.state(), lava.flood_active()])
	h.check("armed: a suit death would already be the too-late loss", _RisingLava.ends_run())
	var id: String = await h.read_beat("beat", 30.0, false)
	h.check("the cutscene's beat", id == Cut.BEAT_ID, id)
	h.check("still nothing rising at the beat", not lava.flood_active(), lava.flood_stats())
	var done: bool = await h.until(func(): return cut.step == "done", 15.0)
	await h.frames(2)
	h.check("the cutscene ends: the rise starts at once, live, from the ocean's surface", done and started.size() == 1 and started[0][0] == true and _RisingLava.state() == "rising" and absf(rise.row - float(top)) < 0.3,
		[done, started, _RisingLava.state(), rise.row, top])
	h.check("with the roar", int(Sfx.played.get("roar", 0)) >= 1, Sfx.played)
	cool(h)
	await h.wait(0.6)
	await h.shot("the_rise_begins")
	await h.wait(2.0)
	cool(h)
	await h.shot("ocean_rising_2s")
	h.check("rising, slowly at first", rise.row < float(top) - 0.1 and rise.row > float(top) - 2.5, rise.row)
	# Up to the ceiling's hole: the lava follows into the shaft.
	await h.teleport_tile(Vector2i(ax, ceiling - 8))
	var cam = Level.viewports.getPlayerCam(k.playerId)
	cam.targetOffset = Vector2(0, 110)
	h.snap_camera(k)
	await h.until(func():
		cool(h)
		return rise.row < float(ceiling) - 2.0, 30.0)
	await h.shot("into_the_shaft")
	cam.targetOffset = Vector2.ZERO
	h.note("rise events", _RisingLava.events)
