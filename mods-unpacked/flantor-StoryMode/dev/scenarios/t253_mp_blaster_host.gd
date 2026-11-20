extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #253, host half: both keepers get the Suit Blaster while a client watches,
# and the client must log no script error or unknown Data key for it
# (t253_mp_blaster_client; dev/log_scan.ps1 counts them).
#   default:          Story Mode's shop: each keeper's Suit Blaster entry is
#                     bought (gamemode/Storymode.gd grants it to the buyer, #265)
#   --devgear:        the boss dev gear (dev/boss_dev.gd: max drill, jetpack,
#                     Laser IV, ... in one frame), then the client's keeper's
#   --vanilla:        a Relic Hunt run, each keeper picking it as a gadget
#                     (LevelStage.addGadgetUpgrade's grant)
#   --early:          (with any of them) given the moment the client is in sync
#   --bigdelta:       (with any of them) right behind a chunked Data delta
#   --give=<gadget>:  (#261) another gadget instead, given straight
#                     (serverAddUpgrade, in either mode): probe (each
#                     keeper's), drill (the team's Mine Driller, whose drill
#                     reads its keys every frame), ...; the client checks
#                     every key of it was there when it came and stayed
#   --onedelta:       (#268) a 2 KB Data key changes in the same tick, so the
#                     gadget's keys go out in one delta over the chunk size
#                     (as story.dev.share did in t234's Mine Driller)
#   --fullsync:       (#268) a full Data sync to the client is on its way
#                     when the gadget is given; landing, it replaces all of
#                     the client's Data
#   --heldchunker:    (#261) the chunker holds a small delta whole behind a
#                     queued one, as before #261, and chunks a big one whole,
#                     to show the keys come late
# Pair: t253_mp_blaster_client.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
const OrderedChunker = preload("res://mods-unpacked/flantor-StoryMode/net/ordered_chunker.gd")
const TIMEOUT := 300


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	var vanilla: bool = Story.has_user_arg("vanilla")
	if not await host_start(h, 2, "relichunt" if vanilla else "storymode"):
		return
	# `--early`: right after the client is in sync, as the boss dev commands
	# do in t230_mp_boss_*: the host's full Data sync to it is still on its
	# way (chunked), and the gadget's RPC overtakes the Data behind it.
	if not Story.has_user_arg("early"):
		await h.wait(3.0)
	# `--bigdelta`: a 20 KB Data key first, so the next delta is sent in chunks
	# and the Suit Blaster's own delta waits behind it every time.
	if Story.has_user_arg("bigdelta"):
		Data.apply("story.dev.pad", "x".repeat(20000))
		Data.synchronizer.manual_tick()
	var keepers: Array = Keepers.getAll()
	var give: String = Story.user_arg("give", "suitblaster")
	var path: String = "vanilla gadget" if vanilla else ("dev gear" if Story.has_user_arg("devgear") else "shop")
	if give != "suitblaster":
		path = "given " + give
	h.note("giving", [give, path])
	var ahead0: int = OrderedChunker.sent_ahead
	# Random letters: zstd shrinks them little, so a full sync grows too.
	if Story.has_user_arg("onedelta"):
		var pad := ""
		for i in 2400:
			pad += char(65 + randi() % 58)
		Data.apply("story.dev.pad", pad)
	if Story.has_user_arg("fullsync"):
		for c in Network.clients:
			c.full_data_sync()
	# A keeper gadget is each keeper's (playerId.<id>), any other the team's.
	var per_keeper: bool = Data.gadgets.get(give, {}).get("scenes", {}).has("keepersuit")
	var ids: Array = keepers.map(func(k): return k.playerId + "." + give) if per_keeper else ["team1." + give]
	if give != "suitblaster":
		if per_keeper:
			for k in keepers:
				GameWorld.serverAddUpgrade(k.playerId + "." + give, k.teamId)
		else:
			GameWorld.serverAddUpgrade(give, "team1")
	elif vanilla:
		for k in keepers:
			GameWorld.serverAddUpgrade(k.playerId + ".suitblaster", k.teamId)
	elif Story.has_user_arg("devgear"):
		var given: Array = load(Story.MOD_DIR + "dev/boss_dev.gd").give_gear()
		h.note("dev gear", given)
		for k in keepers:
			if not GameWorld.boughtUpgrades.has(k.playerId + ".suitblaster"):
				GameWorld.serverAddUpgrade(k.playerId + ".suitblaster", k.teamId)
	else:
		Data.apply("team1.inventory.money", 5000)
		await h.wait(0.5)
		# Each keeper's own entry since #265 (it grants the buyer's blaster only).
		for k in keepers:
			GameWorld.buyUpgrade(k.playerId + ".storysuitblaster", "team1", k.playerId)
	var all: bool = await h.until(func(): return ids.all(func(id): return GameWorld.boughtUpgrades.has(id)), 10.0)
	h.check("%s has the %s (%s)" % ["every keeper" if per_keeper else "the team", give, path], all, ids.map(func(id): return [id, GameWorld.boughtUpgrades.has(id)]))
	var ahead: int = OrderedChunker.sent_ahead - ahead0
	h.note("Data keys sent ahead of queued Data (#261)", ahead)
	await h.wait(4.0)
	# The gadget's own Data keys (its property changes, per team and player).
	var keys: Array = []
	for key in Data.values:
		if String(key).contains("." + give + "."):
			keys.append(key)
	h.note("%s keys" % give, keys)
	share("given", {"path": path, "give": give, "ids": ids, "keys": keys, "players": keepers.map(func(k): return k.playerId)})
	await h.shot("host_blaster")
	await host_wait_clients_left(h, 90.0)
