extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t369_rise.gd"

# #369: entering the lair stops the rise, for good. Huge map, seed 12345, the
# chains broken quietly (the seal is purple), shaft A dug up from the ocean.
# The rise starts; once it is over the ocean's ceiling and into the shaft, the
# keeper dives through the ocean to the lair's left entry and drills down
# through the crust and the purple membrane by real input. At that moment:
# the state is "stopped", the level stays where it is through the fight that
# starts (checked over several seconds), the band is still lava (the line is
# held, not drained), the warning fades out, a suit death is no longer the
# too-late loss (the fight's hearts take over), and the lava never rises
# again (not when the fight goes on, not after the boss state moves on).

const LairSeal = preload("res://mods-unpacked/flantor-StoryMode/endgame/lair_seal.gd")
static var _LairSeal = LairSeal  # calls go through this: lazy_preload makes const-preload calls slow
const LavaData = preload("res://mods-unpacked/flantor-StoryMode/data/lava.gd")


func run(h) -> void:
	if not await setup(h):
		return
	var k = h.keeper()
	var ch: Rect2i = Level.map.tileData.get_meta("story_boss_chamber")
	var c0 := Vector2i(ch.position.x + int(LavaData.BOSS_CHAMBER_ENTRY[0]), ch.position.y - 1)
	await dig_clean(h, Vector2i(3, 100), Vector2i(4, ceiling))
	await h.reveal(range(ceiling, ch.end.y + 1).map(func(y): return Vector2i(c0.x, y)))
	await place(h, k, Vector2i(3, 120))
	rise.dev_start()
	var stopped_why: Array = []
	rise.stopped.connect(func(w): stopped_why.append(w))
	await h.until(func():
		cool(h)
		return rise.row < float(ceiling) - 4.0, 40.0)
	var cam = Level.viewports.getPlayerCam(k.playerId)
	await h.shot("rising_in_shaft_a")
	# Into the lair: the keeper dives to the entry and drills through.
	await h.teleport_tile(c0 + Vector2i(0, -1), k)
	cool(h)
	h.down("ui_down")
	var t0: float = h.now()
	while h.now() - t0 < 20.0 and not _EndGame.is_lair_entered():
		await h.wait(0.05)
		cool(h)
	h.up("ui_down")
	var row_at: float = rise.row
	h.check("the keeper drilled through the membrane into the lair", _EndGame.is_lair_entered(), [_EndGame.state(), Level.map.getTileCoord(k.global_position)])
	await h.frames(2)
	h.check("entering the lair stops the rise", _RisingLava.state() == "stopped" and stopped_why == ["lair"], [_RisingLava.state(), stopped_why])
	h.check("a suit death is no longer the too-late loss", not _RisingLava.ends_run(), _RisingLava.state())
	await h.wait(0.5)
	await h.shot("in_the_lair")
	var fight: bool = await h.until(func(): return str(Data.ofOr("team1.story.boss", "")) == "fight", 15.0)
	h.check("the fight starts", fight, Data.ofOr("team1.story.boss", ""))
	await h.wait(6.0)
	h.check("the level stays where it stopped through the fight", is_equal_approx(rise.row, row_at) and _RisingLava.state() == "stopped", [rise.row, row_at])
	h.check("the line is held, not drained: shaft A under it is still lava", lava.flooded(Vector2i(3, int(ceil(row_at)) + 1)) and lava.flooded(Vector2i(3, ceiling - 1)), lava.flood_stats())
	h.check("the warning has faded out", float(rise.closeness.get(k.playerId, 1.0)) == 0.0, rise.closeness)
	# A look at the stopped line, from the shaft (the camera only).
	var line_at := Vector2(Level.map.getTilePos(Vector2(3, 0)).x + 12.0, lava.flood_y())
	var saved_cam: Vector2 = cam.targetOffset
	cam.targetOffset = line_at - k.global_position
	h.snap_camera(k)
	await h.wait(0.3)
	await h.shot("the_stopped_line")
	cam.targetOffset = saved_cam
	h.snap_camera(k)
	# It never rises again: a start is refused.
	rise.start(true)
	await h.wait(1.0)
	h.check("nothing starts it again", is_equal_approx(rise.row, row_at) and _RisingLava.state() == "stopped", [rise.row, _RisingLava.state()])
