extends Node

# Dev boot switches (editor binary only). Vanilla dev mode always boots a
# hard-coded Versus run; these user args (after `--`) boot something else:
#   --story              a Story Mode run (same as --mode=storymode)
#   --mode=<id>          a run in that game mode (e.g. relichunt, for vanilla checks)
#   --loadout            the loadout screen
#   --seed=<n>           fixed map seed
#   --gadget=<id>        primary gadget (default shield)
#   --difficulty=<n>     -2, -1, 0 or 2
#   --world=<worldN>     fixed world; --palette=<name> fixed palette
#   --mapsize=<id>       map size id (regular-small/-medium/-large/-huge); default
#                        regular-medium, but regular-huge (the full map) for Story Mode (#320)
#   --load=<slot>        load the save in that slot (singleplayer folder), e.g. one a
#                        scenario wrote with SaveGame.saveGame(..., slot, true)
#   --dlckeepers         with --load: let a save with a DLC keeper (keeper3, or
#                        keeper4 the Beastmaster) load on a machine whose Steam
#                        account does not own the keeper DLC (see below)
#   --horror-defeated    with --story: play the saved ending (#97) once the keeper
#                        can move (handled by gamemode/Storymode.gd)
#   --nethost            host an online (ENet) session, then open the loadout (#223)
#   --netload=<slot>     load the online save in that slot (multiplayer folder) the
#                        way Continue Multiplayer does (#232): it hosts the session the
#                        save names and opens the keeper choice; the host's scenario
#                        picks keepers and starts the run there
#   --netjoin            join the ENet session on 127.0.0.1; the host's stages follow
#   --title              the title screen (#231)
#   --splitscreen        with --loadout: open it as the title's Splitscreen button
#                        does (#231); each device that presses a key joins
# A playtest scenario's boot() dictionary can give the same keys.
#
# How: Game.gd cannot be script-extended safely (loading it early enough breaks
# the parsing of other vanilla scripts). Instead this node puts a DomeEditorConf
# in the resource cache at the path Game._ready() reads, asking for a play mode
# that does not exist. Vanilla then starts no stage at all, and this node starts
# the wanted one on the next frame. No vanilla file is touched.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow

var _conf: Resource
var _mode_id: String = ""
var _done: bool = false


static func wanted() -> bool:
	if not OS.has_feature("editor"):
		return false
	for n: String in ["story", "scenario", "mode", "loadout", "load", "netload", "nethost", "netjoin", "title"]:
		if _Story.has_user_arg(n):
			return true
	return false


func _ready() -> void:
	_mode_id = _Story.user_arg("mode", "")
	if _mode_id == "" and not _Story.has_user_arg("loadout"):
		_mode_id = Story.MODE_ID
	_conf = load("res://addons/dome_editor_ext/dome_editor_conf.gd").new()
	_conf.custom_play_pressed = true
	_conf.play_mode = 99
	_conf.take_over_path(Const.EDITOR_CONF_PATH)


func _process(_delta: float) -> void:
	if _done or get_tree().current_scene == null:
		return
	_done = true
	set_process(false)
	if _Story.has_user_arg("title"):
		# The title screen, as a player starts (#231: its Splitscreen button).
		print("RUNNING IN DEV MODE (Story Mode dev boot: title)")
		StageManager.startStage("stages/title/title")
		return
	if _Story.has_user_arg("netjoin"):
		# A second instance on this machine joins the host. Vanilla's client
		# path shows the loading stage and follows whatever stage the host is in.
		print("RUNNING IN DEV MODE (Story Mode dev boot: join 127.0.0.1)")
		Network.create_enet_client("127.0.0.1", Network.ENET_LISTEN_PORT)
		return
	if _Story.has_user_arg("netload"):
		var nslot: int = int(_Story.user_arg("netload"))
		print("RUNNING IN DEV MODE (Story Mode dev boot: load online save slot %d)" % nslot)
		StageManager.startStage("stages/title/title")
		while StageManager.currentStage == null or StageManager.isSwitchingStage():
			await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
		# TitleStage.continue_multiplayer: once the save's keepers are read,
		# the keeper choice opens; its start button lets loadGame() go on.
		SaveGame.keeper_data_loaded.connect(func(): StageManager.startStage("stages/deviceselection/deviceselection"), CONNECT_ONE_SHOT)
		var nerr = await SaveGame.loadGame("multiplayer", nslot)
		if nerr != OK:
			push_error("Dev boot: loading online save slot %d failed (%s)" % [nslot, str(nerr)])
		return
	if _Story.has_user_arg("nethost"):
		print("RUNNING IN DEV MODE (Story Mode dev boot: host ENet session)")
		if _Story.has_user_arg("splitscreen"):
			# Online with local splitscreen on the host (#231): the option's
			# setting, for this run only (not saved).
			Options.enableSplitScreen = true
		Network.create_enet_host()
		StageManager.startStage("stages/loadout/multiplayerloadout")
		return
	if _Story.has_user_arg("load"):
		var slot: int = int(_Story.user_arg("load"))
		print("RUNNING IN DEV MODE (Story Mode dev boot: load slot %d)" % slot)
		# Load from the title stage, as the Continue button does. With no stage
		# running, StageManager starts the landing stage synchronously and
		# loadGame() misses one of the two stage_started signals it waits for.
		StageManager.startStage("stages/title/title")
		while StageManager.currentStage == null or StageManager.isSwitchingStage():
			await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
		if _Story.has_user_arg("dlckeepers"):
			_unlock_dlc_keepers()
		var err = await SaveGame.loadGame("singleplayer", slot)
		if err != OK:
			push_error("Dev boot: loading save slot %d failed (%s)" % [slot, str(err)])
	elif _mode_id == "":
		if _Story.has_user_arg("splitscreen"):
			# The title's Splitscreen button (#231): the loadout then adds a
			# local keeper for each device that presses a key.
			print("RUNNING IN DEV MODE (Story Mode dev boot: splitscreen loadout)")
			Network.multiplayer_mode = Network.MultiplayerMode.OFFLINE_SPLITSCREEN
		StageManager.startStage("stages/loadout/multiplayerloadout")
	else:
		_start_run(_mode_id)


func _start_run(mode_id: String) -> void:
	print("RUNNING IN DEV MODE (Story Mode dev boot: " + mode_id + ")")
	if _Story.has_user_arg("seed"):
		Level.setSeed(int(_Story.user_arg("seed")))
	var loadout: Loadout = Loadout.default()
	var ld1: LoadoutDome = LoadoutDome.new()
	ld1.primaryGadgetId = _Story.user_arg("gadget", "shield")
	ld1.domeId = _Story.user_arg("dome", "dome1")
	ld1.teamId = "team1"
	ld1.petId = ""
	ld1.additionalGadgets = []
	loadout.domes = [ld1]
	loadout.modeId = mode_id
	loadout.modeConfig = {CONST.MODE_CONFIG_MAP_ARCHETYPE: _Story.user_arg("mapsize", CONST.MAP_HUGE if mode_id == _Story.MODE_ID else CONST.MAP_MEDIUM)}
	var diff: int = int(_Story.user_arg("difficulty", "0"))
	loadout.difficultyByTeamId = {"team1": diff, "map": diff}
	loadout.worldId = _Story.user_arg("world", "")
	loadout.palette = _Story.user_arg("palette", "")
	var lk1: LoadoutKeeper = LoadoutKeeper.new()
	lk1.playerId = "player1"
	lk1.teamId = "team1"
	lk1.keeperId = _Story.user_arg("keeper", "keeper1")
	lk1.skinId = "skin0"
	lk1.deviceId = 0
	lk1.peerId = 1
	lk1.tutorialsActive = false
	loadout.keepers = [lk1]
	Lobby.simple_add(lk1.deviceId)
	var member = Lobby.get_member_by_player_id(lk1.playerId)
	member.keeper_id = Utils.encode_tech_id(lk1.keeperId)
	Lobby.send_lobby_update()
	var startData: LevelStartData = LevelStartData.new()
	startData.loadout = loadout
	StageManager.startStage("stages/landing/landing", [startData])


# `--dlckeepers` (playtests only): vanilla SaveGame.loadGame refuses an offline
# save whose keeper is a DLC keeper (Data.dlcKeepers) not in
# GameWorld.unlockedElements ("unavailable dlc keeper content",
# ERR_UNAUTHORIZED). At boot SaveGame takes those keepers out of the list
# unless Steam says the DLC is owned (GameWorld.update_keeper_dlc), so on a
# machine without the DLC a Beastmaster save made by a scenario can't be
# reloaded. This puts just the keepers back in this run's lists before the
# load, with their base skin (skin0, which the same boot step takes away; with
# no skin left, Data.sanitizeLoadout errors on the load), as
# update_keeper_dlc(true) would. Vanilla does that itself for an online save
# with unowned DLC content. DLC pets, other skins and assignments stay checked.
# Only this node calls it: it lives in dev/, which release/package_mod.py
# leaves out of the mod, and DevBoot runs only on the editor binary (wanted()).
func _unlock_dlc_keepers() -> void:
	for k: String in Data.dlcKeepers:
		if not GameWorld.isUnlocked(k):
			GameWorld.unlockElement(k)
			GameWorld.unlockSkin(k, "skin0")
			print("Dev boot: --dlckeepers unlocked %s for this load" % k)
