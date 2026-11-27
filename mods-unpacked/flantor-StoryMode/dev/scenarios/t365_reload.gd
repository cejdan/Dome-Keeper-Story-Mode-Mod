extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t365_anchors.gd"

# #365, part two: run t365_anchors first. Loads its save (slot 40, six chains
# broken) in a fresh process: the same six are broken (their tiles gone,
# shown as stubs, no snap), the other four whole, the tentacles at six
# chains' wake, no live event on load. Then the last four break: the last
# chain fires exactly once (its signal, the waiter registered before it,
# EndGame.is_free, the record's time), and nothing fires again after.
# A waiter registered after it is called at once, not live. Saves slot 41 for
# t365_reload2. Shots: the stubs after the load, the last break.

const SLOT_IN := 40
const SLOT_OUT := 41

var waiter_calls: Array = []


func boot() -> Dictionary:
	return {"load": SLOT_IN, "boss": false}


func run(h) -> void:
	await h.until(func(): return not SaveGame.currentLoadingSavegame, 20.0)
	if not await setup(h):
		return
	var td = Level.map.tileData
	h.check("six chains broken after the load", _EndGame.chains_broken() == 6 and not _EndGame.is_free(), _EndGame.state())
	var broken: Array = anchors.anchors.filter(func(a): return a["broken"])
	h.check("the same six anchors show broken, the other four whole", broken.size() == 6 and broken.all(func(a): return _EndGame.is_anchor_broken(a["id"])), broken.map(func(a): return a["id"]))
	h.check("broken anchors' tiles are gone, whole ones' standing", anchors.anchors.all(func(a): return a["cells"].all(func(c): return (td.get_resourcev(c) == AnchorData.TILE_ID) != a["broken"])))
	h.check("they come back broken, not snapping again", anchors.anchors.all(func(a): return a["snap_t"] < 0.0))
	h.check("the tentacles are at six chains' wake", _Ocean.chains_broken() == 6 and is_equal_approx(tents.rigs[0].target_share, _Ocean.share_for(_Ocean.wake_for(6))), [_Ocean.chains_broken(), tents.rigs[0].target_share])
	h.check("no live event on the load", chain_events.is_empty() and last_events == 0 and _EndGame.events.is_empty(), _EndGame.events)
	await reveal_ocean(h)
	await look_at(h, tents.rigs[0].segments[tents.rigs[0].count / 2].global_position + Vector2(100, 0))
	await h.shot("reloaded_stubs")
	_EndGame.when_free(func(live): waiter_calls.append(["before", live]))
	# The last four.
	var rest: Array = anchors.anchors.filter(func(a): return not a["broken"])
	for i in rest.size():
		var a: Dictionary = rest[i]
		if i == rest.size() - 1:
			await look_at(h, a["centre"] + Vector2(-signf(a["side"]) * 80.0, -50.0))
			anchors.dev_break(a["id"])
			await h.burst("last_chain", 14, 3)
		else:
			await hit_break(h, a)
		cool(h)
	await h.wait(1.0)
	h.check("ten broken: one live chain event each", _EndGame.chains_broken() == 10 and chain_events.size() == 4, [_EndGame.state(), chain_events])
	h.check("the last chain fired exactly once", last_events == 1 and _EndGame.events.filter(func(e): return e["what"] == "last_chain").size() == 1, _EndGame.events)
	h.check("the waiter from before was called once, live", waiter_calls == [["before", true]], waiter_calls)
	h.check("free, with the time it broke", _EndGame.is_free() and _EndGame.freed_at() > 0.0, _EndGame.state())
	h.check("the tentacles at full wake", _Ocean.chains_broken() == 10, _Ocean.chains_broken())
	_EndGame.when_free(func(live): waiter_calls.append(["after", live]))
	await h.wait(0.5)
	h.check("a waiter after it is called at once, not live", waiter_calls.size() == 2 and waiter_calls[1] == ["after", false], waiter_calls)
	# Nothing breaks it again: a repeat record is ignored.
	_EndGame.record_break(rest[0]["id"])
	await h.wait(0.5)
	h.check("nothing fires twice", last_events == 1 and chain_events.size() == 4, [last_events, chain_events.size()])
	await h.wait(2.0)
	await look_at(h, tents.rigs[0].segments[tents.rigs[0].count - 4].global_position + Vector2(110, 10))
	await h.shot("all_broken_tentacle_0")
	await h.burst("all_broken_swing", 8, 8)
	await SaveGame.saveGame("singleplayer", SLOT_OUT, true)
	await h.wait(1.0)
	h.note("saved slot %d" % SLOT_OUT, _EndGame.state())
