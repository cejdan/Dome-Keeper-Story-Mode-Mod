extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #231: client half of t231_mp_split_host (the host plays two local keepers).
# This client has one keeper: it sees three, keeps its own heat and toxin at
# zero while the host's second keeper burns, and sees the team's money halve
# once.

const TIMEOUT := 420


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var k2id = await shared(h, "k2", 120.0)
	h.check("the host's keeper 2 is out", k2id != null, k2id)
	h.note("keepers", Keepers.getAll().map(func(k): return [k.playerId, k.peerId, k.deviceId, Keepers.local.has(k)]))
	h.check("three keepers here, one local", Keepers.getAll().size() == 3 and h.local_keepers().size() == 1, Keepers.getAll().size())
	var me = _Story.local_keeper()
	var lava = Level.map.get_node("StoryLavaField")
	var gas = Level.map.get_node("StoryGasField")
	await shared(h, "lava_done", 60.0)
	await h.wait(1.0)
	await h.shot("client_view")
	var money_ok: bool = await h.until(func(): return int(Data.ofOr("team1.inventory.money", 0)) == 500, 10.0)
	h.check("money halved once on the client too", money_ok, Data.ofOr("team1.inventory.money", 0))
	h.check("this keeper stayed cool", lava.heat_of(me) == 0.0, lava.heats)
	h.check("no heat kept for other instances' keepers", lava.heats.keys().all(func(p): return p == me.playerId), lava.heats.keys())
	await h.wait(3.0)
	h.check("this keeper breathed no gas", gas.toxin_of(me) == 0.0, gas.toxins)
	share_client(h)
	await shared(h, "done", 60.0)


func share_client(h) -> void:
	# Clients can't Data.apply; the host only logs that the client got here.
	h.note("client done")


const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
