extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t366_seal.gd"

# #366: slot 66 (t366_open: the last chain broken, the seal open, nobody in
# the lair yet) in a fresh process. The seal simply shows purple at once: no
# opening, no live moment, its bodies off. Then the keeper drills the other
# entry's crust and drops in: the lair is entered and the fight starts, as
# in a run that never reloaded.


func boot() -> Dictionary:
	return {"load": 66}


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	var ok: bool = await h.until(func(): return _LairSeal.find() != null and h.keeper() != null, 30.0)
	if not h.check("the loaded run has its lair seal", ok):
		return
	seal = _LairSeal.find()
	ch = Level.map.tileData.get_meta("story_boss_chamber")
	lava = Level.map.get_node_or_null("StoryLavaField")
	h.disable_waves()
	var k = h.keeper()
	h.check("the save is after the last chain, nobody in the lair", _EndGame.is_free() and not _EndGame.is_lair_entered(), _EndGame.state())
	h.check("the seal is purple from the start: no opening", seal.mode == "open" and not seal.blocking and is_equal_approx(float(seal._vis["tint"]), 1.0), seal.state())
	var whats: Array = _LairSeal.events.map(func(e): return e["what"])
	h.check("... and no live moment (shown open, not played)", whats == ["open"] and _LairSeal.events[0]["live"] == false, _LairSeal.events)
	h.check("the last chain did not fire again", _EndGame.events.filter(func(e): return e.get("live", false)).is_empty(), _EndGame.events)
	var cells: Array = crust_cells()
	var c_right: Vector2i = cells[2]
	await h.teleport_tile(c_right + Vector2i(2, -1))
	h.snap_camera(k)
	await h.wait(1.5)
	cool(h)
	await h.shot("purple_after_reload")
	await h.wait(2.0)
	h.check("still no opening after a while", _LairSeal.events.size() == 1, _LairSeal.events)
	var got: bool = await drill_in(h, k, c_right, "passing_in_after_reload")
	h.check("the keeper drills the other entry and drops into the lair", got, {"deepest": _deepest, "inside": _inside})
	h.check("the lair is entered", _EndGame.is_lair_entered(), _EndGame.state())
	var fight: bool = await h.until(func(): return _Director.current() == "fight", 10.0)
	h.check("and the fight starts", fight, _Director.current())
	await h.wait(1.0)
	await h.shot("fight_after_reload")
