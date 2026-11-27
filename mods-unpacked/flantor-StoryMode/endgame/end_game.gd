extends Node

# End game 2.0 (#363): the run's end-game state, in one place (#365). Every
# later End game ticket reads it here: the lair seal (#366), the last-chain
# cutscene (#367), the ship (#368) and the rising lava (#369).
#
# The state is the set of chain anchors broken (map/chain_anchors.gd), a
# bitmask in Data (ANCHORS_KEY), and the moment the last one broke
# (FREED_KEY). Both are written only by the host, saved with the run, and
# reach clients with the rest of Data. Everything else is derived from them:
# the chains broken (popcount), the ocean tentacles' wake (OceanTentacles
# keeps its own copy of the count in Data for its wave, written from here)
# and whether the horror is unbound.
#
#   EndGame.chains_broken() -> int        0..10
#   EndGame.chains_total() -> int         10
#   EndGame.is_anchor_broken(id) -> bool  id 0..9 (map meta "story_anchors")
#   EndGame.is_free() -> bool             the last chain has broken (any peer)
#   EndGame.freed_at() -> float           GameWorld.runTime when it broke, -1 before
#   EndGame.when_free(cb)                 cb(live: bool), exactly once for this run:
#                                         live = true at the moment it breaks,
#                                         false at once (deferred) if it already
#                                         had (a loaded save, a late join)
#   EndGame.node().chain_broken(id, n)    signal: a chain just broke (live only)
#   EndGame.node().last_chain_broken()    signal: the last chain just broke (live
#                                         only, once per run, every peer)
#
# The lair (#366): a keeper going through the opened seal into the boss
# chamber (endgame/lair_seal.gd reports it; the host records it here). It
# wakes the horror (beats/awakening.gd -> the fight) and stops the rising
# lava (#369). Only after the last chain: before it the host ignores it.
#   EndGame.is_lair_entered() -> bool     a keeper has entered the lair (any peer)
#   EndGame.lair_entered_at() -> float    GameWorld.runTime it happened, -1 before
#   EndGame.when_lair_entered(cb)         cb(live: bool), once for this run, as when_free
#   EndGame.node().lair_entered(pid)      signal: the first keeper just entered
#                                         (live only, once per run, every peer)
#   EndGame.record_lair_entered(pid)      host only; the seal calls it
#   EndGame.dev_free()                    host, dev and playtests: every chain
#                                         broken quietly, as a save made after
#                                         the last chain loads (no live moment;
#                                         when_free callbacks told not live)
#
# Online: the host records each break (a client's keeper breaking an anchor
# reaches the host as tile hits, as every tile does) and tells every client
# the live moments by RPC. The last chain's RPC is the client's "live"
# moment; a client that joins or loads later is told "already free" instead,
# so the live moment never plays twice. The node sits under the mod's main
# node, at the same path on every peer.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const TentData = preload("res://mods-unpacked/flantor-StoryMode/data/tentacles.gd")
static var _TentData = TentData  # calls go through this: lazy_preload makes const-preload calls slow
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
static var _StoryBeats = StoryBeats  # calls go through this: lazy_preload makes const-preload calls slow

const NAME := "StoryEndGame"
const ANCHORS_KEY := "team1.story.anchorsbroken"   # int: bit `id` set = anchor `id` broken
const FREED_KEY := "team1.story.lastchain"          # float: GameWorld.runTime of the last chain
const LAIR_KEY := "team1.story.lairentered"         # float: GameWorld.runTime a keeper first entered the lair (#366)
# Keys of the Unobtainium seal (#95, #101) that older saves carry; the host
# drops them when such a run loads (gamemode/legacy_saves.gd).
const LEGACY_KEYS := ["team1.story.unobmined", "team1.story.unobcells"]

signal chain_broken(anchor_id: int, chains: int)
signal last_chain_broken()
signal lair_entered(player_id: String)

static var _inst = null

# Every live moment so far, for playtests: [{"what", "id", "chains", "seed", "live"}].
static var events: Array = []

var _heard_seed: int = -1        # client: the run the host said is free
var _waiters: Array = []         # [seed, Callable]
var _told: Dictionary = {}       # host: peer id -> seed it was told "free" for
var _heard_lair: int = -1        # client: the run the host said a keeper entered the lair
var _lair_waiters: Array = []    # [seed, Callable]
var _told_lair: Dictionary = {}  # host: peer id -> seed it was told about the lair


func _enter_tree() -> void:
	_inst = self


static func node():
	return _inst


# --- reading (any peer) ------------------------------------------------------------

static func anchors_broken() -> int:
	return int(Data.ofOr(ANCHORS_KEY, 0))


static func is_anchor_broken(id: int) -> bool:
	return (anchors_broken() >> id) & 1 == 1


static func chains_total() -> int:
	return _TentData.CHAINS


static func chains_broken() -> int:
	var m: int = anchors_broken()
	var n: int = 0
	while m != 0:
		n += m & 1
		m >>= 1
	return mini(n, chains_total())


static func freed_at() -> float:
	return float(Data.ofOr(FREED_KEY, -1.0))


static func is_free() -> bool:
	if freed_at() >= 0.0:
		return true
	return _inst != null and _inst._heard_seed == Level.levelSeed


# `cb(live: bool)` once for this run: when the last chain breaks (live), or
# right away (deferred, not live) if it already has on this peer.
static func when_free(cb: Callable) -> void:
	if is_free():
		cb.call_deferred(false)
	elif _inst != null:
		_inst._waiters.append([Level.levelSeed, cb])


static func lair_entered_at() -> float:
	return float(Data.ofOr(LAIR_KEY, -1.0))


static func is_lair_entered() -> bool:
	if lair_entered_at() >= 0.0:
		return true
	return _inst != null and _inst._heard_lair == Level.levelSeed


# `cb(live: bool)` once for this run: when the first keeper enters the lair
# (live), or right away (deferred, not live) if one already has on this peer.
static func when_lair_entered(cb: Callable) -> void:
	if is_lair_entered():
		cb.call_deferred(false)
	elif _inst != null:
		_inst._lair_waiters.append([Level.levelSeed, cb])


# Everything above, for logs and playtests.
static func state() -> Dictionary:
	return {"anchors": anchors_broken(), "chains": chains_broken(), "free": is_free(), "freed_at": freed_at(),
		"lair": is_lair_entered(), "lair_at": lair_entered_at()}


# --- writing (host) ----------------------------------------------------------------

# The host: anchor `id` just broke. Records it, wakes the tentacles, fires the
# chain's beat trigger and, on the tenth, the last chain. Safe to call twice.
static func record_break(id: int) -> void:
	if Network.is_client() or id < 0 or id >= chains_total():
		return
	if is_anchor_broken(id):
		return
	Data.apply(ANCHORS_KEY, anchors_broken() | (1 << id))
	var n: int = chains_broken()
	_sync_tentacles()
	ModLoaderLog.info("End game: anchor %d broken, %d of %d chains" % [id, n, chains_total()], _Story.LOG)
	if _inst != null:
		_inst._live_chain(id, n)
		_inst._send_chain(id, n)
	# Each chain has a beat trigger, as each unobtainium piece had (#95); no
	# beat is on any of them today (the user cut those beats in #285).
	_StoryBeats.trigger("chain:%d" % n)
	if n >= chains_total() and freed_at() < 0.0:
		Data.apply(FREED_KEY, GameWorld.runTime)
		ModLoaderLog.info("End game: the last chain is broken at %.1f s" % GameWorld.runTime, _Story.LOG)
		if _inst != null:
			_inst._live_free()
			_inst._send_free_all()


# The host: keeper `pid` went through the open seal into the lair. The first
# one records it, wakes the horror and tells everyone. Before the last chain
# the seal is shut, so a keeper there came by a dev route: ignored. Returns
# whether this call recorded it.
static func record_lair_entered(pid: String) -> bool:
	if Network.is_client() or is_lair_entered():
		return false
	if not is_free():
		ModLoaderLog.info("End game: %s is in the lair before the last chain; ignored" % pid, _Story.LOG)
		return false
	Data.apply(LAIR_KEY, GameWorld.runTime)
	ModLoaderLog.info("End game: %s entered the lair at %.1f s" % [pid, GameWorld.runTime], _Story.LOG)
	if _inst != null:
		_inst._live_lair(pid)
		_inst._send_lair_all(pid)
	# The horror wakes: its beat, then the fight (boss/boss_director.gd).
	load(_Story.MOD_DIR + "beats/awakening.gd").wake()
	return true


# Dev and playtests (host): every chain broken, quietly, the way a save made
# after the last chain loads: no live moment, no beat; when_free callbacks
# are told "not live". map/chain_anchors.gd dev_free_all() also clears the
# stones (`--free`, `--boss`).
static func dev_free() -> void:
	if Network.is_client() or is_free():
		return
	Data.apply(ANCHORS_KEY, (1 << chains_total()) - 1)
	Data.apply(FREED_KEY, GameWorld.runTime)
	_sync_tentacles()
	ModLoaderLog.info("End game: dev: every chain broken quietly", _Story.LOG)
	events.append({"what": "dev_free", "seed": Level.levelSeed, "live": false})
	if _inst != null:
		_inst._call_waiters(false)


# The tentacles' wake follows the chains broken (host; after a load too).
static func _sync_tentacles() -> void:
	load(_Story.MOD_DIR + "map/ocean_tentacles.gd").set_chains_broken(chains_broken())


# --- live moments ------------------------------------------------------------------

func _live_chain(id: int, n: int) -> void:
	events.append({"what": "chain", "id": id, "chains": n, "seed": Level.levelSeed, "live": true})
	chain_broken.emit(id, n)


func _live_free() -> void:
	events.append({"what": "last_chain", "seed": Level.levelSeed, "live": true})
	last_chain_broken.emit()
	_call_waiters(true)


func _live_lair(pid: String) -> void:
	events.append({"what": "lair", "pid": pid, "seed": Level.levelSeed, "live": true})
	lair_entered.emit(pid)
	_call_lair_waiters(true)


func _call_lair_waiters(live: bool) -> void:
	var now: Array = _lair_waiters.filter(func(w): return int(w[0]) == Level.levelSeed)
	_lair_waiters.clear()
	for w in now:
		var cb: Callable = w[1]
		if cb.is_valid():
			cb.call(live)


func _call_waiters(live: bool) -> void:
	var now: Array = _waiters.filter(func(w): return int(w[0]) == Level.levelSeed)
	_waiters.clear()
	for w in now:
		var cb: Callable = w[1]
		if cb.is_valid():
			cb.call(live)


# --- online -----------------------------------------------------------------------

func _process(_delta: float) -> void:
	if Network.is_offline_mode() or Network.is_client() or not _Story.is_story():
		return
	if Level.map == null or not is_instance_valid(Level.map) or freed_at() < 0.0:
		return
	# A client that joined (or rejoined) after the last chain is told it is free.
	for c in Network.clients:
		if c.connection_state != Network.ConnectionState.LEVEL_STAGE_SYNC:
			continue
		if int(_told.get(c.peer_id, -1)) == Level.levelSeed:
			continue
		_told[c.peer_id] = Level.levelSeed
		rpc_id(c.peer_id, "_client_free", Level.levelSeed, false)
	# And, after that, that a keeper is already in the lair.
	if lair_entered_at() < 0.0:
		return
	for c in Network.clients:
		if c.connection_state != Network.ConnectionState.LEVEL_STAGE_SYNC:
			continue
		if int(_told_lair.get(c.peer_id, -1)) == Level.levelSeed or int(_told.get(c.peer_id, -1)) != Level.levelSeed:
			continue
		_told_lair[c.peer_id] = Level.levelSeed
		rpc_id(c.peer_id, "_client_lair", Level.levelSeed, "", false)


func _send_lair_all(pid: String) -> void:
	if Network.is_offline_mode():
		return
	for c in Network.clients:
		if c.connection_state == Network.ConnectionState.LEVEL_STAGE_SYNC:
			_told_lair[c.peer_id] = Level.levelSeed
			rpc_id(c.peer_id, "_client_lair", Level.levelSeed, pid, true)


func _send_chain(id: int, n: int) -> void:
	if Network.is_offline_mode():
		return
	for c in Network.clients:
		if c.connection_state == Network.ConnectionState.LEVEL_STAGE_SYNC:
			rpc_id(c.peer_id, "_client_chain", Level.levelSeed, id, n)


func _send_free_all() -> void:
	if Network.is_offline_mode():
		return
	for c in Network.clients:
		if c.connection_state == Network.ConnectionState.LEVEL_STAGE_SYNC:
			_told[c.peer_id] = Level.levelSeed
			rpc_id(c.peer_id, "_client_free", Level.levelSeed, true)


@rpc("authority", "call_remote", "reliable")
func _client_chain(seed: int, id: int, n: int) -> void:
	if seed != Level.levelSeed:
		return
	_live_chain(id, n)


@rpc("authority", "call_remote", "reliable")
func _client_free(seed: int, live: bool) -> void:
	if seed != Level.levelSeed or _heard_seed == seed:
		return
	_heard_seed = seed
	if live:
		ModLoaderLog.info("End game: the host's last chain is broken", _Story.LOG)
		_live_free()
	else:
		events.append({"what": "told_free", "seed": seed, "live": false})
		_call_waiters(false)


@rpc("authority", "call_remote", "reliable")
func _client_lair(seed: int, pid: String, live: bool) -> void:
	if seed != Level.levelSeed or _heard_lair == seed:
		return
	_heard_lair = seed
	if live:
		ModLoaderLog.info("End game: the host says %s entered the lair" % pid, _Story.LOG)
		_live_lair(pid)
	else:
		events.append({"what": "told_lair", "seed": seed, "live": false})
		_call_lair_waiters(false)
