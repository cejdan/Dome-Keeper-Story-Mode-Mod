extends Node

# The Story Mode game mode node. LevelStage loads it from
# res://content/gamemode/storymode/Storymode.tscn (the mod takes over that path)
# and calls init(), afterInitialized() and getRunWeight().

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
const Runes = preload("res://mods-unpacked/flantor-StoryMode/pleas/runes.gd")
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
const SalePops = preload("res://mods-unpacked/flantor-StoryMode/hud/sale_pops.gd")
const KeeperUpgrades = preload("res://mods-unpacked/flantor-StoryMode/gamemode/keeper_upgrades.gd")

const MONEY := "team1.inventory.money"

var runWeightOverride: int = -1
var _lost: bool = false


func init() -> void:
	# The horror's story beats (#23); fired through beats/story_beats.gd.
	add_child(load(Story.MOD_DIR + "beats/story_beats.gd").new())
	# The story endings (#96, #97).
	var endings = load(Story.MOD_DIR + "endings/ending_director.gd").new()
	endings.name = "StoryEndings"
	add_child(endings)
	# The monsters' pleas during waves (#91).
	add_child(load(Story.MOD_DIR + "pleas/plea_director.gd").new())
	# "+$5" over the dome for each piece sold (#121).
	add_child(SalePops.new())
	# The keeper's lines about the depth heat (#146).
	add_child(load(Story.MOD_DIR + "hud/heat_talk.gd").new())
	# The boss sequence: Velle's chamber fight and what follows (#160).
	add_child(load(Story.MOD_DIR + "boss/boss_director.gd").new())
	Data.listen(self, "team1.dome.health")
	# upgradeAdded is the host's one signal for every purchase, a client's too (#229).
	GameWorld.upgradeAdded.connect(_on_upgrade_added)
	# Per-keeper shop entries (#265): a loaded save gets its keepers' limits, and
	# one from before #265 has the team's Heat Shielding tier moved to every
	# keeper, once vanilla has restored the upgrades and Data.
	if SaveGame.currentLoadingSavegame and multiplayer.is_server():
		GameWorld.savegame_loaded.connect(KeeperUpgrades.after_load, CONNECT_ONE_SHOT)
	ModLoaderLog.info("Story Mode run started (seed %d)" % Level.levelSeed, Story.LOG)


func afterInitialized() -> void:
	# Every player sees the money (#225); the rest is the host's.
	Level.addHudElement(load(Story.MOD_DIR + "hud/MoneyHud.tscn"), "team1")
	if not multiplayer.is_server():
		return
	# The level seed goes into the map data, which every save writes out, so a
	# load can restore it (#116, mod_main.gd prepareGameMode). A loaded map has it
	# already; an older save gets it from here on.
	if Level.map != null and Level.map.tileData != null and not Level.map.tileData.has_meta(Story.SEED_META):
		Level.map.tileData.set_meta(Story.SEED_META, Level.levelSeed)
	# Vanilla dev mode hands out 500 iron, 50 water and 20 cobalt; a Story Mode
	# run starts with empty pockets either way. A loaded save keeps its values.
	# A new run: the company's welcome memo opens once the keeper can move (#123).
	# A save restores Data after this runs, so a load is told apart by its flag.
	if not SaveGame.currentLoadingSavegame:
		_welcome()
	# The win condition's shop section (#144): vanilla adds only the mode's own
	# root, so the second root is added here, then its Retire Rich unlocked.
	# A save made before #144 gets it on load too.
	if not GameWorld.boughtUpgrades.has("team1." + WIN_ROOT):
		GameWorld.addUpgrade(WIN_ROOT, "team1")
		GameWorld.updateAvailableUpgrades("team1")
	# Story-only upgrades on vanilla tracks (#147) need the storyonly limit, which
	# the storymode root unlocks; a save made before it gets it here.
	if not GameWorld.isUpgradeLimitAvailable("team1.storyonly"):
		GameWorld.setUpgradeLimitAvailable("team1.storyonly")
		GameWorld.updateAvailableUpgrades("team1")
	if not Data.has(MONEY):
		Data.apply(MONEY, 0)
		Data.apply("team1.inventory.iron", 0)
		Data.apply("team1.inventory.water", 0)
		Data.apply("team1.inventory.sand", 0)
	for m: String in Minerals.ORDER:
		if not Data.has("team1.inventory." + m):
			Data.apply("team1.inventory." + m, 0)
		Data.listen(self, "team1.inventory." + m)
	# Translators installed at the dome (#93).
	Data.listen(self, "team1.inventory.translator")
	if OS.has_feature("editor") and Story.has_user_arg("horror-defeated"):
		_dev_horror_defeated()


# The keeper's own log (#123): Halcyon's welcome memo, a moment after the run
# hands the keeper control, so the dome is on screen first. New runs only; a
# loaded save never shows it.
const WELCOME_DELAY := 1.2


func _welcome() -> void:
	while Level.stage == null or not Level.stage.keeperInputStarted:
		await get_tree().process_frame
	await get_tree().create_timer(WELCOME_DELAY, false).timeout
	StoryBeats.fire(load(Story.MOD_DIR + "data/logs.gd").WELCOME)


# Retire Rich (#31, #54): the only way to win a Story Mode run until the boss.
const RETIRE_ENTRY := "storyretirerich"
# Retire Rich's own root, the shop's top section (#144).
const WIN_ROOT := "storywin"
# Call for Evacuation (#303): free, refused. Halcyon's reply opens; nothing else.
const EVACUATE_ENTRY := "storyevacuate"


# The shop's Suit Blaster entry is a stand-in: buying it grants the real gadget
# the way a gadget chest does (#18), to that keeper only (#265: the entry is
# per keeper, player2.storysuitblaster -> player2.suitblaster), as vanilla
# gives a keepersuit gadget to the keeper who picked it.
func _on_upgrade_added(id: String, teamId: String) -> void:
	if not multiplayer.is_server():
		return
	if id == teamId + "." + RETIRE_ENTRY:
		_win()
		return
	if id == teamId + "." + EVACUATE_ENTRY:
		StoryBeats.fire(load(Story.MOD_DIR + "data/logs.gd").EVACUATION)
		return
	if not id.begins_with("player") or not id.ends_with("." + KeeperUpgrades.BLASTER_ENTRY):
		return
	var pid: String = id.substr(0, id.find("."))
	var gid: String = pid + ".suitblaster"
	if not GameWorld.boughtUpgrades.has(gid):
		GameWorld.serverAddUpgrade(gid, teamId)
		ModLoaderLog.info("Suit Blaster granted to " + pid, Story.LOG)


func propertyChanged(property: String, oldValue, newValue) -> void:
	# A mineral delivered to the dome pays its dollar value. Inventory counts only
	# ever rise from deliveries; Story Mode never spends minerals.
	if property == "team1.inventory.translator":
		# Each translator the dome takes in moves the pleas one stage closer to
		# English, and the horror objects (#93).
		var n: int = int(newValue) if newValue != null else 0
		if n > (int(oldValue) if oldValue != null else 0):
			Runes.set_stage(n)
			StoryBeats.trigger("translator:%d" % n)
			ModLoaderLog.info("Translator %d installed: plea stage %d" % [n, Runes.stage()], Story.LOG)
		return
	if property.begins_with("team1.inventory."):
		var type: String = property.substr(16)
		if Minerals.is_mineral(type) and oldValue != null and newValue > oldValue:
			var pieces: int = int(newValue - oldValue)
			Data.changeByInt(MONEY, pieces * Minerals.value_of(type))
			Data.changeByInt("team1.story.pieces", pieces)
			for _i in pieces:
				SalePops.pop(Minerals.value_of(type))
		return
	match property:
		"team1.dome.health":
			if newValue <= 0 and not GameWorld.lost and not _lost and not Data.ofOr("team1.dome.healthlocked", false):
				if Data.ofOr("team1.inventory.sand", 0) > 0 and Data.ofOr("team1.dome.autorepair", false):
					return
				_lose()


var _ending: bool = false


# Retire Rich: the doom ending (#96), then vanilla Relic Hunt's win, minus the
# relic and the final wave. Still a won run with the $1M.
func _win() -> void:
	if not _can_end():
		return
	_ending = true
	ModLoaderLog.info("Retire Rich bought: the run is won", Story.LOG)
	await _stop_play()
	var endings = get_node_or_null("StoryEndings")
	if endings != null:
		await endings.play_doom()
	var Endings = load(Story.MOD_DIR + "data/endings.gd")
	await _end_won(Endings.DOOM_TITLE, Endings.DOOM_SUBTITLE)


# The saved ending's hook (#97). The future boss fight calls this when the horror
# is defeated: Level.mode.horror_defeated(). It plays the saved ending (narration
# cards), then ends the run as a win on the end screen "The Planet Is Saved".
# Returns false, and does nothing, when the run is already won, lost or playing
# an ending; true when the ending started. The ending runs on its own; the
# caller need not await it. The boss director calls it when the finale is won;
# so does `-- --story --horror-defeated` once keeper input has started.
func horror_defeated() -> bool:
	if not multiplayer.is_server() or not _can_end():
		return false
	_ending = true
	_saved_ending()
	return true


func _saved_ending() -> void:
	ModLoaderLog.info("The horror is defeated: the planet is saved", Story.LOG)
	await _stop_play()
	var endings = get_node_or_null("StoryEndings")
	if endings != null:
		await endings.play_saved()
	var Endings = load(Story.MOD_DIR + "data/endings.gd")
	await _end_won(Endings.SAVED_TITLE, Endings.SAVED_SUBTITLE)


func _can_end() -> bool:
	return not (GameWorld.won or GameWorld.lost or _lost or _ending)


# True while an ending plays or the run is lost: story beats wait (#96, #97).
func is_ending() -> bool:
	return _ending or _lost


# Online (#229): the host runs every story ending (Retire Rich's doom, the
# saved ending, the boss's lost ending) and tells the clients each step: the
# start (_net_ending_start), the cards (StoryEndings._net_cards), the end screen
# (_end_won / _end_fallen). This is the one way an ending reaches a client; the
# boss director only decides on the host (#230). The dome falling is vanilla's
# way instead: every instance sees team1.dome.health reach 0 and runs _lose().
# Clients in the level get `call`; offline there are none.
func _to_clients(call: Callable) -> void:
	if not Network.is_offline_mode() and multiplayer.is_server():
		Network.rpc_if_state(call, Network.ConnectionState.LEVEL_STAGE_SYNC)


# Frames left until a client's input processors are cleared for an ending
# (the ending's boxes integrate after that); see beats/story_beats.gd.
var _settle: int = 0


func settling() -> bool:
	return _settle > 0


func _process(_delta: float) -> void:
	if _settle > 0:
		_settle -= 1


# Host to clients: an ending starts; this player's controls go too.
@rpc("authority", "call_remote", "reliable")
func _net_ending_start(lost: bool) -> void:
	if _ending or _lost:
		return
	if lost:
		_lost = true
	else:
		_ending = true
	_settle = 4
	_stop_play()


# Takes the keeper's controls and ends the waves, for an ending.
func _stop_play() -> void:
	_to_clients(_net_ending_start.bind(_lost))
	Level.stage.stopKeeperInput()
	for mm in get_tree().get_nodes_in_group("monster-manager"):
		mm.disabled = true
		if mm.has_method("instantlyKillWave"):
			mm.instantlyKillWave()
	# stopKeeperInput clears every input processor (the shop's too) on the input
	# system's next frame; the ending's own boxes integrate after that.
	for i in 3:
		await get_tree().process_frame


# Vanilla Relic Hunt's win, with the end screen retitled for the ending played.
# Online, every player's instance runs it (the host's call).
@rpc("authority", "call_remote", "reliable")
func _end_won(title: String, subtitle: String) -> void:
	_to_clients(_end_won.bind(title, subtitle))
	GameWorld.handleGameWon()
	Audio.stopBattleMusic()
	await get_tree().create_timer(2.5).timeout
	Audio.startEnding()
	await get_tree().create_timer(4.0).timeout
	var popup = load("res://content/gamemode/relichunt/RunFinishedPopup.tscn").instantiate()
	popup.init(multiplayer.is_server())
	load(Story.MOD_DIR + "endings/ending_director.gd").retitle(popup, title, subtitle)
	_show_end(popup)


# End screens shown on this instance (a playtest checks there is one).
var end_screens: int = 0


# Shows the run's end screen, once per run on this instance. A client still
# reading the ending's cards when the host's end screen comes has them closed.
func _show_end(popup, delete_autosave: bool = true) -> void:
	if end_screens > 0:
		popup.queue_free()
		ModLoaderLog.warning("A second end screen was refused", Story.LOG)
		return
	end_screens += 1
	var endings = get_node_or_null("StoryEndings")
	if endings != null and not multiplayer.is_server():
		endings.close_cards()
	Level.stage.showEndingPanel(popup)
	if delete_autosave:
		SaveGame.delete_autosave()


# Dev command (editor only): `-- --story --horror-defeated` plays the saved
# ending as soon as the keeper can move.
func _dev_horror_defeated() -> void:
	while Level.stage == null or not Level.stage.keeperInputStarted:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	ModLoaderLog.info("Dev command: horror defeated", Story.LOG)
	horror_defeated()


func _lose() -> void:
	_lost = true
	# The dome fell while it fought Velle's tentacles (#162): the lost ending.
	var boss = get_node_or_null("StoryBoss")
	var fallen: bool = boss != null and Story.boss_active()
	if fallen and multiplayer.is_server():
		boss.dome_lost()
	Level.moveHudOut()
	GameWorld.lost = true
	var delay: float = Level.stage.playGameLostAnimation()
	await get_tree().create_timer(delay).timeout
	Audio.sound("lose")
	await get_tree().create_timer(0.2).timeout
	GameWorld.handleGameLost()
	Audio.startGameOver(1.0)
	await get_tree().create_timer(5.0).timeout
	var popup = load("res://content/gamemode/relichunt/RunFinishedPopup.tscn").instantiate()
	popup.init(multiplayer.is_server())
	if fallen:
		var BossText = load(Story.MOD_DIR + "data/boss_text.gd")
		load(Story.MOD_DIR + "endings/ending_director.gd").retitle(popup, BossText.FALLEN_TITLE, BossText.FALLEN_SUBTITLE)
	_show_end(popup, false)


# The keeper died in the boss sequence (#160): the run ends in failure. The
# boss director calls this once, on the host; clients follow (#229).
func keeper_lost() -> void:
	if not multiplayer.is_server() or not _can_end():
		return
	_lost = true
	ModLoaderLog.info("The keeper is lost: the run ends in failure", Story.LOG)
	await _stop_play()
	# The lost ending (#162): the planet's end, told in cards.
	var endings = get_node_or_null("StoryEndings")
	if endings != null:
		await get_tree().create_timer(1.5).timeout
		await endings.play_fallen()
	await _end_fallen()


# The lost ending's end screen. Online, every player's instance runs it.
@rpc("authority", "call_remote", "reliable")
func _end_fallen() -> void:
	_to_clients(_end_fallen)
	Level.moveHudOut()
	GameWorld.lost = true
	await get_tree().create_timer(1.2).timeout
	Audio.sound("lose")
	await get_tree().create_timer(0.2).timeout
	GameWorld.handleGameLost()
	Audio.startGameOver(1.0)
	await get_tree().create_timer(5.0).timeout
	var popup = load("res://content/gamemode/relichunt/RunFinishedPopup.tscn").instantiate()
	popup.init(multiplayer.is_server())
	var BossText = load(Story.MOD_DIR + "data/boss_text.gd")
	load(Story.MOD_DIR + "endings/ending_director.gd").retitle(popup, BossText.FALLEN_TITLE, BossText.FALLEN_SUBTITLE)
	_show_end(popup)


# Vanilla Relic Hunt's run weight (Relichunt.gd). Story Mode's own iron term
# arrives with the waves ticket.
func getRunWeight(teamId: String) -> float:
	if runWeightOverride != -1:
		return float(runWeightOverride)
	var weight: float = 10.0 + float(Data.ofOr(teamId + ".monsters.additionalwaveweight", 0))
	# Relic Hunt's run weight, except that every delivered mineral piece (bronze
	# through unobtainium, iron included) counts as one iron (#30, #53).
	weight += Data.ofOr(teamId + ".story.pieces", 0) * 0.6
	weight += Data.ofOr("inventory.totalsand", 0) * 2.2
	weight += Data.ofOr("inventory.totalwater", 0) * 1.2
	weight += Data.ofOr(teamId + ".inventory.gadget", 0) * 8
	weight += Data.ofOr(teamId + ".inventory.powercore", 0) * 8
	var cycle = Data.of(teamId + ".monsters.cycle")
	var cycleWeight = round(cycle * ((9 + Level.difficulty(teamId)) + cycle * 0.15)) + cycle * 2
	weight += cycleWeight * Data.of(teamId + ".monstermodifiers.cyclesrunweightmodifier")
	weight += GameWorld.additionalRunWeight
	weight *= 1.0 + Level.difficulty(teamId) * 0.1
	weight *= Data.of(teamId + ".monsters.strengthmodfromplayercount")
	return max(15, weight) * Data.of(teamId + ".monstermodifiers.totalrunweightmodifier")
