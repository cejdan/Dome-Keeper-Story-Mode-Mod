extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #242: host half. Changes a story key, the money, the water and the boss state
# exactly as the client comes into sync: on its first frame in LEVEL_STAGE_SYNC
# (the change rides in the big delta of what changed while it loaded) and again
# each frame while the chunker still has more than a frame of a big Data
# message to it to send (those small deltas overtake it, and its older values
# land on top). Then leaves them alone and shares the values the client must
# end up with. The boss director's own 2 s repeat is held off here, so the boss state
# rides on StoryNet's settled resend alone. `-Extra "--noresend"` turns the
# resend off to show the race. Pair: t242_mp_data_resend_client.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const StoryNet = preload("res://mods-unpacked/flantor-StoryMode/net/story_net.gd")
const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const KEY := "team1.story.t242"
const TIMEOUT := 300

var _changes := 0
var _first_sync := -1.0
var _remaining: Array = []
var _stopped := false
var _saw_delta := false


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if _Story.has_user_arg("noresend"):
		StoryNet.resend_on = false
	h.note("resend on", StoryNet.resend_on)
	var stage = Level.stage
	GameWorld.figuredOutMovementInLoadout = true
	var joined: bool = await h.until(func(): return Lobby.members.size() >= 2, 120.0)
	h.check("players joined the lobby", joined, Lobby.members.size())
	if not joined:
		return
	await h.until(func():
		if Level.loadout.keepers.size() < 2:
			return false
		for lk in Level.loadout.keepers:
			if lk.keeper == null:
				return false
		return true, 30.0)
	stage.gameModeSelected("storymode")
	await h.wait(2.0)
	stage.startRun()
	# Watch the client's state and the chunker's queue every frame from here.
	var tree: SceneTree = h.get_tree()
	var watch := func(): _watch(h)
	tree.process_frame.connect(watch)
	tree.process_frame.connect(_hold_repeat)
	var started: bool = await h.until(func(): return Level.stage is LevelStage and Level.stage.get("keeperInputStarted") == true and Level.map != null and Level.map.isMapReady(), 180.0)
	h.check("run started", started)
	if not started:
		return
	h.mute_beats()
	h.disable_waves()
	var synced: bool = await h.until(func(): return _first_sync >= 0.0, 90.0)
	h.check("client reached LEVEL_STAGE_SYNC", synced)
	await h.until(func(): return _stopped and not _in_flight(), 10.0)
	tree.process_frame.disconnect(watch)
	h.check("changed the keys again while a big Data message to the client was in flight", _changes > 1, {"frames changed": _changes, "chunks left each frame": _remaining})
	var want := {"money": Data.of("team1.inventory.money"), "water": Data.of("team1.inventory.water"), "story": Data.of(KEY), "boss": _Director.current()}
	h.note("final values", want)
	await h.wait(4.0)
	h.check("the host's values held", Data.of("team1.inventory.money") == want["money"] and Data.of(KEY) == want["story"] and _Director.current() == want["boss"])
	h.note("resends", StoryNet.resends)
	if StoryNet.resend_on:
		h.check("a settled resend to the client after it reached sync", StoryNet.resends.any(func(r): return r["story"]), StoryNet.resends)
	share("final", want)
	await host_wait_clients_left(h, 120.0)


# The boss director's own repeat of its state, held off all run.
func _hold_repeat() -> void:
	var boss = _Director.instance()
	if boss != null:
		boss._net_repeat = 1.0e9


func _client():
	for c in Network.clients:
		return c
	return null


# Chunks still to send of the chunked Data messages (full syncs and big deltas)
# to the client, the most of any; -1 when none is queued.
func _left() -> int:
	var c = _client()
	if c == null:
		return -1
	var most := -1
	for r in Network.chunker.outgoing_rpcs.values():
		if r.target_peer_id == c.peer_id and (r.request_type == Chunker.ChunkRequestType.DATA_FULL_SYNC or r.request_type == Chunker.ChunkRequestType.DATA_DELTA_SYNC) and not r.is_sent():
			most = maxi(most, r.total_chunks - r.current_chunk_index)
			if r.request_type == Chunker.ChunkRequestType.DATA_DELTA_SYNC:
				_saw_delta = true
	return most


func _in_flight() -> bool:
	return _left() > 0


func _watch(h) -> void:
	var c = _client()
	if _stopped or c == null or c.connection_state != Network.ConnectionState.LEVEL_STAGE_SYNC or Level.map == null:
		return
	if _first_sync < 0.0:
		_first_sync = h.now()
	var left: int = _left()
	_remaining.append(left)
	# Until the big delta of what changed while the client loaded is queued
	# (these changes ride in it), then while more than a frame's worth of it is
	# still to go: the small delta each change makes goes out before its last
	# chunk.
	if left <= Chunker.CHUNKS_PER_FRAME and (_saw_delta or _remaining.size() > 120):
		_stopped = true
		return
	_changes += 1
	Data.apply("team1.inventory.money", 4200 + _changes)
	Data.apply("team1.inventory.water", 40 + _changes)
	Data.apply(KEY, "v%d" % _changes)
	Data.apply(Director.STATE, "t242_%d" % _changes)
