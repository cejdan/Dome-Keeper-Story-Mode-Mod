extends Node

const STORYMODE_LOG = "cejdan-StoryMode"
const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const Assets = preload("res://mods-unpacked/cejdan-StoryMode/util/assets.gd")
const MapConfig = preload("res://mods-unpacked/cejdan-StoryMode/data/map_config.gd")
const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")
const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")
const Palette = preload("res://mods-unpacked/cejdan-StoryMode/util/palette.gd")
const Prices = preload("res://mods-unpacked/cejdan-StoryMode/data/prices.gd")
const Strings = preload("res://mods-unpacked/cejdan-StoryMode/text/strings.gd")

const EXT := "res://mods-unpacked/cejdan-StoryMode/extensions/"

# Kept alive so resources that took over a vanilla path stay in the cache.
var _held: Array = []


func _init():
	ModLoaderLog.info("Init", STORYMODE_LOG)


func _ready():
	Strings.register()
	# The game looks the mode's scene and icon up by id at fixed vanilla paths.
	var scene: PackedScene = load(Story.MOD_DIR + "gamemode/Storymode.tscn")
	scene.take_over_path("res://content/gamemode/storymode/Storymode.tscn")
	_held.append(scene)
	Assets.provide(Story.MOD_DIR + "art/loadout_storymode.png", "res://content/icons/loadout_storymode.png")

	# Living lava: the director gives each Story Mode run's map a LavaField.
	var lava = load("res://mods-unpacked/cejdan-StoryMode/lava/lava_director.gd").new()
	lava.name = "LavaDirector"
	add_child(lava)
	# Dev-only lava playtest; does nothing without `-- --lavaprobe=<dir>`.
	var lava_probe = load("res://mods-unpacked/cejdan-StoryMode/lava/dev_lava_probe.gd").new()
	lava_probe.name = "DevLavaProbe"
	add_child(lava_probe)
	# Dev-only: F9 jumps the keeper to the next magma pocket; needs `-- --lava`.
	var lava_finder = load("res://mods-unpacked/cejdan-StoryMode/lava/dev_lava_finder.gd").new()
	lava_finder.name = "DevLavaFinder"
	add_child(lava_finder)
	# Dev-only boot switches (`-- --story`, `--mode=`, `--loadout`, `--scenario=`).
	if ResourceLoader.exists(Story.MOD_DIR + "dev/dev_boot.gd"):
		var boot_script = load(Story.MOD_DIR + "dev/dev_boot.gd")
		if boot_script.wanted():
			var boot = boot_script.new()
			boot.name = "DevBoot"
			add_child(boot)
	# Dev-only playtest harness; needs the dev/ folder and `-- --scenario=<name>`.
	if OS.has_feature("editor") and Story.user_arg("scenario") != "" and ResourceLoader.exists(Story.MOD_DIR + "dev/harness.gd"):
		var harness = load(Story.MOD_DIR + "dev/harness.gd").new()
		harness.name = "PlaytestHarness"
		add_child(harness)
	add_to_group("mod_init")
	add_to_group("gamemodes-prepare")
	ModLoaderLog.info("Done", STORYMODE_LOG)


func _process(_delta: float) -> void:
	Palette.keep_filled()


# Called by the game once its data is loaded.
func modInit():
	# Script extensions: each handles Story Mode and defers to vanilla otherwise.
	# They are installed here, not in _init(): loading a vanilla script while
	# ModLoader is still starting up pulls its dependencies in too early, and
	# some of them then fail to parse.
	for path: String in [
		"stages/loadout/MultiplayerloadoutStage.gd",
		"content/hud/inventory/Inventory.gd",
		"content/techtree/Tech2.gd",
		"content/techtree/TechTreePopup.gd",
		"content/map/Map.gd",
		"content/map/tile/Tile.gd",
		"content/map/tile/DirtParticle.gd",
		"content/dome/Dome.gd",
		"content/map/generation/TileDataGenerator.gd",
		"content/gadgets/suitblaster/SuitblasterExplosion.gd",
	]:
		ModLoaderMod.install_script_extension(EXT + path)
	# Scenes that were already loaded still hold the vanilla script; reload them
	# so their nodes pick up the extension.
	for scene_path: String in [
		"res://content/techtree/Tech2.tscn",
		"res://content/techtree/TechTreePopup.tscn",
		"res://content/map/Map.tscn",
		"res://content/map/tile/Tile.tscn",
		"res://content/map/tile/DirtParticle.tscn",
		"res://content/map/tile/TileBreakParticles.tscn",
		"res://content/dome/Dome.tscn",
		"res://content/map/generation/TileDataGenerator.tscn",
		"res://content/gadgets/suitblaster/SuitblasterExplosion.tscn",
	]:
		if ResourceLoader.has_cached(scene_path):
			_held.append(ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REPLACE))
	Minerals.register()
	Metal.register()
	Data.registerGameMode(Story.MODE_ID)
	GameWorld.unlockElement(Story.MODE_ID)


# Called by GameWorld.prepareLevelStart for every mode; vanilla sets nothing up
# for an unknown mode id, so Story Mode does its own level preparation here.
func prepareGameMode(modeId: String, levelStartData: LevelStartData) -> void:
	Prices.apply(modeId == Story.MODE_ID)
	Minerals.use_story_iron(modeId == Story.MODE_ID)
	if modeId != Story.MODE_ID:
		return
	levelStartData.loadout.modeConfig[Story.MODE_FLAG] = true
	levelStartData.loadout.modeConfig.erase(CONST.MODE_CONFIG_WORLDMODIFIERS)
	levelStartData.mapArchetype = MapConfig.make_archetype()
	GameWorld.prepareRegularLevelStart(levelStartData)
