extends Node

const STORYMODE_LOG = "cejdan-StoryMode"


func _init():
	ModLoaderLog.info("Init", STORYMODE_LOG)


func _ready():
	ModLoaderLog.info("Done", STORYMODE_LOG)
	add_to_group("mod_init")


# Called by the game once its data is loaded. Story Mode registers its
# game mode here (see the "Mod skeleton" ticket on the map).
func modInit():
	pass
