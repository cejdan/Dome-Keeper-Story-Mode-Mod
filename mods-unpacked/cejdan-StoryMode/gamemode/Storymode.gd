extends Node

# The Story Mode game mode node. LevelStage loads it from
# res://content/gamemode/storymode/Storymode.tscn (the mod takes over that path)
# and calls init(), afterInitialized() and getRunWeight().

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")

const MONEY := "team1.inventory.money"

var runWeightOverride: int = -1
var _lost: bool = false


func init() -> void:
	Data.listen(self, "team1.dome.health")
	GameWorld.upgradeBought.connect(_on_upgrade_bought)
	ModLoaderLog.info("Story Mode run started (seed %d)" % Level.levelSeed, Story.LOG)


func afterInitialized() -> void:
	if not multiplayer.is_server():
		return
	# Vanilla dev mode hands out 500 iron, 50 water and 20 cobalt; a Story Mode
	# run starts with empty pockets either way. A loaded save keeps its values.
	if not Data.has(MONEY):
		Data.apply(MONEY, 0)
		Data.apply("team1.inventory.iron", 0)
		Data.apply("team1.inventory.water", 0)
		Data.apply("team1.inventory.sand", 0)
	for m: String in Minerals.ORDER:
		if not Data.has("team1.inventory." + m):
			Data.apply("team1.inventory." + m, 0)
		Data.listen(self, "team1.inventory." + m)
	Level.addHudElement(load(Story.MOD_DIR + "hud/MoneyHud.tscn"), "team1")


# The shop's Suit Blaster entry is a stand-in: buying it grants the real gadget
# to the team's keepers the way a gadget chest does (research on #18).
const SUITBLASTER_ENTRY := "storysuitblaster"


func _on_upgrade_bought(id: String, teamId: String, _playerId: String) -> void:
	if not multiplayer.is_server() or id != teamId + "." + SUITBLASTER_ENTRY:
		return
	for keeper in Keepers.getAllOfTeam(teamId):
		var gid: String = keeper.playerId + ".suitblaster"
		if not GameWorld.boughtUpgrades.has(gid):
			GameWorld.serverAddUpgrade(gid, teamId)
			ModLoaderLog.info("Suit Blaster granted to " + keeper.playerId, Story.LOG)


func propertyChanged(property: String, oldValue, newValue) -> void:
	# A mineral delivered to the dome pays its dollar value. Inventory counts only
	# ever rise from deliveries; Story Mode never spends minerals.
	if property.begins_with("team1.inventory."):
		var type: String = property.substr(16)
		if Minerals.is_mineral(type) and oldValue != null and newValue > oldValue:
			var pieces: int = int(newValue - oldValue)
			Data.changeByInt(MONEY, pieces * Minerals.value_of(type))
			Data.changeByInt("team1.story.pieces", pieces)
		return
	match property:
		"team1.dome.health":
			if newValue <= 0 and not GameWorld.lost and not _lost and not Data.ofOr("team1.dome.healthlocked", false):
				if Data.ofOr("team1.inventory.sand", 0) > 0 and Data.ofOr("team1.dome.autorepair", false):
					return
				_lose()


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
