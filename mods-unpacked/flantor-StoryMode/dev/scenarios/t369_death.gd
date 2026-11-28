extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t369_rise.gd"

# #369: once the horror is free, a death in the lava ends the run (no recall
# to the dome). Huge map, seed 12345, the chains broken quietly, shaft A dug;
# the rise starts a few rows under the keeper, who stays in the shaft. The
# lava closes over it; with its suit near full heat it gives out: the keeper
# is not sent home (it stays where it died), the "too late" moment plays (the
# keeper sinks away into the lava), the [DRAFT] card, the end screen
# ("[DRAFT] Too Late"), the run lost. Before that a gas death would be the
# same: `ends_run()` is checked for it.

const Endings = preload("res://mods-unpacked/flantor-StoryMode/data/endings.gd")


func run(h) -> void:
	if not await setup(h):
		return
	var k = h.keeper()
	await dig_clean(h, Vector2i(3, 100), Vector2i(4, ceiling))
	await place(h, k, Vector2i(3, 120))
	h.check("before the rise, a death would still be a recall", not _RisingLava.ends_run(), _RisingLava.state())
	rise.dev_start(124.5)
	await h.frames(2)
	h.check("rising: a suit death ends the run now", _RisingLava.ends_run(), _RisingLava.state())
	var spot: Vector2 = k.global_position
	await wait_until_below(h, k, -0.6, 30.0)
	h.check("the lava closed over the keeper", lava.keeper_in_lava(k), rows_below(k))
	await h.shot("caught_in_the_lava")
	lava.set_heat_of(k, lava.HEAT_MAX * 0.97)
	var ended: bool = await h.until(func(): return Level.mode.is_ending(), 10.0)
	h.check("the suit gives out: the run ends", ended and _RisingLava.events.any(func(e): return e["what"] == "death" and e["cause"] == "lava"), _RisingLava.events)
	h.check("no recall to the dome: the keeper stays where it died", k.global_position.distance_to(spot) < 120.0 and not k.isInsideDome, [k.global_position - spot, k.isInsideDome])
	h.check("no lava-death beat or money penalty (it isn't a recall)", lava.recalls == 0, lava.recalls)
	await h.wait(0.5)
	await h.burst("sinking_away", 6, 8)
	h.check("the too-late moment plays (lava)", Level.mode.too_late_shown == ["lava"], Level.mode.too_late_shown)
	var ed = Level.mode.get_node_or_null("StoryEndings")
	await h.until(func(): return ed.playing == "too_late" and ed.last_step == "cards", 15.0)
	var seen: Array = []
	var t_end: float = h.now() + 30.0
	while h.now() < t_end and ed.last_step == "cards":
		var box = h.beat_box()
		if box != null and box.get("cards") != null and box.current_card() != "" and not seen.has(box.current_card()):
			await h.wait(1.2)
			seen.append(box.current_card())
			await h.shot("card_%d" % seen.size())
		await h.wait(0.2)
	h.check("the [DRAFT] card shows", seen == Endings.TOO_LATE_DEATH_CARDS, seen)
	await h.until(func(): return Level.stage.endingPanel != null, 20.0)
	await h.wait(3.0)
	var panel = Level.stage.endingPanel
	await h.shot("too_late_end_screen")
	h.check("the end screen reads \"%s\"" % Endings.TOO_LATE_TITLE, panel != null and panel.titleLabel.text == Endings.TOO_LATE_TITLE, panel.titleLabel.text if panel != null else "")
	h.check("the run is recorded as lost, not won", GameWorld.lost and not GameWorld.won)
	h.check("one end screen", Level.mode.end_screens == 1, Level.mode.end_screens)
