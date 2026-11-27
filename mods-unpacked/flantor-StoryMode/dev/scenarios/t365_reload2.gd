extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t365_anchors.gd"

# #365, part three: run t365_reload first. Loads its save (slot 41, every
# chain broken): free with the saved time, the tentacles at full wake, every
# anchor a stub, no live event on the load, a waiter is called at once and not
# live, and the awakening level is the seal's cap.

const Awakening2 = preload("res://mods-unpacked/flantor-StoryMode/beats/awakening.gd")

var waiter_calls: Array = []


func boot() -> Dictionary:
	return {"load": 41, "boss": false}


func run(h) -> void:
	await h.until(func(): return not SaveGame.currentLoadingSavegame, 20.0)
	if not await setup(h):
		return
	h.check("still free after the reload, with the saved time", _EndGame.is_free() and _EndGame.chains_broken() == 10 and _EndGame.freed_at() > 0.0, _EndGame.state())
	h.check("every anchor broken, none snapping", anchors.anchors.all(func(a): return a["broken"] and a["snap_t"] < 0.0))
	h.check("the tentacles at full wake", _Ocean.chains_broken() == 10, _Ocean.chains_broken())
	_EndGame.when_free(func(live): waiter_calls.append(live))
	await h.wait(2.0)
	h.check("no live event on the load; a waiter is told at once, not live", chain_events.is_empty() and last_events == 0 and _EndGame.events.is_empty() and waiter_calls == [false], [_EndGame.events, waiter_calls])
	h.check("the seal is at its cap until the chamber", is_equal_approx(Awakening2.level(), Awakening2.SEAL_MAX), Awakening2.level())
	await reveal_ocean(h)
	await look_at(h, tents.rigs[1].segments[tents.rigs[1].count / 2].global_position + Vector2(-110, 0))
	await h.shot("reloaded_free")
