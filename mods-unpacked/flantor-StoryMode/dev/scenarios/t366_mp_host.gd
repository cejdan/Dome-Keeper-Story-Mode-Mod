extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #366: host half of the online check for the lair seal. The client's keeper
# drills at the blue seal over the right entry (its hits reach the host as
# tile hits: refused here too, the crust stays on both); the host breaks all
# ten chains (the last live); the client sees the opening live, drills in and
# enters the lair; the host records it from the client's word, wakes the
# horror and starts the fight. Pair: t366_mp_client.

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
const Base = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t366_seal.gd")
const TIMEOUT := 480

var lair_events: Array = []


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if not await host_start(h):
		return
	var ok: bool = await h.until(func(): return _Anchors.find() != null and _LairSeal.find() != null, 20.0)
	if not h.check("host: the anchors and the seal are built", ok):
		return
	var base = Base.new()
	base.anchors = _Anchors.find()
	base.tents = _Ocean.find()
	base.lava = Level.map.get_node_or_null("StoryLavaField")
	base.seal = _LairSeal.find()
	base.ch = Level.map.tileData.get_meta("story_boss_chamber")
	var seal = base.seal
	_EndGame.node().lair_entered.connect(func(pid): lair_events.append(pid))
	h.disable_waves()
	load("res://mods-unpacked/flantor-StoryMode/dev/boss_dev.gd").give_gear()
	await base.reveal_ocean(h)
	var cells: Array = base.crust_cells()
	# The host's keeper looks on from beside the left entry.
	var k = h.keeper()
	await h.teleport_tile(cells[0] + Vector2i(3, -1))
	share("ready", true)
	var refused0: int = seal.hits_refused
	var tried = await shared(h, "tried", 120.0)
	base.cool(h)
	h.check("host: the client tried", tried != null)
	h.check("host: the client's hits on the crust were refused here too", seal.hits_refused > refused0, seal.hits_refused - refused0)
	h.check("host: its touches crackled here", seal.remote_touches > 0, seal.remote_touches)
	h.check("host: all four crust tiles still stand", base.standing(cells) == 4)
	h.check("host: sealed, nobody in the lair", seal.mode == "sealed" and seal.blocking and not _EndGame.is_lair_entered())
	await h.shot("host_after_client_tried")
	for a in base.anchors.anchors:
		if not a["broken"]:
			base.anchors.dev_break(a["id"], false)
			await h.wait(0.2)
			base.cool(h)
	h.check("host: free", _EndGame.is_free(), _EndGame.state())
	share("free", true)
	var entered: bool = await h.until(func():
		base.cool(h)
		return _EndGame.is_lair_entered(), 90.0)
	var client_pid: String = ""
	for kk in Keepers.getAll():
		if kk != k:
			client_pid = kk.playerId
	h.check("host: the client's keeper entered the lair, recorded once from its word", entered and lair_events == [client_pid], [lair_events, client_pid])
	var fight: bool = await h.until(func(): return _Director.current() == "fight", 12.0)
	h.check("host: the horror woke and the fight started", bool(Data.ofOr("team1.story.awake", false)) and fight, _Director.current())
	share("fight", fight)
	await h.shot("host_end")
	await host_wait_clients_left(h)
