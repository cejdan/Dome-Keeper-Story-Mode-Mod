extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t367_cutscene.gd"

# #367: skipping the cutscene. The last chain breaks; a quick tap of the use
# key does nothing; holding it during the rise fills the ring (shot) and, once
# full, sets the ship down at once and plays the beat; then back to the
# keeper as usual. Done once, live, play resumes.


func run(h) -> void:
	if not await setup(h):
		return
	ship = _Ship.find()
	cut = _LastChain.find()
	unmute_cut_beat()
	cut.step_changed.connect(func(s): steps_seen.append(s))
	var k = h.keeper()
	await reveal_ocean(h)
	var last: Dictionary = await break_all_but_last(h)
	var spot: Dictionary = stand_by(last)
	await h.teleport_tile(spot["cell"])
	cool(h)
	await h.wait(0.5)
	anchors.dev_break(last["id"], false)
	await h.until(func(): return cut.step == "hold", 3.0)
	await h.press("ui_select")
	await h.wait(1.4)
	h.check("a tap doesn't skip", not cut.skipped and cut.step in ["hold", "rise"], cut.step)
	h.down("ui_select")
	await h.wait(Cut.SKIP_HOLD_S * 0.6)
	await h.shot("skip_ring_filling")
	await h.until(func(): return cut.skipped, 2.0)
	h.up("ui_select")
	h.check("holding the use key skips: the ship stands at the dome at once", cut.skipped and ship.mode == "dome" and _Ship.is_landed(), [cut.skipped, ship.mode, cut.step])
	var id: String = await h.read_beat("beat_after_skip", 12.0)
	h.check("the beat still plays", id == Cut.BEAT_ID, id)
	var done: bool = await h.until(func(): return cut.step == "done", 10.0)
	h.check("back to the keeper, play resumes, done (live)", done and not GameWorld.paused and _LastChain.is_done(), [cut.step, GameWorld.paused])
	h.check("the steps: skipped from the rise to the beat", not steps_seen.has("burst") and steps_seen.has("beat") and steps_seen.has("return"), steps_seen)
	await h.shot("after_skip")
