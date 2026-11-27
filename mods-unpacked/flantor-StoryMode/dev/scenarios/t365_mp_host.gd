extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #365: host half of the online check for the chain anchors and the
# end-game state. The host breaks two anchors; the client's keeper drills a
# third (its hits reach the host, which records the break); the host breaks
# the other seven, the last of them the last chain. Checks the host recorded
# all ten, fired the last chain exactly once, and the tentacles are at full
# wake. Pair: t365_mp_client.

const EndGame = preload("res://mods-unpacked/flantor-StoryMode/endgame/end_game.gd")
static var _EndGame = EndGame  # calls go through this: lazy_preload makes const-preload calls slow
const Anchors = preload("res://mods-unpacked/flantor-StoryMode/map/chain_anchors.gd")
static var _Anchors = Anchors  # calls go through this: lazy_preload makes const-preload calls slow
const Ocean = preload("res://mods-unpacked/flantor-StoryMode/map/ocean_tentacles.gd")
static var _Ocean = Ocean  # calls go through this: lazy_preload makes const-preload calls slow
const Base = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t365_anchors.gd")
const TIMEOUT := 480

var last_events: int = 0


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if not await host_start(h):
		return
	var ok: bool = await h.until(func(): return _Anchors.find() != null, 20.0)
	if not h.check("host: the anchors are built", ok):
		return
	var anchors = _Anchors.find()
	var base = Base.new()
	base.anchors = anchors
	base.tents = _Ocean.find()
	base.lava = Level.map.get_node_or_null("StoryLavaField")
	_EndGame.node().last_chain_broken.connect(func(): last_events += 1)
	load("res://mods-unpacked/flantor-StoryMode/dev/boss_dev.gd").give_gear()
	await base.reveal_ocean(h)
	var list: Array = anchors.anchors.duplicate()
	list.sort_custom(func(x, y): return x["centre"].y > y["centre"].y)
	# The client's: the lowest; the host's two: the next two.
	var theirs: Dictionary = list[0]
	var spot: Dictionary = base.stand_by(theirs)
	share("client_anchor", {"id": theirs["id"], "cell": [spot["cell"].x, spot["cell"].y], "dir": [spot["dir"].x, spot["dir"].y]})
	var k = h.keeper()
	k.teleport(list[1]["centre"] + Vector2(-90, -60))
	base.tents.refresh_near()
	h.snap_camera(k)
	share("ready", true)
	await h.wait(2.0)
	for a in [list[1], list[2]]:
		anchors.dev_break(a["id"])
		await h.wait(1.5)
		base.cool(h)
	h.check("host: two chains broken", _EndGame.chains_broken() == 2, _EndGame.state())
	share("two", true)
	await h.shot("host_two")
	# The client's keeper drills its anchor.
	var got: bool = await h.until(func():
		base.cool(h)
		return _EndGame.is_anchor_broken(theirs["id"]), 90.0)
	h.check("host: the client's keeper broke its anchor and the host recorded it", got and _EndGame.chains_broken() == 3, _EndGame.state())
	h.check("host: ... its tiles are gone here too", theirs["cells"].all(func(c): return Level.map.tileData.get_resourcev(c) == Data.TILE_EMPTY))
	share("three", true)
	await h.wait(2.0)
	for a in anchors.anchors:
		if not a["broken"]:
			anchors.dev_break(a["id"])
			await h.wait(0.8)
			base.cool(h)
	await h.wait(1.5)
	h.check("host: all ten recorded, free", _EndGame.chains_broken() == 10 and _EndGame.is_free(), _EndGame.state())
	h.check("host: the last chain fired once", last_events == 1, last_events)
	h.check("host: the tentacles at full wake", _Ocean.chains_broken() == 10, _Ocean.chains_broken())
	share("done", true)
	await h.shot("host_end")
	await host_wait_clients_left(h)
