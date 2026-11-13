extends Node

# The Story Mode game mode node. LevelStage loads it from
# res://content/gamemode/storymode/Storymode.tscn (the mod takes over that path)
# and calls init(), afterInitialized() and getRunWeight().

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")
const Runes = preload("res://mods-unpacked/cejdan-StoryMode/pleas/runes.gd")
const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const SalePops = preload("res://mods-unpacked/cejdan-StoryMode/hud/sale_pops.gd")

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
	Data.listen(self, "team1.dome.health")
	GameWorld.upgradeBought.connect(_on_upgrade_bought)
	ModLoaderLog.info("Story Mode run started (seed %d)" % Level.levelSeed, Story.LOG)


func afterInitialized() -> void:
	if not multiplayer.is_server():
		return
	# Vanilla dev mode hands out 500 iron, 50 water and 20 cobalt; a Story Mode
	# run starts with empty pockets either way. A loaded save keeps its values.
	# A new run: the company's welcome memo opens once the keeper can move (#123).
	# A save restores Data after this runs, so a load is told apart by its flag.
	if not SaveGame.currentLoadingSavegame:
		_welcome()
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
	Level.addHudElement(load(Story.MOD_DIR + "hud/MoneyHud.tscn"), "team1")
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


# The shop's Suit Blaster entry is a stand-in: buying it grants the real gadget
# to the team's keepers the way a gadget chest does (research on #18).
const SUITBLASTER_ENTRY := "storysuitblaster"
# Retire Rich (#31, #54): the only way to win a Story Mode run until the boss.
const RETIRE_ENTRY := "storyretirerich"


func _on_upgrade_bought(id: String, teamId: String, _playerId: String) -> void:
	if not multiplayer.is_server():
		return
	if id == teamId + "." + RETIRE_ENTRY:
		_win()
		return
	if id != teamId + "." + SUITBLASTER_ENTRY:
		return
	for keeper in Keepers.getAllOfTeam(teamId):
		var gid: String = keeper.playerId + ".suitblaster"
		if not GameWorld.boughtUpgrades.has(gid):
			GameWorld.serverAddUpgrade(gid, teamId)
			ModLoaderLog.info("Suit Blaster granted to " + keeper.playerId, Story.LOG)


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
# caller need not await it. Normal play never calls it yet; the dev command
# `-- --story --horror-defeated` does once keeper input has started.
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


# Takes the keeper's controls and ends the waves, for an ending.
func _stop_play() -> void:
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
func _end_won(title: String, subtitle: String) -> void:
	GameWorld.handleGameWon()
	Audio.stopBattleMusic()
	await get_tree().create_timer(2.5).timeout
	Audio.startEnding()
	await get_tree().create_timer(4.0).timeout
	var popup = load("res://content/gamemode/relichunt/RunFinishedPopup.tscn").instantiate()
	popup.init(multiplayer.is_server())
	load(Story.MOD_DIR + "endings/ending_director.gd").retitle(popup, title, subtitle)
	Level.stage.showEndingPanel(popup)
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
	Level.stage.showEndingPanel(popup)


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
