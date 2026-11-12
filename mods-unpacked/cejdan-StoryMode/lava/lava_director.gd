extends Node

# Gives each Story Mode run's map a LavaField. Lives under the mod's main node and
# polls, so it needs no script extension: when a run's map is ready and has no
# LavaField yet, it adds one. Vanilla modes never get lava.
#
# Until the Story Mode game mode exists, a run counts as Story Mode when its
# loadout carries the "cejdan-storymode" flag, or when the game was launched with
# `-- --lava` (dev switch).

const LavaField = preload("res://mods-unpacked/cejdan-StoryMode/lava/lava_field.gd")
const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const MODE_FLAG := "cejdan-storymode"
const FIELD_NAME := "StoryLavaField"


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
	var field := LavaField.new()
	field.name = FIELD_NAME
	map.add_child(field)
	field.setup(map)
	ModLoaderLog.info("Lava field added: %d magma cells" % field.magma.size(), "cejdan-StoryMode")


func _wants_lava() -> bool:
	if "--lava" in OS.get_cmdline_user_args():
		return true
	# A loaded save brings back the mode id but not the start-time flag.
	return Story.is_story() or (Level.loadout != null and Level.loadout.modeConfig.get(MODE_FLAG, false))
