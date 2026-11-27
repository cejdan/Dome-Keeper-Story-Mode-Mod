extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #365: client half. Its anchors come from the host's map facts; the host's
# two breaks reach it live (the chain event per break, the snap played, the
# count in Data, the tentacles' wake); its own keeper drills a third anchor
# by real input (the break plays here at once and the host records it); then
# the host breaks the rest and the last chain reaches it live exactly once,
# with EndGame.is_free() and a waiter told live. Pair: t365_mp_host.

const EndGame = preload("res://mods-unpacked/flantor-StoryMode/endgame/end_game.gd")
static var _EndGame = EndGame  # calls go through this: lazy_preload makes const-preload calls slow
const Anchors = preload("res://mods-unpacked/flantor-StoryMode/map/chain_anchors.gd")
static var _Anchors = Anchors  # calls go through this: lazy_preload makes const-preload calls slow
const Ocean = preload("res://mods-unpacked/flantor-StoryMode/map/ocean_tentacles.gd")
static var _Ocean = Ocean  # calls go through this: lazy_preload makes const-preload calls slow
const Base = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t365_anchors.gd")
const TIMEOUT := 480

var chain_events: Array = []
var last_events: int = 0
var waiter: Array = []


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var ready = await shared(h, "ready", 150.0)
	if not h.check("host ready", ready != null):
		return
	var ok: bool = await h.until(func(): return _Anchors.find() != null, 30.0)
	if not h.check("client: the anchors are built from the host's map facts", ok):
		return
	var anchors = _Anchors.find()
	h.check("client: ten anchors", anchors.anchors.size() == 10, anchors.anchors.size())
	var base = Base.new()
	base.anchors = anchors
	base.tents = _Ocean.find()
	base.lava = Level.map.get_node_or_null("StoryLavaField")
	_EndGame.node().chain_broken.connect(func(id, n): chain_events.append([id, n]))
	_EndGame.node().last_chain_broken.connect(func(): last_events += 1)
	_EndGame.when_free(func(live): waiter.append(live))
	await base.reveal_ocean(h)
	var mine = await shared(h, "client_anchor")
	var a: Dictionary = anchors.anchors.filter(func(x): return x["id"] == int(mine["id"]))[0]
	var k = h.keeper()
	k.teleport(a["centre"] + Vector2(-80, -60))
	base.tents.refresh_near()
	h.snap_camera(k)
	await shared(h, "two", 60.0)
	await h.wait(1.5)
	h.check("client: the host's two breaks arrive (Data and a live event each)", _EndGame.chains_broken() == 2 and chain_events.size() == 2, [_EndGame.state(), chain_events])
	var played: Array = anchors.anchors.filter(func(x): return x["broken"] and x["snap_t"] >= 0.0)
	h.check("client: both played their snap here", played.size() == 2, played.size())
	h.check("client: its tentacles follow (2 chains)", _Ocean.chains_broken() == 2, _Ocean.chains_broken())
	# Its own keeper drills its anchor.
	var cell := Vector2i(int(mine["cell"][0]), int(mine["cell"][1]))
	var dir := Vector2(float(mine["dir"][0]), float(mine["dir"][1]))
	await h.teleport_tile(cell)
	base.tents.refresh_near()
	base.cool(h)
	await h.wait(0.3)
	var act: String = base.dir_action(dir)
	var t0: float = h.now()
	h.down(act)
	var broke: bool = await h.until(func():
		base.cool(h)
		return a["broken"], 40.0)
	h.up(act)
	h.check("client: its keeper breaks the anchor (it plays here at once)", broke and a["snap_t"] >= 0.0, h.now() - t0)
	await h.burst("client_break", 8, 4)
	var three: bool = await h.until(func(): return _EndGame.chains_broken() == 3, 15.0)
	h.check("client: the host's record of it comes back (3)", three, _EndGame.state())
	await shared(h, "done", 120.0)
	await h.wait(2.0)
	h.check("client: all ten, free", _EndGame.chains_broken() == 10 and _EndGame.is_free(), _EndGame.state())
	h.check("client: the last chain arrived live exactly once", last_events == 1 and _EndGame.events.filter(func(e): return e["what"] == "last_chain").size() == 1, _EndGame.events)
	h.check("client: its waiter was told once, live", waiter == [true], waiter)
	h.check("client: every anchor's tiles are gone here", anchors.anchors.all(func(x): return x["cells"].all(func(c): return Level.map.tileData.get_resourcev(c) == Data.TILE_EMPTY)))
	h.check("client: its tentacles at full wake", _Ocean.chains_broken() == 10, _Ocean.chains_broken())
	await h.shot("client_end")
