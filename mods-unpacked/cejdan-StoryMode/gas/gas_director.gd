extends Node

# Gives each Story Mode run's map a GasField (#198), once its lava field is
# there (gas keeps clear of magma, and lava closes cells to gas). Polls like
# the lava director; vanilla modes never get gas.

const GasField = preload("res://mods-unpacked/cejdan-StoryMode/gas/gas_field.gd")
const FIELD_NAME := "StoryGasField"
const LAVA_FIELD := "StoryLavaField"


func _process(_delta: float) -> void:
	var map = Level.map
	if map == null or not is_instance_valid(map) or not map.is_inside_tree():
		return
	if not map.isMapReady() or map.has_node(FIELD_NAME) or not map.has_node(LAVA_FIELD):
		return
	if not Level.stage is LevelStage:
		return
	# A client builds its field from the host's map facts (#225).
	if not load("res://mods-unpacked/cejdan-StoryMode/net/story_net.gd").map_meta_ready(map):
		return
	var field := GasField.new()
	field.name = FIELD_NAME
	map.add_child(field)
	field.setup(map)
	ModLoaderLog.info("Gas field added: %d gas rock cells" % field.rock.size(), "cejdan-StoryMode")
