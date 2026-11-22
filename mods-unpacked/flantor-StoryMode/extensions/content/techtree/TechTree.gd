extends "res://content/techtree/TechTree.gd"

# Vanilla scrolls the shop to centre the focused panel's whole track. A track
# taller than the view (Story Mode's own track has eight rows) would keep its
# top and bottom rows out of sight, so for those the view follows the panel.
#
# Story Mode's buy rules live in buyCurrentUpgrade, the one call that both the
# select key (TechTreePopup.buyUpgrade) and a double click on a panel (techInput)
# reach. Handled only in the popup, a double click bought a New Gadget entry the
# vanilla way: price paid, no gadget choice, no gadget (#317).

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const GadgetShop = preload("res://mods-unpacked/flantor-StoryMode/gamemode/gadget_shop.gd")
static var _GadgetShop = GadgetShop  # calls go through this: lazy_preload makes const-preload calls slow
const DomeGas = preload("res://mods-unpacked/flantor-StoryMode/gas/dome_gas.gd")
static var _DomeGas = DomeGas  # calls go through this: lazy_preload makes const-preload calls slow


func technologyFocussed(techPanel):
	super(techPanel)
	var view = get_parent()
	if techPanel == null or techPanel.track == null or techPanel.track.size.y <= view.size.y * 0.9:
		return
	var y: float = techPanel.global_position.y - view.global_position.y + view.scroll_vertical - view.size.y * 0.5 + techPanel.size.y * 0.5
	$Tween.interpolate_property(view, "scroll_vertical", view.scroll_vertical, y, 0.2, Tween.TRANS_QUAD, Tween.EASE_IN_OUT)
	$Tween.start()


# A New Gadget entry is not bought here: it opens the gadget choice, and the
# pick pays for it (extensions/stages/level/LevelStage.gd). Without the money
# the choice stays shut and the panel shows vanilla's "can't afford" error.
func buyCurrentUpgrade():
	if not _Story.is_story() or focussedTechPanel == null:
		super()
		return
	var id: String = focussedTechPanel.techId
	# Vent the Dome (#213) with clean air in the dome would be water for
	# nothing: refused, as vanilla refuses a repair at full health.
	if id.ends_with(DomeGas.VENT_ID) and not _DomeGas.has_gas():
		GameWorld.upgradeError.emit(id, teamId, playerId)
		return
	if _GadgetShop.is_entry(id):
		if focussedTechPanel.state == 1:
			var cost = GameWorld.upgrades.get(id, {}).get("cost", {})
			if cost is Dictionary and not GameWorld.canAfford(cost, teamId):
				GameWorld.upgradeError.emit(id, teamId, playerId)
			else:
				Level.stage.openStoryGadgetChoice(teamId, playerId)
		return
	super()
