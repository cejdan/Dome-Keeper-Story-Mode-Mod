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

const Installer = preload("res://mods-unpacked/cejdan-StoryMode/extensions/installer.gd")

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
	# The win condition's section (#144): vanilla Prestige's rocket, as its own
	# copy so Prestige keeps its icon. Fly home rich.
	var rocket: Texture2D = load("res://content/icons/prestige.png")
	if rocket != null:
		var win: ImageTexture = ImageTexture.create_from_image(rocket.get_image())
		win.take_over_path("res://content/icons/storywin.png")
		_held.append(win)
	# Call for Evacuation (#303): vanilla's probe, a signal going out, as its own
	# copy so the probe keeps its icon.
	var probe: Texture2D = load("res://content/icons/probe.png")
	if probe != null:
		var evac: ImageTexture = ImageTexture.create_from_image(probe.get_image())
		evac.take_over_path("res://content/icons/storyevacuate.png")
		_held.append(evac)
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
	# Metal Bit (#147): the gadget's own icon with a half-size Suit Blaster
	# badge (the metal breaker), pixels copied so the palette encoding holds.
	for pair: Array in [["drill", "storydrillmetal"], ["drillbot", "storydrillbotmetal"]]:
		var bit: Texture2D = _badged_icon("res://content/icons/%s.png" % pair[0], "res://content/icons/suitblaster.png")
		if bit != null:
			bit.take_over_path("res://content/icons/%s.png" % pair[1])
			_held.append(bit)
	# Vent the Dome (#213): the dome's own icon, as a placeholder until art exists.
	var dome_icon: Texture2D = load("res://content/icons/dome1.png")
	if dome_icon != null:
		var vent: ImageTexture = ImageTexture.create_from_image(dome_icon.get_image())
		vent.take_over_path("res://content/icons/storyventdome.png")
		_held.append(vent)
	# New Gadget I-IV (#132): a cog with a spark and the tier in pips
	# (art/tools/make_gear_icon.py).
	for i in range(1, 5):
		Assets.provide(Story.MOD_DIR + "art/icons/newgadget%d.png" % i, "res://content/icons/storynewgadget%d.png" % i)

	# Living lava: the director gives each Story Mode run's map a LavaField.
	var lava = load("res://mods-unpacked/cejdan-StoryMode/lava/lava_director.gd").new()
	lava.name = "LavaDirector"
	add_child(lava)
	# Noxious gas (#198): each run's map gets a GasField beside its lava.
	var gas = load("res://mods-unpacked/cejdan-StoryMode/gas/gas_director.gd").new()
	gas.name = "GasDirector"
	add_child(gas)
	# Online multiplayer (#225): the run setup clients don't get from vanilla.
	var net = load("res://mods-unpacked/cejdan-StoryMode/net/story_net.gd").new()
	net.name = "StoryNet"
	add_child(net)
	# Dev-only: F10 jumps the keeper to the next gas pocket; needs `-- --gas`.
	var gas_finder = load("res://mods-unpacked/cejdan-StoryMode/gas/dev_gas_finder.gd").new()
	gas_finder.name = "DevGasFinder"
	add_child(gas_finder)
	# Dev-only lava playtest; does nothing without `-- --lavaprobe=<dir>`.
	var lava_probe = load("res://mods-unpacked/cejdan-StoryMode/lava/dev_lava_probe.gd").new()
	lava_probe.name = "DevLavaProbe"
	add_child(lava_probe)
	# Dev-only: F9 jumps the keeper to the next magma pocket; needs `-- --lava`.
	var lava_finder = load("res://mods-unpacked/cejdan-StoryMode/lava/dev_lava_finder.gd").new()
	lava_finder.name = "DevLavaFinder"
	add_child(lava_finder)
	# Dev-only cheats (#292): a Story Mode column in the F1 panel, and the
	# `--unlockall` / `--money=` / `--gear` launch switches (dev/play_dev.ps1).
	# Added before DevBoot so the unlocks land before the loadout is built.
	if ResourceLoader.exists(Story.MOD_DIR + "dev/dev_cheats.gd"):
		var cheats_script = load(Story.MOD_DIR + "dev/dev_cheats.gd")
		if cheats_script.wanted():
			var dev_cheats = cheats_script.new()
			dev_cheats.name = "DevCheats"
			add_child(dev_cheats)
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
	# Data messages to a peer keep their order in the chunker (#246; see
	# net/ordered_chunker.gd). Set on vanilla's node before any session, so it
	# keeps its name and RPC path. `--vanillachunker` (editor) leaves it vanilla.
	if Network.chunker != null and not (OS.has_feature("editor") and Story.has_user_arg("vanillachunker")):
		Network.chunker.set_script(load(Story.MOD_DIR + "net/ordered_chunker.gd"))
		Network.chunker.set_process(true)
		Data.full_sync_received.connect(Network.chunker.restore_ahead)
		Network.chunker.tally_on = OS.has_feature("editor") and Story.has_user_arg("datasizes")
		# `--heldchunker` (editor): a small delta waits whole behind queued
		# Data and a big one is chunked whole, as before #261 and #268, to
		# show a gadget's keys landing after it.
		Network.chunker.split_on = not (OS.has_feature("editor") and Story.has_user_arg("heldchunker"))
	# Script extensions: each handles Story Mode and defers to vanilla otherwise.
	# They are installed here, not in _init(): loading a vanilla script while
	# ModLoader is still starting up pulls its dependencies in too early, and
	# some of them then fail to parse. Every script that names a class_name
	# they take over is compiled and held first (#252, #256; the list and the
	# reason are in extensions/installer.gd). `--noclasshold` (editor) skips
	# that, to show what it prevents.
	var t0: int = Time.get_ticks_msec()
	Installer.install(_held, not (OS.has_feature("editor") and Story.has_user_arg("noclasshold")))
	ModLoaderLog.info("Script extensions installed (%d ms)" % (Time.get_ticks_msec() - t0), STORYMODE_LOG)
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
	_order_shop_tracks()
	# Heat Shielding prices come from the shared lava data file.
	var LavaData = load(Story.MOD_DIR + "data/lava.gd")
	for i in LavaData.HEAT_SHIELD_PRICES.size():
		var hs: Dictionary = Data.upgrades.get("storyheatshield%d" % (i + 1), {})
		if not hs.is_empty():
			hs["cost"] = {"money": int(LavaData.HEAT_SHIELD_PRICES[i])}
	Data.registerGameMode(Story.MODE_ID)
	GameWorld.unlockElement(Story.MODE_ID)


# The shop draws one track per bought root, in Data.orderedUpgradeKeys order
# (gamemode roots, then domes, keepers, weapons, gadgets). Story Mode's roots
# are parsed last, so they would sit at the bottom. In a Story Mode run (#144):
# the win condition first, then the dome, then Story Mode's own track, then
# the keeper and everything else in vanilla order. Vanilla runs never have
# these roots, so their shop is unchanged.
const WIN_ROOT := "storywin"
const FIRST_KEEPER_ROOT := "keeper1"


func _order_shop_tracks() -> void:
	var keys: Array = Data.orderedUpgradeKeys
	if keys.has(WIN_ROOT):
		keys.erase(WIN_ROOT)
		keys.push_front(WIN_ROOT)
	if keys.has(Story.MODE_ID) and keys.has(FIRST_KEEPER_ROOT):
		keys.erase(Story.MODE_ID)
		keys.insert(keys.find(FIRST_KEEPER_ROOT), Story.MODE_ID)


# `base` with `badge` shrunk to half size in its lower right corner.
func _badged_icon(base: String, badge: String) -> Texture2D:
	var b: Texture2D = load(base)
	var g: Texture2D = load(badge)
	if b == null or g == null:
		return null
	var img: Image = b.get_image().duplicate()
	var mark: Image = g.get_image().duplicate()
	for i: Image in [img, mark]:
		if i.is_compressed():
			i.decompress()
		i.convert(Image.FORMAT_RGBA8)
	mark.resize(mark.get_width() / 2, mark.get_height() / 2, Image.INTERPOLATE_NEAREST)
	var at: Vector2i = img.get_size() - mark.get_size()
	img.blend_rect(mark, Rect2i(Vector2i.ZERO, mark.get_size()), at)
	return ImageTexture.create_from_image(img)


# Called by GameWorld.prepareLevelStart for every mode; vanilla sets nothing up
# for an unknown mode id, so Story Mode does its own level preparation here.
func prepareGameMode(modeId: String, levelStartData: LevelStartData) -> void:
	Prices.apply(modeId == Story.MODE_ID)
	Minerals.use_story_iron(modeId == Story.MODE_ID)
	if modeId != Story.MODE_ID:
		# A loadout that ran Story Mode before keeps its modeConfig (the
		# loadout screen reuses it), flag and all: without this a vanilla run
		# picked there afterwards got Story Mode's lava and gas (#231).
		levelStartData.loadout.modeConfig.erase(Story.MODE_FLAG)
		if Level.loadout != null:
			Level.loadout.modeConfig.erase(Story.MODE_FLAG)
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
	# Story Mode's per-keeper shop entries (#265): a limit per player, as vanilla
	# makes <playerId>.mining available just before this for every keeper.
	var pids: Array = []
	for lk in levelStartData.loadout.keepers:
		pids.append(lk.playerId)
	load(Story.MOD_DIR + "gamemode/keeper_upgrades.gd").add_limits(pids)
	# Story Mode's gentler tile health growth with depth (#148). Vanilla's
	# prepareCleanData sets 2.1 again before every run.
	Data.apply("map.tileHealthMultiplierPerLayer", MapConfig.TILE_HEALTH_PER_BIOME)
	levelStartData.loadout.modeConfig.erase(CONST.MODE_CONFIG_WORLDMODIFIERS)
	levelStartData.mapArchetype = MapConfig.make_archetype()
	GameWorld.prepareRegularLevelStart(levelStartData)
