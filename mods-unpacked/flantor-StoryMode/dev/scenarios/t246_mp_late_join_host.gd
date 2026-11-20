extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #246: host half. Three players start the run; the third leaves and joins
# again in a new process (the only way into a run under way: the keeper choice
# offers the keeper of a player who left). From the moment it connects until
# its big messages (stage data, map, full Data) have all gone out, the host
# changes Story Mode keys every frame: the money, a story key and the boss
# state, each to a counter `n` that only goes up; every BURST_EVERY frames
# many other keys change with them, so that frame's delta is chunked (see
# _burst). `-Extra "--vanillachunker"` runs without net/ordered_chunker.gd. Logs which chunked messages
# were queued to whom each frame and the wall-clock time each `n` was set
# (user://t246_host.json), so the watching client (the second player, which
# stays) can tell lag from flicker (a value going back). The boss director's
# own 2 s repeat is held off. Run with:
#   mp_playtest.ps1 t246_mp_late_join_host t246_mp_late_join_watcher -Client2 t246_mp_late_join_leaver -Rejoin t246_mp_late_join_rejoin

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
const StoryNet = preload("res://mods-unpacked/flantor-StoryMode/net/story_net.gd")
const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
const KEY := "team1.story.t246"
const LOG := "user://t246_host.json"
const TIMEOUT := 420

var _n := 0
var _on := false
var _sets: Array = []        # [unix msec, n]
var _queue: Array = []       # per frame: [unix msec, n, chunks queued to the watcher (data / other), to the joiner (all)]
var _watcher := 0
var _joiner := 0
# Every BURST_EVERY frames while the player joins, BURST_KEYS other keys change
# at once: a Data delta too big to go whole (over 900 bytes), so it is chunked
# and queues behind the joiner's map, as a busy moment in play would (many
# keys in one network tick). `--noburst` leaves them out.
var _burst := true
const BURST_EVERY := 15
const BURST_KEYS := 50
var _bursts := 0


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if not await host_start(h, 3):
		return
	var tree: SceneTree = h.get_tree()
	tree.process_frame.connect(_hold_repeat)
	await h.wait(3.0)
	# The watcher is the client that joined first (lowest lobby order).
	_watcher = Network.clients[0].peer_id
	share("leave", Network.clients[1].peer_id)
	var left: bool = await h.until(func(): return Network.clients.size() == 1, 60.0)
	h.check("the third player left", left, Network.clients.size())
	if not left:
		return
	h.check("the watcher stayed", Network.clients[0].peer_id == _watcher)
	_bump(h)    # n = 1 before the join
	var back: bool = await h.until(func(): return Network.clients.size() == 2, 120.0)
	h.check("the third player is connecting again", back)
	if not back:
		return
	for c in Network.clients:
		if c.peer_id != _watcher:
			_joiner = c.peer_id
	var t0: float = h.now()
	_burst = not Story.has_user_arg("noburst")
	h.note("bursts", _burst)
	_on = true
	var each := func(): _frame(h)
	tree.process_frame.connect(each)
	var in_sync := func():
		for c in Network.clients:
			if c.peer_id == _joiner:
				return c.connection_state == Network.ConnectionState.LEVEL_STAGE_SYNC
		return false
	var synced: bool = await h.until(in_sync, 120.0)
	h.check("the joiner reached LEVEL_STAGE_SYNC", synced, h.now() - t0)
	# A moment more of bursts, then until nothing chunked is left for the joiner.
	await h.wait(2.0)
	_burst = false
	await h.until(func(): return _queued(_joiner) + _queued(_watcher) == 0, 20.0)
	await h.wait(1.0)
	_on = false
	tree.process_frame.disconnect(each)
	h.note("changed every frame", {"frames": _n, "seconds": h.now() - t0, "bursts": _bursts})
	var watched: Array = _queue.filter(func(q): return q[2] > 0)
	h.note("frames with a chunked Data message to the watcher queued", watched.size())
	var f := FileAccess.open(LOG, FileAccess.WRITE)
	f.store_string(JSON.stringify({"sets": _sets, "queue": _queue, "watcher": _watcher, "joiner": _joiner}))
	f.close()
	await h.wait(1.0)
	var want := {"n": _n, "money": Data.of("team1.inventory.money"), "story": Data.of(KEY), "boss": Director.current()}
	h.note("final values", want)
	h.note("resends", StoryNet.resends)
	share("final", want)
	await host_wait_clients_left(h, 120.0)


func _bump(h) -> void:
	_n += 1
	Data.apply("team1.inventory.money", 5000 + _n)
	Data.apply(KEY, "v%d" % _n)
	Data.apply(Director.STATE, "t246_%d" % _n)
	_sets.append([int(Time.get_unix_time_from_system() * 1000.0), _n])


func _frame(h) -> void:
	if not _on:
		return
	if _burst and _n % BURST_EVERY == 0:
		_bursts += 1
		for i in BURST_KEYS:
			Data.apply("story.dev.burst.%d" % i, "burst %d of the late-join test" % _n)
	_bump(h)
	var data_w := 0
	var other_w := 0
	for r in Network.chunker.outgoing_rpcs.values():
		if r.target_peer_id == _watcher and not r.is_sent():
			if r.request_type == Chunker.ChunkRequestType.DATA_FULL_SYNC or r.request_type == Chunker.ChunkRequestType.DATA_DELTA_SYNC:
				data_w += r.total_chunks - r.current_chunk_index
			else:
				other_w += r.total_chunks - r.current_chunk_index
	_queue.append([int(Time.get_unix_time_from_system() * 1000.0), _n, data_w, other_w, _queued(_joiner)])


func _queued(peer: int) -> int:
	var n := 0
	for r in Network.chunker.outgoing_rpcs.values():
		if r.target_peer_id == peer and not r.is_sent():
			n += r.total_chunks - r.current_chunk_index
	return n


func _hold_repeat() -> void:
	var boss = Director.instance()
	if boss != null:
		boss._net_repeat = 1.0e9
