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
	# The Story Mode track's root in the shop (#134): the same drawing,
	# palette-encoded like vanilla tech icons (art/tools/make_horror_icon.py).
	Assets.provide(Story.MOD_DIR + "art/icons/storymode.png", "res://content/icons/storymode.png")
	# Retire Rich: the money coin, blown up to a tech icon.
	var coin: Image = Assets.image(Story.MOD_DIR + "art/icon_money.png")
	if coin != null:
		coin = coin.duplicate()
		var f: int = maxi(1, 72 / maxi(coin.get_width(), coin.get_height()))
		coin.resize(coin.get_width() * f, coin.get_height() * f, Image.INTERPOLATE_NEAREST)
		var sq2: Image = Image.create(72, 72, false, coin.get_format())
		sq2.blit_rect(coin, Rect2i(Vector2i.ZERO, coin.get_size()), (Vector2i(72, 72) - coin.get_size()) / 2)
		var rr: ImageTexture = ImageTexture.create_from_image(sq2)
		rr.take_over_path("res://content/icons/storyretirerich.png")
		_held.append(rr)
	# Heat Shielding I-IV: the carry (suit) icon pushed hotter along palette
	# row 12, as a placeholder until art exists.
	var suit: Texture2D = load("res://content/icons/jetpackstrength1.png")
	if suit != null:
		var hot: Image = suit.get_image().duplicate()
		if hot.is_compressed():
			hot.decompress()
		hot.convert(Image.FORMAT_RGBA8)
		for y in hot.get_height():
			for x in hot.get_width():
				var px: Color = hot.get_pixel(x, y)
				var col: int = int(round(px.r8 / 8.0))
				if px.a > 0.0 and col >= 18:
					px.r8 = mini(31, col + 3) * 8
					hot.set_pixel(x, y, px)
		for i in 4:
			var t: ImageTexture = ImageTexture.create_from_image(hot)
			t.take_over_path("res://content/icons/storyheatshield%d.png" % (i + 1))
			_held.append(t)
	# New Gadget I-IV (#132): a cog with a spark and the tier in pips
	# (art/tools/make_gear_icon.py).
	for i in range(1, 5):
		Assets.provide(Story.MOD_DIR + "art/icons/newgadget%d.png" % i, "res://content/icons/storynewgadget%d.png" % i)

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
		"content/techtree/TechTree.gd",
		"content/techtree/TechTreePopup.gd",
		"content/map/Map.gd",
		"content/map/tile/Tile.gd",
		"content/map/tile/DirtParticle.gd",
		"content/dome/Dome.gd",
		"content/map/generation/TileDataGenerator.gd",
		"content/gadgets/suitblaster/SuitblasterExplosion.gd",
		"stages/level/LevelStage.gd",
		"content/caves/treecave/Iron.gd",
		"content/gadgets/mineraltree/FruitGrowth.gd",
		"content/gadgets/mineraltree/MineralTree.gd",
	]:
		ModLoaderMod.install_script_extension(EXT + path)
	# Scenes that were already loaded still hold the vanilla script; reload them
	# so their nodes pick up the extension.
	for scene_path: String in [
		"res://content/techtree/Tech2.tscn",
		"res://content/techtree/TechTree.tscn",
		"res://content/techtree/TechTreePopup.tscn",
		"res://content/map/Map.tscn",
		"res://content/map/tile/Tile.tscn",
		"res://content/map/tile/DirtParticle.tscn",
		"res://content/map/tile/TileBreakParticles.tscn",
		"res://content/dome/Dome.tscn",
		"res://content/map/generation/TileDataGenerator.tscn",
		"res://content/gadgets/suitblaster/SuitblasterExplosion.tscn",
		"res://stages/level/LevelStage.tscn",
		"res://content/caves/treecave/IronTreeCave.tscn",
		"res://content/gadgets/mineraltree/MineralTree.tscn",
	]:
		if ResourceLoader.has_cached(scene_path):
			_held.append(ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_REPLACE))
	Minerals.register()
	Metal.register()
	# Miner bones (#94): a tile id and a carried, sellable drop.
	load(Story.MOD_DIR + "data/bones.gd").register()
	# The translator (#93): carried home like a relic.
	if not Data.DROP_TYPES.has("translator"):
		Data.DROP_TYPES.append("translator")
	Data.DROP_SCENES["translator"] = load(Story.MOD_DIR + "drops/translator_drop.tscn")
	# The mod's own shop entries (data/upgrades.yaml), through vanilla's parser.
	# Its root `storymode` is a gamemode upgrade: vanilla adds it to a run only
	# when the run's mode id is "storymode", so vanilla modes never see them.
	# The parser stores an entry only when it reaches a blank line, so every
	# entry in that file, the last one too, must be followed by one.
	Data.parseUpgradesYaml(Story.MOD_DIR + "data/upgrades.yaml")
	# Heat Shielding prices come from the shared lava data file.
	var LavaData = load(Story.MOD_DIR + "data/lava.gd")
	for i in LavaData.HEAT_SHIELD_PRICES.size():
		var hs: Dictionary = Data.upgrades.get("storyheatshield%d" % (i + 1), {})
		if not hs.is_empty():
			hs["cost"] = {"money": int(LavaData.HEAT_SHIELD_PRICES[i])}
	Data.registerGameMode(Story.MODE_ID)
	GameWorld.unlockElement(Story.MODE_ID)


# Called by GameWorld.prepareLevelStart for every mode; vanilla sets nothing up
# for an unknown mode id, so Story Mode does its own level preparation here.
func prepareGameMode(modeId: String, levelStartData: LevelStartData) -> void:
	Prices.apply(modeId == Story.MODE_ID)
	Minerals.use_story_iron(modeId == Story.MODE_ID)
	if modeId != Story.MODE_ID:
		return
	# A loaded run keeps its level seed (#116). Vanilla saves don't store it, so
	# a fresh process rolled a new one: a new palette (picked from the seed right
	# after this), and the saved lava rejected as another map's. The seed rides
	# in the saved map data (gamemode/Storymode.gd writes it).
	var td = levelStartData.tileData
	if levelStartData.savegame and td != null and td.has_meta(Story.SEED_META):
		var saved: int = int(td.get_meta(Story.SEED_META))
		if saved != Level.levelSeed:
			ModLoaderLog.info("Loaded run: level seed %d restored (was rolled as %d)" % [saved, Level.levelSeed], Story.LOG)
			Level.levelSeed = saved
	levelStartData.loadout.modeConfig[Story.MODE_FLAG] = true
	levelStartData.loadout.modeConfig.erase(CONST.MODE_CONFIG_WORLDMODIFIERS)
	levelStartData.mapArchetype = MapConfig.make_archetype()
	GameWorld.prepareRegularLevelStart(levelStartData)
