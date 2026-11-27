extends Node

# Story Mode in online multiplayer (#222): the run's setup that only the host
# does and vanilla's netcode doesn't carry (#225). The map generator's facts go
# to every client in small RPCs (_host_meta, #247; readers wait for
# map_meta_ready()); a client applies Story Mode's prices and iron drop itself;
# Data that went stale behind a big message is sent again (#242,
# _host_resend). It also relays the lava, gas and tile breaks the host runs.
# Lives under the mod's main node, the same path on every peer.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const Prices = preload("res://mods-unpacked/flantor-StoryMode/data/prices.gd")
static var _Prices = Prices  # calls go through this: lazy_preload makes const-preload calls slow
const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
static var _Minerals = Minerals  # calls go through this: lazy_preload makes const-preload calls slow

# The map facts' Data key before #247: dropped from Data and never sent.
const MAP_META := "story.mapmeta"
# Set on a client's map data once the host's meta is on it.
const SYNCED := "story_meta_synced"
# Map-data meta that stays on the host: the seed rides in saves (#116), the rest
# are generator reports for playtests.
const LOCAL_ONLY := ["story_seed"]

# The settled resend (#242): see _host_resend.
const RESEND_PREFIXES := ["team1.story.", "story.", "team1.inventory.", "team1.suit."]
# Per-keeper Story Mode keys (#265): <playerId> + one of these (player2.suit.heatshield).
const RESEND_PLAYER_PARTS := [".suit."]
# The host's own save blobs (save_blob): never sent.
const HOST_ONLY := ["story.lava", "story.gas"]
# Keys net/ordered_chunker.gd takes out of every big Data message to a client
# (#247): the save blobs, which a loaded save puts back into Data, and the old
# map facts key.
const NEVER_SENT := ["story.lava", "story.gas", MAP_META]
const META_PART := 700         # bytes of compressed map facts per RPC: under the chunker's 900
const RESEND_SETTLE := 1.0     # seconds after the last chunked Data message to a peer left
const RESEND_BATCH := 700      # bytes per message: under the chunker's 900, so sent whole

var _client_story := false     # a client's prices and drops are Story Mode's
# The map facts (#247): the host's, compressed, for the run with seed _meta_seed,
# and which seed each client has had; a client's parts as they arrive, and the
# facts once whole.
var _meta_seed := -1
var _meta_size := 0
var _meta_bytes := PackedByteArray()
var _meta_sent: Dictionary = {}
var _meta_in_seed := -1
var _meta_parts: Dictionary = {}
var _meta_text := ""
var _meta_text_seed := -1

# peer id -> {"vals": key -> value the chunked Data messages to it carry,
# "full": one of them was a full sync, "story": it reached LEVEL_STAGE_SYNC,
# "out": msec one was last seen in flight}
var _resend_wait: Dictionary = {}
var _resend_read: Dictionary = {}   # chunker request ids already read
var _resend_synced: Dictionary = {} # peer id -> true while in LEVEL_STAGE_SYNC
# Playtests: false turns the resend off (t242 shows the race without it);
# every resend made, newest last.
static var resend_on := true
static var resends: Array = []


# A session closed (the chunker's reset): its request and peer ids start over
# in the next one.
static func reset() -> void:
	if _inst == null:
		return
	_inst._meta_sent.clear()
	_inst._resend_wait.clear()
	_inst._resend_read.clear()
	_inst._resend_synced.clear()


# The lava's and the gas's save blob (story.lava, story.gas: tens of KB) goes
# into Data for vanilla's save. Online, Data.apply would also send it to every
# client as one big delta at each autosave (every wave's start and end), which
# holds up the chunker's other Data messages to them (#246); clients get the
# lava and gas from the host's stream instead, so the host keeps it to itself.
# A loaded save puts the blobs back into Data, and a full sync sends all of
# Data: net/ordered_chunker.gd takes them out of every big Data message (#247).
static func save_blob(key: String, blob: String) -> void:
	if not Network.is_offline_mode() and not Network.is_client():
		Data.server_apply(key, blob)
	else:
		Data.apply(key, blob)


# True once `map`'s story meta can be read: always on the host and offline; on
# a client, once the host's copy has arrived.
static func map_meta_ready(map) -> bool:
	if not Network.is_client():
		return true
	return map != null and map.tileData != null and map.tileData.has_meta(SYNCED)


func _process(_delta: float) -> void:
	if Network.is_offline_mode():
		return
	if Network.is_client():
		_client_prices()
		if _Story.is_story():
			_client_meta()
	elif _Story.is_story():
		_host_meta()
		_host_resend()
		_log_tally()


# --- host ----------------------------------------------------------------------

func _host_meta() -> void:
	if Data.values.has(MAP_META):
		Data.values.erase(MAP_META)
	var td = _host_map_data()
	if td == null or not td.has_meta("story_ocean"):
		return
	if _meta_seed != Level.levelSeed:
		var metas: Dictionary = {}
		for k: StringName in td.get_meta_list():
			var v = td.get_meta(k)
			if String(k) in LOCAL_ONLY or v is Object:
				continue
			metas[String(k)] = v
		# var_to_str keeps Rect2i and Vector2i.
		var text: PackedByteArray = var_to_str(metas).to_utf8_buffer()
		_meta_size = text.size()
		_meta_bytes = text.compress(FileAccess.CompressionMode.COMPRESSION_ZSTD)
		_meta_seed = Level.levelSeed
		_meta_sent.clear()
		ModLoaderLog.info("Story map facts for clients: %d keys, %d bytes, %d compressed" % [metas.size(), _meta_size, _meta_bytes.size()], Story.LOG)
	var peers: Dictionary = {}
	for c in Network.clients:
		peers[c.peer_id] = true
		if c.connection_state == Network.ConnectionState.HANDSHAKE or int(_meta_sent.get(c.peer_id, -1)) == _meta_seed:
			continue
		_meta_sent[c.peer_id] = _meta_seed
		# Reliable RPCs on one channel arrive in order, each under the chunker's
		# size, so none of them holds up a Data message.
		var total: int = ceili(float(_meta_bytes.size()) / META_PART)
		for i in total:
			_client_meta_part.rpc_id(c.peer_id, _meta_seed, _meta_size, i, total, _meta_bytes.slice(i * META_PART, mini((i + 1) * META_PART, _meta_bytes.size())))
		ModLoaderLog.info("Story map facts sent to peer %d in %d messages" % [c.peer_id, total], Story.LOG)
	for p in _meta_sent.keys():
		if not peers.has(p):
			_meta_sent.erase(p)


# The run's map data: the landing stage's while it lands, then the level's.
func _host_map_data():
	if Level.map != null and is_instance_valid(Level.map) and Level.map.tileData != null:
		return Level.map.tileData
	var st = StageManager.currentStage
	if st != null and is_instance_valid(st) and st is LandingStage and st.levelStartData != null:
		var td = st.levelStartData.tileData
		if td != null and is_instance_valid(td):
			return td
	return null


# --- the settled resend (#242) -------------------------------------------------
# A small Data delta can reach a client before a big (chunked) message sent
# earlier, whose older values then win; vanilla doesn't send that key again
# until it changes. So the host reads each chunked Data message to a client in
# flight and, once they have landed, sends that client every key whose value
# now differs (after a full sync, also keys it didn't hold), and every Story
# Mode key once it reaches LEVEL_STAGE_SYNC. In messages under the chunk size,
# so they keep their order with later deltas.

func _host_resend() -> void:
	var now: int = Time.get_ticks_msec()
	var flying: Dictionary = {}
	var outgoing: Dictionary = Network.chunker.outgoing_rpcs
	for id in outgoing:
		var r = outgoing[id]
		if r.is_sent() or not is_data(r.request_type):
			continue
		flying[r.target_peer_id] = true
		if _resend_read.has(id):
			continue
		_resend_read[id] = true
		var w: Dictionary = _wait(r.target_peer_id)
		var full: bool = r.request_type == Chunker.ChunkRequestType.DATA_FULL_SYNC
		var vals: Dictionary = queued_values(r)
		_log_message(r, full, vals)
		if full:
			w["full"] = true
			w["vals"] = vals    # a full sync replaces everything before it
		else:
			w["vals"].merge(vals, true)
	for id in _resend_read.keys():
		if not outgoing.has(id):
			_resend_read.erase(id)
	var peers: Dictionary = {}
	for c in Network.clients:
		var p: int = c.peer_id
		peers[p] = true
		var in_sync: bool = c.connection_state == Network.ConnectionState.LEVEL_STAGE_SYNC
		if not in_sync:
			_resend_synced.erase(p)
			continue
		if not _resend_synced.has(p):
			_resend_synced[p] = true
			_wait(p)["story"] = true
		if not _resend_wait.has(p):
			continue
		var w: Dictionary = _resend_wait[p]
		if flying.has(p) or not w.has("out"):
			w["out"] = now
			continue
		if now - int(w["out"]) < int(RESEND_SETTLE * 1000.0):
			continue
		_resend_wait.erase(p)
		if resend_on:
			_resend(p, w)
	for p in _resend_wait.keys():
		if not peers.has(p):
			_resend_wait.erase(p)
	for p in _resend_synced.keys():
		if not peers.has(p):
			_resend_synced.erase(p)


func _wait(peer: int) -> Dictionary:
	if not _resend_wait.has(peer):
		_resend_wait[peer] = {"vals": {}, "full": false, "story": false}
	return _resend_wait[peer]


static func is_data(request_type: int) -> bool:
	return request_type == Chunker.ChunkRequestType.DATA_DELTA_SYNC or request_type == Chunker.ChunkRequestType.DATA_FULL_SYNC


# The Data values a Data message's bound arguments carry: (tick,
# var_to_bytes(changes)) for a delta, (size, zstd bytes) or (tick, size, zstd
# bytes) for a full sync. Empty when they hold none.
static func data_values(request_type: int, args) -> Dictionary:
	if not args is Array or args.size() < 2 or not args[-1] is PackedByteArray:
		return {}
	var bytes: PackedByteArray = args[-1]
	if request_type == Chunker.ChunkRequestType.DATA_FULL_SYNC:
		if not args[-2] is int:
			return {}
		bytes = bytes.decompress(args[-2], FileAccess.CompressionMode.COMPRESSION_ZSTD)
	var vals = bytes_to_var(bytes)
	return vals if vals is Dictionary else {}


# data_values() of a queued message.
static func queued_values(r) -> Dictionary:
	var buf := PackedByteArray()
	for ch: PackedByteArray in r.chunks:
		buf.append_array(ch)
	return data_values(r.request_type, bytes_to_var(buf))


func _resend(peer: int, w: Dictionary) -> void:
	var vals: Dictionary = w["vals"]
	var keys: Array = []
	var stale := 0
	for k in Data.values:
		if k in HOST_ONLY:
			continue
		if vals.has(k):
			if not _same(vals[k], Data.values[k]):
				keys.append(k)
				stale += 1
				continue
		elif w["full"]:
			keys.append(k)
			stale += 1
			continue
		if w["story"] and _story_key(String(k)):
			keys.append(k)
	if keys.is_empty():
		return
	var batch: Dictionary = {}
	var size := 0
	var messages := 0
	for k in keys:
		var n: int = var_to_bytes(Data.values[k]).size() + String(k).length() + 8
		if size + n > RESEND_BATCH and not batch.is_empty():
			_send_delta(peer, batch)
			messages += 1
			batch = {}
			size = 0
		batch[k] = Data.values[k]
		size += n
	if not batch.is_empty():
		_send_delta(peer, batch)
		messages += 1
	if OS.has_feature("editor"):
		resends.append({"peer": peer, "keys": keys.size(), "stale": stale, "messages": messages, "story": w["story"], "msec": Time.get_ticks_msec()})
	ModLoaderLog.info("Data resent to peer %d once its big messages landed: %d keys (%d changed since), %d messages" % [peer, keys.size(), stale, messages], Story.LOG)


# Vanilla's delta message, to one client (DataSynchronizer.on_network_tick).
func _send_delta(peer: int, batch: Dictionary) -> void:
	Network.chunker.send(peer, Chunker.ChunkRequestType.DATA_DELTA_SYNC, Data.synchronizer.remote_data_call.bind(Network.tick_count, var_to_bytes(batch)))


# --- measuring Data messages (#247) ---------------------------------------------
# Each chunked Data message to a client (900 bytes or more, the chunker's
# MAX_CHUNK_SIZE) is logged once from the host, as the resend reads it: kind,
# bytes sent, the client's connection state, and the keys and key groups that
# make it up, by what var_to_bytes spends on each (a full sync goes out zstd
# compressed; its raw sizes are before that). With `--datasizes` (editor) every
# key is logged too, a full sync's biggest keys get their share of the
# compressed size, and ordered_chunker.gd tallies every Data message sent.

static var measured: Array = []    # one entry per logged message, for playtests


func _log_message(r, full: bool, vals: Dictionary) -> void:
	var sent := 0
	for ch: PackedByteArray in r.chunks:
		sent += ch.size()
	if sent < Chunker.MAX_CHUNK_SIZE:
		return
	var rows: Array = key_sizes(vals)
	var groups: Dictionary = {}
	var raw := 0
	for row in rows:
		raw += int(row[1])
		var g: String = key_group(row[0])
		groups[g] = int(groups.get(g, 0)) + int(row[1])
	var grows: Array = []
	for g in groups:
		grows.append([g, groups[g]])
	grows.sort_custom(func(a, b): return a[1] > b[1])
	var state := "?"
	for c in Network.clients:
		if c.peer_id == r.target_peer_id:
			state = str(Network.ConnectionState.find_key(c.connection_state))
	var entry: Dictionary = {"peer": r.target_peer_id, "kind": "full" if full else "delta", "sent": sent, "keys": vals.size(),
		"raw": raw, "state": state, "top": rows.slice(0, 12), "groups": grows.slice(0, 12)}
	var dev: bool = OS.has_feature("editor") and _Story.has_user_arg("datasizes")
	if full and dev:
		var bytes: PackedByteArray = var_to_bytes(vals)
		var zall: int = bytes.compress(FileAccess.CompressionMode.COMPRESSION_ZSTD).size()
		var shares: Array = []
		for row in rows.slice(0, 10):
			var rest: Dictionary = vals.duplicate()
			rest.erase(row[0])
			shares.append([row[0], zall - var_to_bytes(rest).compress(FileAccess.CompressionMode.COMPRESSION_ZSTD).size()])
		entry["zstd"] = zall
		entry["zstd_shares"] = shares
	if OS.has_feature("editor"):
		measured.append(entry)
	ModLoaderLog.info("Data message to peer %d (%s): %s, %d bytes sent, %d keys, %d bytes raw; groups: %s; biggest: %s" % [
		r.target_peer_id, state, entry["kind"], sent, vals.size(), raw, _rows_text(grows.slice(0, 6)), _rows_text(rows.slice(0, 6))], Story.LOG)
	if dev:
		ModLoaderLog.info("  every key: " + _rows_text(rows), Story.LOG)
		if entry.has("zstd"):
			ModLoaderLog.info("  zstd %d bytes; biggest keys' share of it: %s" % [entry["zstd"], _rows_text(entry["zstd_shares"])], Story.LOG)


# [key, bytes] for each key of `vals`, largest first: what var_to_bytes spends
# on the key and its value.
static func key_sizes(vals: Dictionary) -> Array:
	var rows: Array = []
	for k in vals:
		rows.append([String(k), var_to_bytes(k).size() + var_to_bytes(vals[k]).size()])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	return rows


# A key's group: its path without the last part, numbers in player ids kept
# ("team1.story.boss" -> "team1.story", "story.mapmeta" -> "story").
static func key_group(k: String) -> String:
	var at: int = k.rfind(".")
	return k.substr(0, at) if at > 0 else k


var _tally_at := 0


# With `--datasizes`: every 20 s, how many Data messages went to clients and
# how big (ordered_chunker.gd's tally since start-up).
func _log_tally() -> void:
	var ch = Network.chunker
	if ch == null or not ch.get("tally_on"):
		return
	var now: int = Time.get_ticks_msec()
	if now - _tally_at < 20000:
		return
	_tally_at = now
	var t: Dictionary = ch.tally
	ModLoaderLog.info("Data messages so far: %d, %d bytes (mean %d, max %d); under 300 bytes %d, 300-899 %d, chunked %d" % [
		t["messages"], t["bytes"], int(t["bytes"]) / maxi(1, int(t["messages"])), t["max"], t["under_300"], t["under_900"], t["chunked"]], Story.LOG)


static func _rows_text(rows: Array) -> String:
	var out: PackedStringArray = []
	for row in rows:
		out.append("%s %d" % [row[0], row[1]])
	return ", ".join(out)


static func _story_key(k: String) -> bool:
	for pre: String in RESEND_PREFIXES:
		if k.begins_with(pre):
			return true
	if k.begins_with("player"):
		var at: int = k.find(".")
		for part: String in RESEND_PLAYER_PARTS:
			if at > 0 and k.substr(at).begins_with(part):
				return true
	return false


static func _same(a, b) -> bool:
	return typeof(a) == typeof(b) and a == b


# --- client --------------------------------------------------------------------

func _client_meta() -> void:
	var map = Level.map
	if map == null or not is_instance_valid(map) or map.tileData == null or map.tileData.has_meta(SYNCED):
		return
	if _meta_text_seed != Level.levelSeed or _meta_text == "":
		return
	var metas = str_to_var(_meta_text)
	if not metas is Dictionary:
		push_error("Story Mode: the host's map facts did not parse")
		return
	for k: String in metas:
		map.tileData.set_meta(k, metas[k])
	map.tileData.set_meta(SYNCED, true)
	ModLoaderLog.info("Story map facts from the host applied (%d keys)" % metas.size(), Story.LOG)


# Host -> one client: part `index` of `total` of the zstd-compressed map facts
# (`size` bytes whole) for the run with `seed`.
@rpc("authority", "call_remote", "reliable")
func _client_meta_part(seed: int, size: int, index: int, total: int, part: PackedByteArray) -> void:
	if seed != _meta_in_seed:
		_meta_in_seed = seed
		_meta_parts = {}
	_meta_parts[index] = part
	if _meta_parts.size() < total:
		return
	var buf := PackedByteArray()
	for i in total:
		buf.append_array(_meta_parts.get(i, PackedByteArray()))
	_meta_parts = {}
	_meta_text = buf.decompress(size, FileAccess.CompressionMode.COMPRESSION_ZSTD).get_string_from_utf8()
	_meta_text_seed = seed


# Story Mode's prices and iron drop for a Story Mode run, vanilla's otherwise;
# the host's mod_main.prepareGameMode does the same.
func _client_prices() -> void:
	var story: bool = _Story.is_story()
	if story == _client_story:
		return
	_client_story = story
	_Prices.apply(story)
	_Minerals.use_story_iron(story)
	ModLoaderLog.info("Client: Story Mode prices %s" % ("on" if story else "off"), Story.LOG)


# --- lava (#227) ---------------------------------------------------------------
# The RPCs go through this node: it sits at the same path on every peer from
# start-up, while a map's LavaField only exists during a run (an RPC to a node a
# peer doesn't have is an error). A client without a field drops the cells; it
# asks for a full snapshot once its field is built.

static var _inst = null


func _enter_tree() -> void:
	_inst = self


static func _lava():
	if Level.map == null or not is_instance_valid(Level.map):
		return null
	return Level.map.get_node_or_null("StoryLavaField")


# Host -> every client: changed lava cells.
static func lava_cells(data: PackedByteArray) -> void:
	if _inst != null:
		_inst.rpc("_lava_cells", data, false)


@rpc("authority", "call_remote", "reliable")
func _lava_cells(data: PackedByteArray, full: bool) -> void:
	var f = _lava()
	if f != null and f.net_client:
		f.net_apply(data, full)


# Client -> host: send me all the lava.
static func lava_full_request() -> void:
	if _inst != null:
		_inst.rpc_id(1, "_lava_full_request")


@rpc("any_peer", "call_remote", "reliable")
func _lava_full_request() -> void:
	if Network.is_client():
		return
	var f = _lava()
	if f != null and not f.net_client:
		rpc_id(multiplayer.get_remote_sender_id(), "_lava_cells", f.net_full(), true)


# Host -> every client: lava water turned to rock.
static func lava_harden(cells: PackedVector2Array) -> void:
	if _inst != null and not Network.is_offline_mode():
		_inst.rpc("_lava_harden", cells)


@rpc("authority", "call_remote", "reliable")
func _lava_harden(cells: PackedVector2Array) -> void:
	var f = _lava()
	if f != null and f.net_client:
		f.net_harden(cells)


# Client -> host: my keeper died in the heat or the gas (the host takes the
# money, plays the beat; `cause` "lava" or "gas", #357).
static func lava_died(player_id: String, cause: String = "lava") -> void:
	if _inst != null:
		_inst.rpc_id(1, "_lava_died", player_id, cause)


@rpc("any_peer", "call_remote", "reliable")
func _lava_died(player_id: String, cause: String) -> void:
	if Network.is_client():
		return
	var f = _lava()
	var k = Keepers.getKeeper(player_id) if Keepers.hasKeeper(player_id) else null
	if f == null or k == null or k.peerId != multiplayer.get_remote_sender_id():
		return
	f.team_death(k, "gas" if cause == "gas" else "lava")


# Client -> host: my keeper broke into the boss chamber (#95 wakes the horror).
static func chamber_reached() -> void:
	if _inst != null:
		_inst.rpc_id(1, "_chamber_reached")


@rpc("any_peer", "call_remote", "reliable")
func _chamber_reached() -> void:
	if not Network.is_client() and _Story.is_story():
		load("res://mods-unpacked/flantor-StoryMode/beats/awakening.gd").wake()


# --- the ocean's tentacles (#364) ---------------------------------------------
# The host's wave clocks, swings and speeds (map/ocean_tentacles.gd
# clock_state), a few times a second; a lost one is replaced by the next.

static func tentacle_clock(data: PackedFloat32Array) -> void:
	if _inst != null and not Network.is_offline_mode():
		Network.rpc_if_state(_inst._tentacle_clock.bind(data), Network.ConnectionState.LEVEL_STAGE_SYNC)


@rpc("authority", "call_remote", "unreliable_ordered")
func _tentacle_clock(data: PackedFloat32Array) -> void:
	if Level.map == null or not is_instance_valid(Level.map):
		return
	var f = Level.map.get_node_or_null("StoryOceanTentacles")
	if f != null:
		f.net_apply(data)


# --- gas (#228) ----------------------------------------------------------------
# As the lava: the host's GasField streams, a client's draws.

static func _gas():
	if Level.map == null or not is_instance_valid(Level.map):
		return null
	return Level.map.get_node_or_null("StoryGasField")


# Host -> every client: gas that changed (or all of it, `full`).
static func gas_cells(data: PackedByteArray, full: bool) -> void:
	if _inst != null:
		_inst.rpc("_gas_cells", data, full)


@rpc("authority", "call_remote", "reliable")
func _gas_cells(data: PackedByteArray, full: bool) -> void:
	var f = _gas()
	if f != null and f.net_client:
		f.net_apply(data, full)


# Client -> host: send me all the gas.
static func gas_full_request() -> void:
	if _inst != null:
		_inst.rpc_id(1, "_gas_full_request")


@rpc("any_peer", "call_remote", "reliable")
func _gas_full_request() -> void:
	if Network.is_client():
		return
	var f = _gas()
	if f != null and not f.net_client:
		rpc_id(multiplayer.get_remote_sender_id(), "_gas_cells", f.net_full(), true)


# --- tiles the host breaks itself (#228) ---------------------------------------
# Vanilla sends clients a tile's hits (Tile.hit), not Map.destroyTile, which is
# how gas rock bursts and magma melts. Host -> every client: break this tile
# too. A client only breaks tiles it has made, and one deep in rock may be
# unrevealed there, so it is revealed everywhere first, as vanilla does.
static func tile_break(map, c: Vector2i) -> void:
	if _inst == null or Network.is_offline_mode() or Network.is_client():
		return
	map.networkRevealTile(Vector2(c), 0.0)
	_inst.rpc("_tile_break", c)


@rpc("authority", "call_remote", "reliable")
func _tile_break(c: Vector2i) -> void:
	var map = Level.map
	if map == null or not is_instance_valid(map) or not map.isMapReady():
		return
	if not map.tiles.has(Vector2(c)):
		map.revealTile(Vector2(c))
	var tile = map.tiles.get(Vector2(c))
	if tile != null and is_instance_valid(tile):
		map.destroyTile("team1", "", tile)
