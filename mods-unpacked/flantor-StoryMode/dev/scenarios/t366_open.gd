extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t366_seal.gd"

# #366: the last chain opens the lair seal, live (huge map, seed 12345, the
# Engineer). Nine chains break (the seal stays blue and shut), the keeper
# stands on the roof stone by the left entry, the last chain breaks far off:
# at once the seal lets keepers through, and the opening plays on screen
# (strain, break, the drain to purple, the settle), shot at each step. The
# lava still stops at the purple membrane. Saves slot 66 (open, nobody in
# yet) for t366_reload. Then the keeper drills the crust by real input,
# passes the membrane (the purple burst) and is in the lair: the lair is
# entered once (EndGame), the horror wakes and the fight starts.

const SealData = preload("res://mods-unpacked/flantor-StoryMode/data/lair_seal.gd")
const OPEN_SLOT := 66


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	if not await setup(h):
		return
	seal = _LairSeal.find()
	if not h.check("the run has a lair seal", seal != null):
		return
	ch = Level.map.tileData.get_meta("story_boss_chamber")
	var k = h.keeper()
	var lair_events: Array = []
	_EndGame.node().lair_entered.connect(func(pid): lair_events.append(pid))
	await reveal_ocean(h)
	var cells: Array = crust_cells()
	var e0: Dictionary = seal.entries[0]
	var c0: Vector2i = cells[0]
	var list: Array = anchors.anchors.duplicate()
	var last: Dictionary = list.pop_back()
	for a in list:
		anchors.dev_break(a["id"], false)
	await h.wait(1.0)
	h.check("nine chains: still sealed", _EndGame.chains_broken() == 9 and seal.mode == "sealed" and seal.blocking, [_EndGame.state(), seal.state()])

	# ---- the keeper by the seal, the last chain far off
	await h.teleport_tile(c0 + Vector2i(3, -1))
	h.snap_camera(k)
	await h.wait(1.2)
	cool(h)
	await h.shot("before_last_chain")
	anchors.dev_break(last["id"], false)
	await h.frames(2)
	h.check("the last chain: free", _EndGame.is_free(), _EndGame.state())
	h.check("at once the seal lets keepers through (its bodies off)", not seal.blocking and seal.entries.all(func(e): return e["shape"].disabled), seal.state())
	h.check("and the opening is under way", seal.mode in ["pending", "opening"], seal.mode)
	# The last-chain cutscene (#367) freezes play first; the opening waits for it.
	var LastChain = load("res://mods-unpacked/flantor-StoryMode/endgame/last_chain.gd")
	var cut_over: bool = await h.until(func(): return LastChain.is_done() and not GameWorld.paused, 40.0)
	h.check("the cutscene is over (the opening waited for it)", cut_over, _LairSeal.events)
	var steps: Array = [[0.5, "opening_strain"], [SealData.STRAIN_S + 0.06, "opening_break"], [1.75, "opening_midway"], [2.3, "opening_late"]]
	for s in steps:
		await h.until(func():
			cool(h)
			return seal.t_open >= float(s[0]) or seal.mode == "open", 8.0)
		await h.shot(str(s[1]))
	await h.burst("opening_settle", 8, 4)
	var opened: bool = await h.until(func(): return seal.mode == "open", 8.0)
	h.check("the opening ends purple", opened and is_equal_approx(float(seal._vis["phase"]), 1.0) and is_equal_approx(float(seal._vis["tint"]), 1.0), seal.state())
	var whats: Array = _LairSeal.events.map(func(e): return e["what"])
	h.check("in order: the live word, the strain, the break, the settle, open (live)", whats == ["free_live", "opening", "break", "settle", "open"] and _LairSeal.events[-1]["live"] == true, _LairSeal.events)
	h.check("with its sounds", int(Sfx.played.get("seal_strain", 0)) == 1 and int(Sfx.played.get("seal_break", 0)) == 1 and int(Sfx.played.get("seal_settle", 0)) == 1, Sfx.played)
	cool(h)
	await h.wait(1.0)
	await h.shot("purple_seal")
	h.check("open does not mean in: nobody has entered, nothing woke", not _EndGame.is_lair_entered() and _Director.current() == "", _EndGame.state())
	SaveGame.saveGame("singleplayer", OPEN_SLOT, true)
	await h.wait(1.5)
	h.note("saved slot %d" % OPEN_SLOT, {"state": _EndGame.state(), "seal": seal.state()})

	# ---- in, by the drill
	var got: bool = await drill_in(h, k, c0)
	h.check("the Engineer drills the crust and drops through the purple membrane into the lair", got and Level.map.tileData.get_resourcev(c0) == Data.TILE_EMPTY, {"deepest": _deepest, "inside": _inside})
	h.check("passing the membrane plays its burst", seal.passes >= 1 and int(Sfx.played.get("seal_pass", 0)) >= 1, [seal.passes, Sfx.played.get("seal_pass", 0)])
	h.check("the lair is entered, once, by this keeper", _EndGame.is_lair_entered() and lair_events == [k.playerId], [lair_events, _EndGame.state()])
	var fight: bool = await h.until(func(): return _Director.current() == "fight", 10.0)
	h.check("the horror wakes and the fight starts", bool(Data.ofOr("team1.story.awake", false)) and fight, _Director.current())
	await h.wait(1.0)
	await h.shot("fight_started")
	await h.teleport_tile(c0 + Vector2i(0, 1))
	await h.wait(2.0)
	var lava = Level.map.get_node_or_null("StoryLavaField")
	var in_room: float = 0.0
	for y in range(ch.position.y, ch.end.y):
		for x in range(ch.position.x, ch.end.x):
			in_room += float(lava.mass.get(Vector2i(x, y), 0.0))
	h.check("lava sits on the purple membrane, none in the lair", in_room == 0.0, {"in_room": in_room, "in_hole": lava.mass.get(c0, 0.0)})
	await h.shot("lava_on_membrane")
