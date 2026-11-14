extends Node

# Story beats (#23): the horror's text boxes. A beat opens when it is fired and
# pauses the game (so the wave countdown, lava and Suit Blaster recharge all
# stop) until the player closes it. Each beat plays once per run.
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

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const BeatData = preload("res://mods-unpacked/cejdan-StoryMode/data/beats.gd")

const GROUP := "story-beats"
const PLAYED := "team1.story.beatsplayed"
const QUEUED := "team1.story.beatsqueued"

signal beat_opened(id: String)
signal beat_closed(id: String)

# Id of the beat on screen, "" when none.
var open_id: String = ""
var _box: Control = null


# ---------------------------------------------------------------- API (static)

static func instance():
	var tree = Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return null
	return tree.get_first_node_in_group(GROUP)


# Queues the beat `id`. False when it is unknown, already played or already
# waiting, or when this is not a Story Mode run.
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
	if BeatData.by_id(id).is_empty():
		push_warning("Story beat: no beat with id " + id)
		return false
	var queued: Array = _list(QUEUED)
	if _list(PLAYED).has(id) or queued.has(id):
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
	var keeper = Keepers.first()
	if keeper == null or not is_instance_valid(keeper) or keeper.isInsideDome:
		return
	var td = Level.map.tileData
	var c: Vector2i = Level.map.getTileCoord(keeper.global_position)
	var depth: int = -1
	var ocean: Dictionary = td.get_meta("story_ocean", {})
	if not ocean.is_empty() and c.y >= int(ocean["top"]) - 1 and c.x >= int(ocean["x0"]) and c.x <= int(ocean["x1"]):
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
	_watch_t += delta
	if _watch_t >= WATCH_EVERY and not GameWorld.paused:
		_watch_t = 0.0
		_watch_depth()
	if open_id != "" or not _can_show():
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
	# A loading save restores Data (and so the queue) after the stage starts.
	if GameWorld.paused or SaveGame.currentLoadingSavegame or Keepers.first() == null:
		return false
	return true


func _show(id: String) -> void:
	var beat: Dictionary = BeatData.by_id(id)
	if beat.is_empty():
		# Dropped from the data file since it was queued (an old save).
		var q: Array = _list(QUEUED)
		q.erase(id)
		_store(QUEUED, q)
		return
	open_id = id
	var keeper: Keeper = Keepers.first()
	var i = load(Story.MOD_DIR + "beats/BeatInputProcessor.gd").new()
	i.deviceId = keeper.deviceId
	i.globalInput = true
	i.popup = load(Story.MOD_DIR + "beats/BeatBox.gd").new()
	i.popup.setup(id, int(beat.get("tier", 1)))
	_box = i.popup
	Level.stage.showPopup(i.popup, null, "", LevelStage.PopupCanvas.GLOBAL)
	# As vanilla's choice popups: no pause menu on top, and the game pauses.
	Level.stage.showingChoicePopup = true
	i.connect("onStop", _on_closed.bind(id))
	i.integrate(Level.stage)
	Level.stage.pause()
	# The beat is the pause's own signal: vanilla's "Paused" label stays hidden.
	for n in get_tree().get_nodes_in_group("pauseL"):
		if n.name == "PauseLabel" and n.has_method("moveOut"):
			n.moveOut()
	ModLoaderLog.info("Story beat open: " + id, Story.LOG)
	beat_opened.emit(id)


func _on_closed(id: String) -> void:
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
