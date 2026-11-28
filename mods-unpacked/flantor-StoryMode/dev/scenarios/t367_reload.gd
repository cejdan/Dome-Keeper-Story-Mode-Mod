extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t367_cutscene.gd"

# #367: slot 67 (saved by t367_cutscene after the cutscene) in a fresh process:
# no replay. The ship stands at the dome from the start; the cutscene never
# runs (no step, play never frozen by it, no live waiter); a waiter is told
# "done, not live"; the beat doesn't open again; the keeper moves. Then the
# keeper walks to the hatch by real input: the ship is boardable as usual.
# `-Extra "--slot=70"` (t367_reload_mid): slot 70, saved in the middle of the
# carry by `t367_cutscene -Extra "--midsave"`: the same after-state (the ship at
# the dome, no replay), and the beat the save cut off is queued and plays.


func boot() -> Dictionary:
	return {"load": int(_Story.user_arg("slot", str(AFTER_SLOT))), "beats": true}


func run(h) -> void:
	var slot: int = int(_Story.user_arg("slot", str(AFTER_SLOT)))
	var mid: bool = slot == MID_SLOT
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	var ok: bool = await h.until(func(): return _Ship.find() != null and _LastChain.find() != null and h.keeper() != null, 30.0)
	if not h.check("loaded slot %d: the ship and the cutscene node" % slot, ok):
		return
	ship = _Ship.find()
	cut = _LastChain.find()
	lava = Level.map.get_node_or_null("StoryLavaField")
	h.disable_waves()
	_LastChain.when_done(func(l): waited.append(l))
	await h.wait(2.0)
	var k = h.keeper()
	h.check("free, from the save", _EndGame.is_free(), _EndGame.state())
	h.check("the ship stands at the dome from the start", ship.mode == "dome" and _Ship.is_landed(), ship.mode)
	h.check("no replay: the cutscene never ran here", cut.step == "done" and _LastChain.events.all(func(e): return e["what"] != "step"), _LastChain.events)
	h.check("a waiter is told it is done, not live", waited == [false], waited)
	h.check("the done key is set", float(Data.ofOr(_LastChain.DONE_KEY, -1.0)) >= 0.0, Data.ofOr(_LastChain.DONE_KEY, null))
	if mid:
		h.check("saved mid-cutscene: noted as such", _LastChain.events.any(func(e): return e["what"] == "after_state" and e["mid"]), _LastChain.events)
		var id: String = await h.read_beat("queued_beat", 15.0)
		h.check("the beat the save cut off plays now", id == Cut.BEAT_ID, id)
	else:
		h.check("after the cutscene: nothing queued", _LastChain.events.any(func(e): return e["what"] == "after_state" and not e["mid"]), _LastChain.events)
		await h.wait(2.0)
		h.check("the beat doesn't open again", not _StoryBeats.is_open() and _StoryBeats.has_played(Cut.BEAT_ID), [_StoryBeats.is_open(), _StoryBeats.has_played(Cut.BEAT_ID)])
	h.check("play isn't frozen", not GameWorld.paused, GameWorld.paused)
	await h.shot("loaded_ship_at_dome")
	await go_home(h, k)
	var got: bool = await walk_to_hatch(h, k)
	h.check("the keeper walks to the hatch by real input: its focus", got, [str(k.focussedUsable), k.global_position - dome().global_position])
	await h.shot("at_the_hatch")
