extends "res://content/techtree/TechTreePopup.gd"

# The shop screen in Story Mode: the inventory panel's iron row becomes the
# dollar balance, and dollar costs are shown and checked against it.
# Vanilla modes run vanilla code only.

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const Assets = preload("res://mods-unpacked/cejdan-StoryMode/util/assets.gd")
const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")


func _ready():
	super()
	if not Story.is_story():
		return
	var iron_label: Node = find_child("LabelIron")
	# The iron icon sits just before the iron count in the inventory grid.
	var grid: Node = iron_label.get_parent()
	var icon: Node = grid.get_child(iron_label.get_index() - 1)
	if icon is TextureRect:
		icon.texture = Assets.tex("res://mods-unpacked/cejdan-StoryMode/art/icon_money.png")
	Data.unlisten(self, teamId + ".inventory.iron")
	Data.listen(self, teamId + ".inventory.money")
	_story_show_money()


func _story_show_money() -> void:
	find_child("LabelIron").text = Minerals.dollars(int(Data.ofOr(teamId + ".inventory.money", 0))).substr(1)


func propertyChanged(property: String, oldValue, newValue):
	if property == teamId + ".inventory.money":
		_story_show_money()
		return
	super(property, oldValue, newValue)


func moveOut():
	if isIn:
		Data.unlisten(self, teamId + ".inventory.money")
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
