extends "res://content/techtree/Tech2.gd"

# Tech tree panels show a dollar cost ("money") with the coin icon and a short
# money text. Vanilla costs (iron, water, cobalt) are drawn by vanilla.

const Assets = preload("res://mods-unpacked/flantor-StoryMode/util/assets.gd")
static var _Assets = Assets  # calls go through this: lazy_preload makes const-preload calls slow
const Prices = preload("res://mods-unpacked/flantor-StoryMode/data/prices.gd")
static var _Prices = Prices  # calls go through this: lazy_preload makes const-preload calls slow


func build(id: String, tier: = -1):
	super(id, tier)
	if costLabels.has("money"):
		var label: Label = costLabels["money"]
		var box: Node = label.get_parent()
		var idx: int = label.get_index() + 1
		if idx < box.get_child_count() and box.get_child(idx) is TextureRect:
			box.get_child(idx).texture = _Assets.tex("res://mods-unpacked/flantor-StoryMode/art/icon_money.png")
		_story_money_text()


func updateState():
	super()
	_story_money_text()


func _story_money_text() -> void:
	if not costLabels.has("money"):
		return
	var tech = GameWorld.upgrades.get(techId)
	if tech == null:
		return
	var cost = tech.get("cost", {})
	if cost is Dictionary and cost.has("money"):
		costLabels["money"].text = _Prices.short(int(cost["money"]))
