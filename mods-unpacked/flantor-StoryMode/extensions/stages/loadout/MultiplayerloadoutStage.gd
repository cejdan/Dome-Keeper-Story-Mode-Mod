extends "res://stages/loadout/MultiplayerloadoutStage.gd"

# Story Mode in the loadout screen. Story Mode borrows the Relic Hunt block for
# its difficulty and map size pickers (run modifiers hidden). All four map
# sizes are open in Story Mode, whatever Relic Hunt has unlocked (#320). Every
# dome (#269) and every keeper (#297) vanilla offers is offered. Vanilla modes
# are untouched.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
const MapConfig = preload("res://mods-unpacked/flantor-StoryMode/data/map_config.gd")
const MAP_SIZES: Array = ["regular-small", "regular-medium", "regular-large", "regular-huge"]


@rpc("reliable", "any_peer")
func gameModeSelected(id: String, playSound: = true, firstLoad: = false):
	super(id, playSound, firstLoad)
	if Level.loadout.modeId == Story.MODE_ID:
		_story_apply()


func _story_apply() -> void:
	# The size the player last had in Story Mode, or Story Mode's default
	# (#320); never the size another mode left behind.
	var size: String = MapConfig.DEFAULT_MAP_SIZE
	if GameWorld.hasLastLoadoutsByMode(Story.MODE_ID):
		var last: Loadout = GameWorld.getLastLoadoutsByMode(Story.MODE_ID)
		if last.modeId == Story.MODE_ID:
			setLoadout(last, false)
			var had: String = str(last.modeConfig.get(CONST.MODE_CONFIG_MAP_ARCHETYPE, ""))
			if MapConfig.MAP_SIZE_SHARE.has(had):
				size = had
	mapSizeSelected(size, false, false)
	Level.loadout.modeConfig.erase(CONST.MODE_CONFIG_WORLDMODIFIERS)
	difficultySelected(Level.loadout.difficultyByTeamId.get("team1", 0), "team1", false, false)
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
		_story_map_sizes(story)
		var modifiers: Node = block.find_child("ModifiersBox", true, false)
		if modifiers != null and story:
			modifiers.visible = false


func _story_on() -> bool:
	return Level.loadout != null and Level.loadout.modeId == Story.MODE_ID


# Vanilla puts a locked map size back to Small whenever unlocks change; in
# Story Mode every size is open (#320).
func fallbackLockedSelections() -> void:
	var story: bool = _story_on()
	var size = Level.loadout.modeConfig.get(CONST.MODE_CONFIG_MAP_ARCHETYPE) if story else null
	super()
	if story and MAP_SIZES.has(size):
		mapSizeSelected(size, false, false)


func refreshUnlockableChoices() -> void:
	super()
	if _story_on():
		_story_map_sizes(true)


# Story Mode opens every map size (#320); other modes get vanilla's locks back
# (fillMapSizes), and a size Story Mode left selected that the mode has not
# unlocked goes back to Small.
func _story_map_sizes(story: bool) -> void:
	var box: Node = find_child("MapsizeContainers", true, false)
	if box == null:
		return
	for c in box.get_children():
		if c is Label or not MAP_SIZES.has(c.id):
			continue
		var open: bool = story or (GameWorld.unlocks.is_unlocked(c.id) and not (GameWorld.buildType == CONST.BUILD_TYPE.EXHIBITION and c.id != CONST.MAP_SMALL))
		var desc: String = CONST.mapSizesStringsById.get(c.id) + ".description" if story or GameWorld.unlocks.is_unlocked(c.id) else "unlock.mapsize." + c.id.replace("regular-", "")
		c.setChoice(CONST.mapSizesStringsById.get(c.id), c.id, null, desc)
		c.set_enabled(open)
	if not story and Level.loadout != null and multiplayer.is_server():
		var size: String = str(Level.loadout.modeConfig.get(CONST.MODE_CONFIG_MAP_ARCHETYPE, ""))
		if MAP_SIZES.has(size) and not GameWorld.unlocks.is_unlocked(size):
			mapSizeSelected(CONST.MAP_SMALL, false, true)


# --- room for every mode (#352) ---------------------------------------------------

# Vanilla's tile blocks carve room for vanilla's modes only. The list grows
# down from a fixed top, so Story Mode (last), Versus in multiplayer and any
# other mod's modes run on into the rock and the indestructible wall. Every
# loadout map is built here, so clear the cells under the list as it really is.
const MODE_LIST_MARGIN := 8.0   # world px kept clear round the list


func createMapDataFor(requirements) -> MapData:
	var tileData: MapData = super(requirements)
	_clear_mode_list(tileData)
	return tileData


# The list's world rect. The first loadout map is built before the UI's first
# layout pass, and is then cached, so lay the list out here first, top-down as
# the deferred pass would: the containers above it, then every container in it.
# Twice: a wrapping label keeps the height it had at its old width in its
# cached minimum size until that is invalidated, so the second pass first
# invalidates every size in the list.
func _mode_list_rect() -> Rect2:
	var box: Control = find_child("GameModeContainers", true, false)
	if box == null or not box.is_inside_tree():
		return Rect2()
	var chain: Array = []
	var n: Node = box.get_parent()
	while n is Control:
		chain.push_front(n)
		n = n.get_parent()
	for i in 2:
		if i == 1:
			_invalidate_tree(box)
		for c in chain:
			if c is Container:
				c.notification(Container.NOTIFICATION_SORT_CHILDREN)
		_sort_tree(box)
	var r := Rect2()
	for c in box.get_children():
		if c is Control and c.visible:
			var xf: Transform2D = c.get_global_transform()
			var cr := Rect2(xf.origin, c.size * xf.get_scale())
			r = cr if r.size == Vector2.ZERO else r.merge(cr)
	return r


func _invalidate_tree(c: Node) -> void:
	for ch in c.get_children():
		_invalidate_tree(ch)
	if c is Control:
		c.update_minimum_size()


func _sort_tree(c: Node) -> void:
	if c is Container:
		c.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for ch in c.get_children():
		if ch is Control and ch.visible:
			_sort_tree(ch)


func _clear_mode_list(tileData: MapData) -> void:
	var r: Rect2 = _mode_list_rect()
	if r.size.x <= 0.0 or r.size.y <= 0.0 or MAP == null:
		return
	r = r.grow(MODE_LIST_MARGIN)
	var a: Vector2i = MAP.getTileCoord(r.position)
	var b: Vector2i = MAP.getTileCoord(r.end)
	var cleared: int = 0
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			var c := Vector2(x, y)
			if tileData.get_resourcev(c) >= 0:
				tileData.clear_resource(c)
				cleared += 1
	ModLoaderLog.info("Loadout: cleared %d cells under the mode list (%s..%s)" % [cleared, a, b], "flantor-StoryMode")

