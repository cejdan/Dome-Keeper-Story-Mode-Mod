extends Node

# Gives each Story Mode run's map a LavaField. Lives under the mod's main node and
# polls, so it needs no script extension: when a run's map is ready and has no
# LavaField yet, it adds one. Vanilla modes never get lava.
#
# Until the Story Mode game mode exists, a run counts as Story Mode when its
# loadout carries the "flantor-storymode" flag, or when the game was launched with
# `-- --lava` (dev switch).

const LavaField = preload("res://mods-unpacked/flantor-StoryMode/lava/lava_field.gd")
static var _LavaField = LavaField  # calls go through this: lazy_preload makes const-preload calls slow
const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const MODE_FLAG := "flantor-storymode"
const FIELD_NAME := "StoryLavaField"
const Chains = preload("res://mods-unpacked/flantor-StoryMode/map/chains.gd")
static var _Chains = Chains  # calls go through this: lazy_preload makes const-preload calls slow
const StoryNet = preload("res://mods-unpacked/flantor-StoryMode/net/story_net.gd")
static var _StoryNet = StoryNet  # calls go through this: lazy_preload makes const-preload calls slow


func _process(_delta: float) -> void:
	var map = Level.map
	if map == null or not is_instance_valid(map) or not map.is_inside_tree():
		return
	if not map.isMapReady() or map.has_node(FIELD_NAME):
		return
	# Only a run's map gets lava. The loadout screen has a small map of its own,
	# and picking Story Mode there sets the mode id before any run exists; a field
	# on that map reads run-only stage state every frame (a script error, which
	# the editor's debugger stops the game on).
	if not Level.stage is LevelStage:
		return
	if not _wants_lava():
		return
	# A client builds its field from the host's map facts (#225).
	if not _StoryNet.map_meta_ready(map):
		return
	var field := _LavaField.new()
	field.name = FIELD_NAME
	map.add_child(field)
	field.setup(map)
	ModLoaderLog.info("Lava field added: %d magma cells" % field.magma.size(), "flantor-StoryMode")
	# Chains of the seal (#101): Story Mode maps only (the --lava dev switch can
	# put lava on a vanilla map, which has no boss chamber).
	if _Story.is_story():
		var chains := _Chains.new()
		chains.setup(map)
		map.add_child(chains)
		ModLoaderLog.info("Chains added: %d" % chains.chains.size(), "flantor-StoryMode")
		# The ocean's two climbable tentacles (#364).
		var tents = load(_Story.MOD_DIR + "map/ocean_tentacles.gd").new()
		if tents.setup(map):
			map.add_child(tents)
		else:
			tents.free()
		# Velle's chamber in living stone (#361).
		var stone = load(_Story.MOD_DIR + "boss/chamber_stone.gd").new()
		if stone.setup(map):
			map.add_child(stone)
			ModLoaderLog.info("Chamber stone added: %d bodies" % stone.bodies.size(), "flantor-StoryMode")
		else:
			stone.free()


func _wants_lava() -> bool:
	if "--lava" in OS.get_cmdline_user_args():
		return true
	# A loaded save brings back the mode id but not the start-time flag.
	return _Story.is_story() or (Level.loadout != null and Level.loadout.modeConfig.get(MODE_FLAG, false))
