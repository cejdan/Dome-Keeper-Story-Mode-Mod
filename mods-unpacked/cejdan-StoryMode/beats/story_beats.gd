extends Node

# Story beats (#23): the horror's text boxes. A beat opens when it is fired and
# pauses the game (so the wave countdown, lava and Suit Blaster recharge all
# stop) until the player closes it. Each beat plays once per run, except one
# marked "repeat" in data/beats.gd.
#
# Other code fires beats through the static helpers, which do nothing outside a
# Story Mode run:
#   const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
#   StoryBeats.fire("first_gem")        # one beat, by id
#   StoryBeats.trigger("biome:B2")      # every beat whose trigger is that name
#
# Beats are data (data/beats.gd). Fired beats wait in a queue until nothing
# else is on screen (pause menu, a choice popup, another beat). Queue and
# played list are Data keys, so they are saved with the run: a beat that was
# open or waiting when the game saved opens again after the reload, and a
# beat that was closed never plays again.
#
# Online multiplayer (#229): the host alone queues beats and decides when one
# opens. While one is open the host keeps "<serial>:<id>" in Data (OPEN), which
# reaches every client, a late one too. Every instance follows that key: it
# opens the box for its own player, and pauses its game (vanilla's group
# pause) for as long as the key is set. Each player pages their own box. A
# client that closes its box tells the host (_ack); the host closes the beat
# for the team by CLOSE_RULE, records it as played and clears the key, which
# unpauses everyone and closes any box still open. Offline play (single
# player, splitscreen) takes none of these paths.

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const BeatData = preload("res://mods-unpacked/cejdan-StoryMode/data/beats.gd")
const LogData = preload("res://mods-unpacked/cejdan-StoryMode/data/logs.gd")

const GROUP := "story-beats"
const PLAYED := "team1.story.beatsplayed"
const QUEUED := "team1.story.beatsqueued"

# Online: the beat on the team's screens, "<serial>:<id>", "" when none.
const OPEN := "team1.story.beatopen"
# Online: when an open beat closes for the team. "all": once every player has
# closed their own box (nobody misses the story; the game stays paused for
# those who are done). "any": as soon as one player closes theirs.
const CLOSE_RULE := "all"
# Online, host: a beat waits this long at most for clients still loading the
# level, so the welcome log doesn't open and close before they arrive.
const SYNC_WAIT := 20.0

signal beat_opened(id: String)
signal beat_closed(id: String)

# Id of the beat on screen, "" when none.
var open_id: String = ""
var _box: Control = null
var _input = null
# Seconds left before a waiting beat may open (hold()).
var _hold_t: float = 0.0
# Online. Host: the open beat's serial and the peers who closed their box.
var _serial: int = 0
var _acks: Dictionary = {}
# The OPEN value this instance is showing or has shown, and whether its own
# player closed the box already.
var _following: String = ""
var _mine_closed: bool = false
var _team_paused: bool = false
var _sync_waited: float = 0.0
var _waiting: Label = null


# ---------------------------------------------------------------- API (static)

static func instance():
	var tree = Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return null
	return tree.get_first_node_in_group(GROUP)


# Queues the beat `id`. False when it is unknown, already played (unless the
# beat has "repeat") or already waiting, or when this is not a Story Mode run.
static func fire(id: String) -> bool:
	var n = instance()
	return n != null and n.queue_beat(id)


# Queues every unplayed beat whose trigger is `trigger_name`; returns how many.
static func trigger(trigger_name: String) -> int:
	var n = instance()
	if n == null:
		return 0
	var count: int = 0
	for id: String in BeatData.ids_for(trigger_name):
		if n.queue_beat(id):
			count += 1
	return count


# Shows the beat `id` now, ahead of the queue, and waits until it is closed
# (nothing if it already played). For the endings, which must play their beat
# before the run ends.
func play_now(id: String) -> void:
	if has_played(id):
		return
	while open_id != "":
		await beat_closed
	var q: Array = _list(QUEUED)
	if not q.has(id):
		q.push_front(id)
		_store(QUEUED, q)
	_show(id)
	while open_id == id:
		await beat_closed


# Keeps every waiting beat off screen for at least `seconds` of unpaused play,
# so something the player should see first (a sale pop) gets its moment.
static func hold(seconds: float) -> void:
	var n = instance()
	if n != null:
		n._hold_t = maxf(n._hold_t, seconds)


static func has_played(id: String) -> bool:
	return _list(PLAYED).has(id)


static func is_open() -> bool:
	var n = instance()
	return n != null and n.open_id != ""


static func _list(key: String) -> Array:
	return Array(str(Data.ofOr(key, "")).split(",", false))


static func _store(key: String, ids: Array) -> void:
	Data.apply(key, ",".join(PackedStringArray(ids)))


# ---------------------------------------------------------------- node

func _ready() -> void:
	name = "StoryBeats"
	add_to_group(GROUP)


func queue_beat(id: String) -> bool:
	if not multiplayer.is_server() or not Story.is_story():
		return false
	if _entry(id).is_empty():
		push_warning("Story beat: no beat or log with id " + id)
		return false
	var queued: Array = _list(QUEUED)
	if queued.has(id) or (_list(PLAYED).has(id) and not bool(_entry(id).get("repeat", false))):
		return false
	queued.append(id)
	_store(QUEUED, queued)
	ModLoaderLog.info("Story beat queued: " + id, Story.LOG)
	return true


const DEEPEST := "team1.story.deepest"
const WATCH_EVERY := 0.2
var _watch_t: float = 0.0


# Depth (#26): the keeper's tile biome, not a fixed row, since biome edges are
# ragged. Entering B2..B8 for the first time fires "biome:B<n>"; the lava ocean
# (the generator's "story_ocean" rows) fires "lava_ocean". The deepest biome
# reached is kept in Data (0 = B1 .. 7 = B8, 8 = the ocean) for the pleas.
func _watch_depth() -> void:
	if not multiplayer.is_server() or Level.map == null or Level.map.tileData == null:
		return
	# The host watches every player's keeper: online (#229) and every local
	# keeper in splitscreen (#231).
	for k in Keepers.getAll():
		_watch_keeper(k)


func _watch_keeper(keeper) -> void:
	if keeper == null or not is_instance_valid(keeper) or keeper.isInsideDome:
		return
	var td = Level.map.tileData
	var c: Vector2i = Level.map.getTileCoord(keeper.global_position)
	var depth: int = -1
	var ocean: Dictionary = td.get_meta("story_ocean", {})
	if not ocean.is_empty() and c.y > int(ocean["ceiling"]) and c.x >= int(ocean["x0"]) and c.x <= int(ocean["x1"]):
		depth = 8
	else:
		depth = td.get_biomev(c)
	if depth < 0:
		return
	if depth > int(Data.ofOr(DEEPEST, 0)):
		Data.apply(DEEPEST, depth)
	if depth == 8:
		trigger("lava_ocean")
	elif depth >= 1:
		trigger("biome:B%d" % (depth + 1))


static func deepest() -> int:
	return int(Data.ofOr(DEEPEST, 0))


func _process(delta: float) -> void:
	if not Network.is_offline_mode():
		_follow_team(delta)
	_watch_t += delta
	if _watch_t >= WATCH_EVERY and not GameWorld.paused:
		_watch_t = 0.0
		_watch_depth()
	if _hold_t > 0.0 and not GameWorld.paused:
		_hold_t -= delta
	if open_id != "" or _hold_t > 0.0 or not _can_show():
		return
	var queued: Array = _list(QUEUED)
	if queued.is_empty():
		return
	_show(str(queued[0]))


# True when a beat can open now without fighting another popup for input.
func _can_show() -> bool:
	var stage = Level.stage
	if stage == null or StageManager.isSwitchingStage() or not stage.keeperInputStarted:
		return false
	if stage.pauseMenuOpen or stage.showingChoicePopup or stage.endingPanel != null:
		return false
	# Nothing waiting opens over an ending or a lost run: stopKeeperInput leaves
	# keeperInputStarted set, and the ending's cards don't pause. The ending's own
	# beat goes through play_now().
	if GameWorld.won or GameWorld.lost:
		return false
	# Nothing opens during the boss sequence either (#174): a text box there
	# kills the flow. Whatever was waiting shows afterwards, if the run goes on.
	if Story.boss_active():
		return false
	var mode = Level.mode
	if mode != null and mode.has_method("is_ending") and mode.is_ending():
		return false
	# A loading save restores Data (and so the queue) after the stage starts.
	if GameWorld.paused or SaveGame.currentLoadingSavegame or Story.local_keeper() == null:
		return false
	# Online: a client's own queue check never opens a beat (the host's OPEN key
	# does), and the host gives clients still loading a moment to arrive.
	if not Network.is_offline_mode():
		if not multiplayer.is_server() or str(Data.ofOr(OPEN, "")) != "":
			return false
		if _sync_waited < SYNC_WAIT:
			for c in Network.clients:
				if c.connection_state != Network.ConnectionState.LEVEL_STAGE_SYNC:
					return false
	return true


# A beat (data/beats.gd) or a miner's data log (data/logs.gd, #94): logs ride
# the same queue, pause and once-per-run record, in their own box.
static func _entry(id: String) -> Dictionary:
	var b: Dictionary = BeatData.by_id(id)
	return b if not b.is_empty() else LogData.by_id(id)


func _show(id: String) -> void:
	var beat: Dictionary = _entry(id)
	if beat.is_empty():
		# Dropped from the data file since it was queued (an old save).
		var q: Array = _list(QUEUED)
		q.erase(id)
		_store(QUEUED, q)
		return
	open_id = id
	if not Network.is_offline_mode():
		# The host opens the beat for the team; _follow_team pauses everyone.
		_serial += 1
		_acks = {}
		_following = "%d:%s" % [_serial, id]
		_mine_closed = false
		_sync_waited = 0.0
		Data.apply(OPEN, _following)
	_open_box(id, beat)
	ModLoaderLog.info("Story beat open: " + id, Story.LOG)
	beat_opened.emit(id)


# This player's box for the beat `id`.
func _open_box(id: String, beat: Dictionary) -> void:
	var keeper: Keeper = Story.local_keeper()
	var i = load(Story.MOD_DIR + "beats/BeatInputProcessor.gd").new()
	i.deviceId = keeper.deviceId
	i.globalInput = true
	var is_log: bool = not LogData.by_id(id).is_empty()
	i.popup = load(Story.MOD_DIR + ("beats/LogBox.gd" if is_log else "beats/BeatBox.gd")).new()
	i.popup.setup(id, int(beat.get("tier", 1)))
	_box = i.popup
	Level.stage.showPopup(i.popup, null, "", LevelStage.PopupCanvas.GLOBAL)
	# As vanilla's choice popups: no pause menu on top, and the game pauses.
	Level.stage.showingChoicePopup = true
	i.connect("onStop", _on_closed.bind(id))
	i.integrate(Level.stage)
	_input = i
	if not Network.is_offline_mode():
		return
	Level.stage.pause()
	_hide_pause_label()


# The beat is the pause's own signal: vanilla's "Paused" label stays hidden.
func _hide_pause_label() -> void:
	for n in get_tree().get_nodes_in_group("pauseL"):
		if n.name == "PauseLabel" and n.has_method("moveOut"):
			n.moveOut()


func _on_closed(id: String) -> void:
	if not Network.is_offline_mode():
		_on_closed_online(id)
		return
	var q: Array = _list(QUEUED)
	q.erase(id)
	_store(QUEUED, q)
	var played: Array = _list(PLAYED)
	if not played.has(id):
		played.append(id)
		_store(PLAYED, played)
	open_id = ""
	_box = null
	if Level.stage != null:
		Level.stage.unpause()
	ModLoaderLog.info("Story beat closed: " + id, Story.LOG)
	beat_closed.emit(id)


# ---------------------------------------------------------------- online (#229)

# True while a beat is open for the team (this player may have closed theirs).
static func team_open() -> bool:
	return not Network.is_offline_mode() and str(Data.ofOr(OPEN, "")) != ""


# Every instance, every frame of an online run: follows the host's OPEN key.
func _follow_team(delta: float) -> void:
	var stage = Level.stage
	if stage == null or not (stage is LevelStage) or not Story.is_story():
		return
	var cur: String = str(Data.ofOr(OPEN, ""))
	if multiplayer.is_server():
		if cur != "" and open_id == "":
			# Left over from a save made while a beat was open; it reopens from the queue.
			Data.apply(OPEN, "")
			cur = ""
		elif open_id != "" and _rule_met():
			_finish(open_id)
			cur = ""
		elif open_id == "" and not _list(QUEUED).is_empty():
			_sync_waited += delta
	elif cur != _following:
		# The host closed the beat (or opened the next): this player's box goes.
		_close_box()
		open_id = ""
		_following = cur
		_mine_closed = false
		if cur != "":
			_serial = int(cur.get_slice(":", 0))
	if cur == "":
		if _team_paused:
			_team_unpause()
		_set_waiting(false)
		return
	if not multiplayer.is_server() and open_id == "" and not _mine_closed and _client_can_show():
		var id: String = cur.substr(cur.find(":") + 1)
		var beat: Dictionary = _entry(id)
		if beat.is_empty():
			# Unknown here (a mod version mismatch): don't hold the team up.
			_mine_closed = true
			_ack.rpc_id(1, _serial)
		else:
			open_id = id
			_open_box(id, beat)
			ModLoaderLog.info("Story beat open: " + id, Story.LOG)
			beat_opened.emit(id)
	# The whole team pauses while the beat is open. Enforced every frame:
	# vanilla's own group pause check may unpause when a pause menu closes.
	_team_paused = true
	if not GameWorld.paused:
		GameWorld.pause(true)
		if stage.has_node("Tween"):
			stage.get_node("Tween").stop_all()
		get_tree().call_group("monster", "pause")
		_hide_pause_label()
	# No pause menu over this player's box; with the box closed it may open.
	if _box != null and is_instance_valid(_box):
		stage.showingChoicePopup = true
	_set_waiting(_mine_closed and not stage.pauseMenuOpen)


func _client_can_show() -> bool:
	var stage = Level.stage
	if StageManager.isSwitchingStage() or not stage.keeperInputStarted or Story.local_keeper() == null:
		return false
	if stage.pauseMenuOpen or stage.showingChoicePopup or stage.endingPanel != null:
		return false
	# An ending takes the keeper's controls first; its beat opens after that.
	var mode = Level.mode
	if mode != null and mode.has_method("settling") and mode.settling():
		return false
	return true


func _team_unpause() -> void:
	_team_paused = false
	var stage = Level.stage
	GameWorld.unpause()
	if stage != null and stage is LevelStage:
		if stage.has_node("Tween"):
			stage.get_node("Tween").resume_all()
		get_tree().call_group("monster", "unpause")
		# Vanilla's own group pause, if every player sits in the pause menu.
		if multiplayer.is_server():
			stage.checkForGroupPause()


# This player closed their box.
func _on_closed_online(id: String) -> void:
	_box = null
	_input = null
	_mine_closed = true
	if Level.stage != null:
		Level.stage.showingChoicePopup = false
	if multiplayer.is_server():
		# open_id stays set until the beat closes for the team (_finish).
		_acks[1] = true
	else:
		open_id = ""
		_ack.rpc_id(1, _serial)
		ModLoaderLog.info("Story beat closed here: " + id, Story.LOG)
		beat_closed.emit(id)


# Client to host: the sender closed their box of beat number `serial`.
@rpc("any_peer", "call_remote", "reliable")
func _ack(serial: int) -> void:
	if multiplayer.is_server() and serial == _serial and open_id != "":
		_acks[multiplayer.get_remote_sender_id()] = true


# Host: has the team closed the open beat, by CLOSE_RULE?
func _rule_met() -> bool:
	if CLOSE_RULE == "any":
		return not _acks.is_empty()
	if not _acks.has(1):
		return false
	for c in Network.clients:
		if c.connection_state == Network.ConnectionState.LEVEL_STAGE_SYNC and not _acks.has(c.peer_id):
			return false
	return true


# Host: the beat is over for the team.
func _finish(id: String) -> void:
	var q: Array = _list(QUEUED)
	q.erase(id)
	_store(QUEUED, q)
	var played: Array = _list(PLAYED)
	if not played.has(id):
		played.append(id)
		_store(PLAYED, played)
	Data.apply(OPEN, "")
	_close_box()
	open_id = ""
	_following = ""
	_acks = {}
	ModLoaderLog.info("Story beat closed: " + id, Story.LOG)
	beat_closed.emit(id)


# Closes this player's box without their input (the beat closed for the team).
func _close_box() -> void:
	if _input != null and is_instance_valid(_input) and not _input.desintegrating:
		if _input.onStop.is_connected(_on_closed):
			_input.onStop.disconnect(_on_closed)
		_input.desintegrate()
		if Level.stage != null:
			Level.stage.showingChoicePopup = false
	_box = null
	_input = null


# "Waiting for the other players" at the foot of the screen, once this player
# has closed a beat the team still has open.
func _set_waiting(on: bool) -> void:
	if not on:
		if _waiting != null and is_instance_valid(_waiting):
			_waiting.get_parent().queue_free()
		_waiting = null
		return
	if _waiting != null and is_instance_valid(_waiting):
		return
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_waiting = Label.new()
	_waiting.name = "StoryBeatWaiting"
	_waiting.text = tr("story.beat.waiting")
	_waiting.label_settings = load("res://gui/fontsettings/NormalFontSettings.tres")
	_waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_waiting.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_waiting.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_waiting.offset_bottom = -90
	_waiting.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_waiting)
