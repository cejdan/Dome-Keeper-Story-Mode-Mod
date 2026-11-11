extends Node

const STORYMODE_LOG = "cejdan-StoryMode"


func _init():
	ModLoaderLog.info("Init", STORYMODE_LOG)


func _ready():
	ModLoaderLog.info("Done", STORYMODE_LOG)
	# Living lava: the director gives each Story Mode run's map a LavaField.
	var lava = load("res://mods-unpacked/cejdan-StoryMode/lava/lava_director.gd").new()
	lava.name = "LavaDirector"
	add_child(lava)
	# Dev-only lava playtest; does nothing without `-- --lavaprobe=<dir>`.
	var lava_probe = load("res://mods-unpacked/cejdan-StoryMode/lava/dev_lava_probe.gd").new()
	lava_probe.name = "DevLavaProbe"
	add_child(lava_probe)
	add_to_group("mod_init")


# Called by the game once its data is loaded. Story Mode registers its
# game mode here (see the "Mod skeleton" ticket on the map).
func modInit():
	pass
