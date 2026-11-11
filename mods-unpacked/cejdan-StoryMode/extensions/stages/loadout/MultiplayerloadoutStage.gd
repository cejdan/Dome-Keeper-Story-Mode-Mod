extends "res://stages/loadout/MultiplayerloadoutStage.gd"

# Story Mode in the loadout screen. Story Mode borrows the Relic Hunt block for
# its difficulty picker (map size and run modifiers hidden), and locks the
# loadout to the Engineer and the laser dome. Vanilla modes are untouched.

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")

const STORY_KEEPER := "keeper1"
const STORY_DOME := "dome1"


@rpc("reliable", "any_peer")
func gameModeSelected(id: String, playSound: = true, firstLoad: = false):
	super(id, playSound, firstLoad)
	if Level.loadout.modeId == Story.MODE_ID:
		_story_apply()


func _story_apply() -> void:
	if GameWorld.hasLastLoadoutsByMode(Story.MODE_ID):
		var last: Loadout = GameWorld.getLastLoadoutsByMode(Story.MODE_ID)
		if last.modeId == Story.MODE_ID:
			setLoadout(last, false)
	# The loadout block only shows once a map size is set; Story Mode's map is fixed.
	Level.loadout.modeConfig[CONST.MODE_CONFIG_MAP_ARCHETYPE] = CONST.MAP_MEDIUM
	Level.loadout.modeConfig.erase(CONST.MODE_CONFIG_WORLDMODIFIERS)
	difficultySelected(Level.loadout.difficultyByTeamId.get("team1", 0), "team1", false, false)
	if Level.loadout.domes.size() > 0 and Level.loadout.domes.front().domeId != STORY_DOME:
		domeSelected(STORY_DOME, "team1", false, false)
	for lk: LoadoutKeeper in Level.loadout.keepers:
		if lk.keeperId != STORY_KEEPER:
			changeKeeper(lk.playerId, STORY_KEEPER + "-skin0")
	updateClientLoadout()


func updateBlockVisibility(forceRebuild: = false):
	var story: bool = Level.loadout != null and Level.loadout.modeId == Story.MODE_ID
	# Vanilla decides which blocks to show by mode id. Story Mode wants exactly
	# Relic Hunt's blocks, so it wears that id for the length of the call.
	if story:
		Level.loadout.modeId = CONST.MODE_RELICHUNT
	super(forceRebuild)
	if story:
		Level.loadout.modeId = Story.MODE_ID
	if initialized:
		_story_dress(story)


func _story_dress(story: bool) -> void:
	var block: Node = find_child("BlockRelicHuntLoadout", true, false)
	if block != null:
		var headline: Label = block.get_node_or_null("Headline")
		if headline != null:
			headline.text = "loadout.storymode.headline" if story else "loadout.relichunt.title"
		var mapsize: Node = block.find_child("MapSizeList", true, false)
		if mapsize != null:
			mapsize.visible = not story
		var modifiers: Node = block.find_child("ModifiersBox", true, false)
		if modifiers != null and story:
			modifiers.visible = false
	for c in _DomeContainersTeam1.get_children():
		if not c is Label:
			c.visible = (not story) or c.id == STORY_DOME
	var kc: Node = find_child("KeeperContainers")
	if kc != null:
		var i: int = 0
		for box in kc.get_children():
			# Boxes are added in Data.loadoutKeepers order.
			if i < Data.loadoutKeepers.size():
				box.visible = (not story) or Data.loadoutKeepers[i] == STORY_KEEPER
			i += 1
