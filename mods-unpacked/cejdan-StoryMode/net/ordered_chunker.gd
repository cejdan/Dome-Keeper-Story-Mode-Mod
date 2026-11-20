extends "res://systems/network/Chunker.gd"

# Vanilla's Chunker sends a message under MAX_CHUNK_SIZE at once and queues a
# bigger one, so a small Data delta could overtake a big one and be undone by
# its older values when it landed (#246). Here a Data message to a peer with
# Data queued waits behind it, except a delta's keys no queued message holds:
# those go at once (#261), in pieces under the chunk size when the delta is big
# (#268), so a new gadget's keys still beat the RPC that adds it. Put on
# Network's chunker node by mod_main.gd (set_script, so it keeps its RPC path).

const StoryNet = preload("res://mods-unpacked/cejdan-StoryMode/net/story_net.gd")

const BATCH := 700  # bytes of Data values per delta sent at once: whole under MAX_CHUNK_SIZE

static var held := 0    # small Data messages queued behind a big one (playtests)
static var sent_ahead := 0  # keys of such deltas sent at once, no queued message holding them (#261)
static var restored := 0    # client: keys put back after a full sync landed (#268, playtests)
# A delta's keys that no queued Data message to the peer holds go at once
# (#261, _send_split); off (`--heldchunker`), a small delta waits whole as in
# #246 and a big one is chunked whole as in vanilla.
static var split_on := true
var _keys_cache: Dictionary = {}  # request id -> the Data keys it carries
var _pinned: Dictionary = {}  # client: full sync request id -> Data sent ahead of it (#268)
var _landing := -1  # client: the request id receive() is finishing
static var stripped := 0  # Data messages the host's blobs were taken out of (#247)
# `--datasizes` (editor, #247): every Data message sent, by size; see tally_text.
static var tally_on := false
static var tally: Dictionary = {"messages": 0, "bytes": 0, "max": 0, "chunked": 0, "under_300": 0, "under_900": 0}


func send(target_peer_id: int, request_type: ChunkRequestType, callable: Callable) -> void:
	if not StoryNet.is_data(request_type):
		super.send(target_peer_id, request_type, callable)
		return
	if multiplayer.is_server():
		callable = _strip(request_type, callable)
		if callable.is_null():
			return
	var data: PackedByteArray = var_to_bytes(callable.get_bound_arguments())
	var small: bool = data.size() < MAX_CHUNK_SIZE
	if tally_on:
		_count(data.size())
	var queued: bool = _data_queued(target_peer_id)
	if request_type == ChunkRequestType.DATA_DELTA_SYNC and split_on and (queued or not small) and _send_split(target_peer_id, callable):
		return
	if queued and small:
		_queue(target_peer_id, request_type, data)
		held += 1
		return
	super.send(target_peer_id, request_type, callable)


func _count(n: int) -> void:
	tally["messages"] += 1
	tally["bytes"] += n
	tally["max"] = maxi(int(tally["max"]), n)
	if n >= MAX_CHUNK_SIZE:
		tally["chunked"] += 1
	elif n < 300:
		tally["under_300"] += 1
	else:
		tally["under_900"] += 1


# A Data delta to a peer with Data queued (#261), or too big to go whole
# (#268): the keys no queued message to it holds go now, in messages small
# enough to go whole; the rest (and any value too big for one) waits. Keys sent
# ahead of a queued full sync go in _ahead, to be put back once it has landed.
# False when nothing could go now.
func _send_split(peer: int, callable: Callable) -> bool:
	var args: Array = callable.get_bound_arguments()
	var vals: Dictionary = StoryNet.data_values(ChunkRequestType.DATA_DELTA_SYNC, args)
	if vals.is_empty():
		return false
	var queued_keys: Dictionary = {}
	var fulls: Array = []
	for id in outgoing_rpcs:
		var r: OutgoingRPC = outgoing_rpcs[id]
		if r.target_peer_id != peer or r.is_sent() or not StoryNet.is_data(r.request_type):
			continue
		if r.request_type == ChunkRequestType.DATA_FULL_SYNC:
			fulls.append(id)
		queued_keys.merge(_keys_of(r))
	var batches: Array = []
	var batch: Dictionary = {}
	var size := 0
	var later: Dictionary = {}
	for k in vals:
		var n: int = var_to_bytes(k).size() + var_to_bytes(vals[k]).size()
		if queued_keys.has(k) or n > BATCH:
			later[k] = vals[k]
			continue
		if size + n > BATCH and not batch.is_empty():
			batches.append(batch)
			batch = {}
			size = 0
		batch[k] = vals[k]
		size += n
	if not batch.is_empty():
		batches.append(batch)
	if batches.is_empty():
		return false
	for b: Dictionary in batches:
		if fulls.is_empty():
			_rebind(callable, args, b).rpc_id(peer)
		else:
			_ahead.rpc_id(peer, fulls, args[0], var_to_bytes(b))
		sent_ahead += b.size()
	if not later.is_empty():
		var rest: Callable = _rebind(callable, args, later)
		var data: PackedByteArray = var_to_bytes(rest.get_bound_arguments())
		if data.size() < MAX_CHUNK_SIZE:
			_queue(peer, ChunkRequestType.DATA_DELTA_SYNC, data)
			held += 1
		else:
			super.send(peer, ChunkRequestType.DATA_DELTA_SYNC, rest)
	return true


# Host -> client: a delta's keys sent ahead of the full syncs `fulls` (request
# ids) still on their way (#268). Applied as vanilla's delta, and put back as
# each of those lands (receive), since a full sync replaces all of Data. Later
# changes to these keys come the same way while one is queued (no queued
# message holds them), so the newest is what goes back in.
@rpc("authority", "call_remote", "reliable")
func _ahead(fulls: Array, tick: int, bytes: PackedByteArray) -> void:
	Data.synchronizer.remote_data_call.call(tick, bytes)
	var vals = bytes_to_var(bytes)
	if not vals is Dictionary:
		return
	for id in fulls:
		if not _pinned.has(id):
			_pinned[id] = {}
		_pinned[id].merge(vals, true)


@rpc("reliable", "any_peer")
func receive(request_id: int, request_type: int, chunk_index: int, total_chunks: int, chunk: PackedByteArray) -> void:
	_landing = request_id
	super(request_id, request_type, chunk_index, total_chunks, chunk)
	_landing = -1


# On Data.full_sync_received, connected in mod_main.modInit before any stage
# listens: the keys sent ahead of this full sync go back in before a stage
# reads Data. Silently: listeners last heard of these values.
func restore_ahead() -> void:
	var vals = _pinned.get(_landing)
	if vals == null:
		return
	_pinned.erase(_landing)
	Data.values.merge(vals, true)
	restored += vals.size()


func reset() -> void:
	super()
	_keys_cache.clear()
	_pinned.clear()
	StoryNet.reset()


func _rebind(callable: Callable, args: Array, vals: Dictionary) -> Callable:
	var a: Array = args.duplicate()
	a[-1] = var_to_bytes(vals)
	return Callable(callable.get_object(), callable.get_method()).bindv(a)


func _queue(peer: int, request_type: ChunkRequestType, data: PackedByteArray) -> void:
	var chunks: Array[PackedByteArray] = [data]
	var id: int = _get_next_request_id()
	outgoing_rpcs[id] = OutgoingRPC.new(id, request_type, peer, chunks)


# The Data keys a queued message carries, read once per message.
func _keys_of(r: OutgoingRPC) -> Dictionary:
	if not _keys_cache.has(r.request_id):
		var keys: Dictionary = {}
		for k in StoryNet.queued_values(r):
			keys[k] = true
		_keys_cache[r.request_id] = keys
	return _keys_cache[r.request_id]


# A request to a peer that has left is dropped: vanilla keeps sending its
# chunks, each one an "Attempt to call RPC with unknown peer ID" error (#249).
func _process(delta: float) -> void:
	if not outgoing_rpcs.is_empty() and multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		var peers: PackedInt32Array = multiplayer.get_peers()
		var me: int = multiplayer.get_unique_id()
		for id in outgoing_rpcs.keys():
			var to: int = outgoing_rpcs[id].target_peer_id
			if to != me and not peers.has(to):
				outgoing_rpcs.erase(id)
	super(delta)
	for id in _keys_cache.keys():
		if not outgoing_rpcs.has(id):
			_keys_cache.erase(id)


# A big Data message from the host without StoryNet.NEVER_SENT (#247): the lava
# and gas save blobs (tens of KB; a loaded save puts them back into Data, and a
# full sync is all of Data) and the old map facts key. Only messages over the
# chunk size are opened: a small one can't hold a blob. Returns a null Callable
# for a delta left empty.
func _strip(request_type: ChunkRequestType, callable: Callable) -> Callable:
	var args: Array = callable.get_bound_arguments()
	if args.size() < 2 or not args[-1] is PackedByteArray or (args[-1] as PackedByteArray).size() < MAX_CHUNK_SIZE:
		return callable
	var full: bool = request_type == ChunkRequestType.DATA_FULL_SYNC
	var vals: Dictionary = StoryNet.data_values(request_type, args)
	var hit := false
	for k: String in StoryNet.NEVER_SENT:
		if vals.has(k):
			vals.erase(k)
			hit = true
	if not hit:
		return callable
	stripped += 1
	if vals.is_empty() and not full:
		return Callable()
	var out: PackedByteArray = var_to_bytes(vals)
	if full:
		args[-2] = out.size()
		args[-1] = out.compress(FileAccess.CompressionMode.COMPRESSION_ZSTD)
	else:
		args[-1] = out
	return Callable(callable.get_object(), callable.get_method()).bindv(args)


func _data_queued(peer: int) -> bool:
	for r in outgoing_rpcs.values():
		if r.target_peer_id == peer and not r.is_sent() and StoryNet.is_data(r.request_type):
			return true
	return false
