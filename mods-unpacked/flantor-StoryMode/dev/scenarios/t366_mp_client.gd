extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #366: client half. Its seal is built from the host's map facts and is blue
# and shut; its keeper drills at the right entry by real input for a while:
# the crust stays (refused here and on the host), the keeper never gets in
# and is thrown back. Then the host's last chain reaches it live: the seal
# lets it through at once and the opening plays on its screen; its keeper
# drills in, passes the membrane and enters the lair; the host's record comes
# back (EndGame.is_lair_entered, the lair_entered signal once, live) and the
# fight starts here too. Pair: t366_mp_host.

const EndGame = preload("res://mods-unpacked/flantor-StoryMode/endgame/end_game.gd")
static var _EndGame = EndGame  # calls go through this: lazy_preload makes const-preload calls slow
const Anchors = preload("res://mods-unpacked/flantor-StoryMode/map/chain_anchors.gd")
static var _Anchors = Anchors  # calls go through this: lazy_preload makes const-preload calls slow
const Ocean = preload("res://mods-unpacked/flantor-StoryMode/map/ocean_tentacles.gd")
static var _Ocean = Ocean  # calls go through this: lazy_preload makes const-preload calls slow
const LairSeal = preload("res://mods-unpacked/flantor-StoryMode/endgame/lair_seal.gd")
static var _LairSeal = LairSeal  # calls go through this: lazy_preload makes const-preload calls slow
const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const Keeper2Run = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t297_keeper2.gd")
const Base = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t366_seal.gd")
const TIMEOUT := 480

var lair_events: Array = []
var lair_waiter: Array = []


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var ready = await shared(h, "ready", 150.0)
	if not h.check("host ready", ready != null):
		return
	var ok: bool = await h.until(func(): return _LairSeal.find() != null and _Anchors.find() != null, 30.0)
	if not h.check("client: the seal is built from the host's map facts", ok):
		return
	var base = Base.new()
	base.anchors = _Anchors.find()
	base.tents = _Ocean.find()
	base.lava = Level.map.get_node_or_null("StoryLavaField")
	base.seal = _LairSeal.find()
	base.ch = Level.map.tileData.get_meta("story_boss_chamber")
	var seal = base.seal
	_EndGame.node().lair_entered.connect(func(pid): lair_events.append(pid))
	_EndGame.when_lair_entered(func(live): lair_waiter.append(live))
	h.check("client: two entries, blue and shut", seal.entries.size() == 2 and seal.mode == "sealed" and seal.blocking, seal.state())
	await base.reveal_ocean(h)
	var cells: Array = base.crust_cells()
	var c: Vector2i = cells[2]
	var k = h.keeper()
	base._start_track(h, k)
	await h.teleport_tile(c + Vector2i(0, -1))
	base.cool(h)
	await h.wait(0.5)
	await h.shot("client_blue_seal")
	var t_end: float = h.now() + 7.0
	var first := true
	while h.now() < t_end:
		if k.global_position.distance_to(Level.map.getTilePos(Vector2(c))) > 90.0:
			await h.teleport_tile(c + Vector2i(0, -1))
		if first:
			first = false
			Keeper2Run.dig(h, k, "ui_down", 2.0)
			await h.burst("client_bounces_off", 10, 3)
			await h.wait(1.0)
		else:
			await Keeper2Run.dig(h, k, "ui_down", 2.0)
		base.cool(h)
	h.check("client: the crust is whole here", base.standing(cells) == 4)
	h.check("client: its keeper never got in, and was thrown back", base._deepest < -Base.T + 4.0 and base._inside == 0 and seal.touches > 0, {"deepest": base._deepest, "inside": base._inside, "touches": seal.touches, "refused": seal.hits_refused})
	await shared(h, "free", 120.0)
	var live: bool = await h.until(func(): return _LairSeal.events.any(func(e): return e["what"] == "free_live"), 10.0)
	h.check("client: the last chain reached the seal live, and it let keepers through", live and not seal.blocking, [_LairSeal.events, seal.state()])
	# The last-chain cutscene (#367) plays first; the opening waits for it.
	var LastChain = load("res://mods-unpacked/flantor-StoryMode/endgame/last_chain.gd")
	await h.until(func(): return LastChain.is_done() and not GameWorld.paused, 45.0)
	await h.teleport_tile(c + Vector2i(2, -1))
	h.snap_camera(k)
	await h.until(func():
		base.cool(h)
		return seal.t_open >= 1.75 or seal.mode == "open", 10.0)
	await h.shot("client_opening_midway")
	var opened: bool = await h.until(func():
		base.cool(h)
		return seal.mode == "open", 10.0)
	var whats: Array = _LairSeal.events.map(func(e): return e["what"])
	h.check("client: the opening played here, live", opened and whats == ["free_live", "opening", "break", "settle", "open"] and _LairSeal.events[-1]["live"] == true, _LairSeal.events)
	await h.shot("client_purple_seal")
	var got: bool = await base.drill_in(h, k, c, "client_passing_in")
	h.check("client: its keeper drills in through the purple membrane", got, {"inside": base._inside})
	var told: bool = await h.until(func(): return _EndGame.is_lair_entered() and lair_events.size() == 1, 10.0)
	h.check("client: the host's record comes back live, once", told and lair_events == [k.playerId] and lair_waiter == [true], [lair_events, lair_waiter, _EndGame.state()])
	var fight: bool = await h.until(func(): return _Director.current() == "fight", 12.0)
	h.check("client: the fight starts here too", fight, _Director.current())
	await shared(h, "fight", 30.0)
	await h.wait(1.0)
	await h.shot("client_fight")
