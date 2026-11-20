extends "res://content/techtree/TechTreePopup.gd"

# The shop screen in Story Mode: the inventory panel's iron row becomes the
# dollar balance, and dollar costs are shown and checked against it.
# Vanilla modes run vanilla code only.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
const Assets = preload("res://mods-unpacked/flantor-StoryMode/util/assets.gd")
const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
const GadgetShop = preload("res://mods-unpacked/flantor-StoryMode/gamemode/gadget_shop.gd")
const DomeGas = preload("res://mods-unpacked/flantor-StoryMode/gas/dome_gas.gd")

var _story_money_listening := false
# Call for Evacuation (#303): bought here, the shop closes so the company's
# reply opens at once (the shop pauses the game, and a story beat waits for it).
const EVACUATE_ID := "storyevacuate"


func _ready():
	if Story.is_story():
		# New Gadget entries leave the shop once nothing is left to offer.
		GadgetShop.refresh_entries(teamId, playerId)
	super()
	if not Story.is_story():
		return
	var iron_label: Node = find_child("LabelIron")
	# The iron icon sits just before the iron count in the inventory grid.
	var grid: Node = iron_label.get_parent()
	var icon: Node = grid.get_child(iron_label.get_index() - 1)
	if icon is TextureRect:
		icon.texture = Assets.tex("res://mods-unpacked/flantor-StoryMode/art/icon_money.png")
	# The iron listener stays (propertyChanged ignores it): vanilla's moveOut
	# unlistens it, and logged an error when it was already gone (#249).
	Data.listen(self, teamId + ".inventory.money")
	_story_money_listening = true
	_story_show_money()
	GameWorld.upgradeBought.connect(_story_on_bought)


# The buyer's own shop only: upgradeBought fires on the instance that asked
# (the host's own buys, or a client's once the host says yes), whether the
# panel was bought by key or by mouse.
func _story_on_bought(id: String, team: String, player: String) -> void:
	if id != teamId + "." + EVACUATE_ID or team != teamId or player != playerId or not isIn:
		return
	for c: Dictionary in get_incoming_connections():
		var from = c["signal"].get_object()
		if c["signal"].get_name() == "buyUpgrade" and from is InputProcessor and not from.desintegrating:
			from.desintegrate()
			return


func _story_show_money() -> void:
	find_child("LabelIron").text = Minerals.dollars(int(Data.ofOr(teamId + ".inventory.money", 0))).substr(1)


func propertyChanged(property: String, oldValue, newValue):
	if property == teamId + ".inventory.money":
		_story_show_money()
		return
	if property == teamId + ".inventory.iron" and Story.is_story():
		return
	super(property, oldValue, newValue)


func moveOut():
	# Only a Story Mode shop listens for money (#297: closing a vanilla shop
	# logged "removing listener who is not listening").
	if isIn and _story_money_listening:
		_story_money_listening = false
		Data.unlisten(self, teamId + ".inventory.money")
	if GameWorld.upgradeBought.is_connected(_story_on_bought):
		GameWorld.upgradeBought.disconnect(_story_on_bought)
	super()


func updateCostLabels():
	if not Story.is_story():
		super()
		return
	find_child("LabelIronCost").text = ""
	find_child("LabelWaterCost").text = ""
	find_child("LabelSandCost").text = ""
	if not focussedPanel:
		return
	var upgrade = GameWorld.upgrades[focussedPanel.techId]
	var costs = upgrade.get("cost", [])
	for costType in costs:
		var cost = costs[costType]
		var newInventory = int(Data.getInventory(costType, teamId)) - int(cost)
		var color = defaultFontColor
		if GameWorld.boughtUpgrades.has(focussedPanel.techId) and not upgrade.has("repeatable"):
			newInventory = 0
		if newInventory < 0:
			color = Style.FONT_COLOR_WARNING
		var row: String = "Iron" if costType == "money" else costType.capitalize()
		var label: Label = find_child("Label" + row + "Cost")
		if label == null:
			continue
		label.text = Minerals.dollars(int(cost)).substr(1) if costType == "money" else "%s" % cost
		label.label_settings.font_color = color


# A New Gadget entry is not bought here: it opens the gadget choice, and the
# pick pays for it (extensions/stages/level/LevelStage.gd). Without the money
# the choice stays shut and the panel shows vanilla's "can't afford" error.
func buyUpgrade():
	if Story.is_story() and animationDone:
		var tree = find_child("TechTree")
		var panel = tree.focussedTechPanel if tree else null
		# Vent the Dome (#213) with clean air in the dome would be water for
		# nothing: refused, as vanilla refuses a repair at full health.
		if panel and panel.techId.ends_with(DomeGas.VENT_ID) and not DomeGas.has_gas():
			GameWorld.upgradeError.emit(panel.techId, teamId, playerId)
			return
		if panel and GadgetShop.is_entry(panel.techId):
			if panel.state == 1:
				var cost = GameWorld.upgrades.get(panel.techId, {}).get("cost", {})
				if cost is Dictionary and not GameWorld.canAfford(cost, teamId):
					GameWorld.upgradeError.emit(panel.techId, teamId, playerId)
				else:
					Level.stage.openStoryGadgetChoice(teamId, playerId)
			return
	super()
