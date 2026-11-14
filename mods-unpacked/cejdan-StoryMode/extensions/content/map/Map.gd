extends "res://content/map/Map.gd"

# Story Mode minerals on the map: reveal (richness and the visible ore mark),
# drops when a mineral tile breaks, and the ore edge overlay between tiles.
# Vanilla resources and vanilla modes run vanilla code only, except
# onTileRemoved's lift-entry check (#159), which gives vanilla's answer cheaper.

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")
const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")
const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const Bones = preload("res://mods-unpacked/cejdan-StoryMode/data/bones.gd")
const Awakening = preload("res://mods-unpacked/cejdan-StoryMode/beats/awakening.gd")


# --- the flood reveal, spread over frames (#159) -----------------------------------
# Breaking into a big cavern (the lava ocean: about 6,500 cells) revealed all of
# it in one frame and froze the game. Once a Story Mode run is under way, the
# flood runs breadth-first from where the cavern was opened, at most
# FLOOD_BUDGET_USEC of work a frame, so the cavern unveils outward over a moment
# instead. A small dig still finishes in the frame it starts. Each frame's work
# updates every touched border sprite once (vanilla redoes each up to four
# times) and uploads the map textures once. Map setup and loading, vanilla
# modes, and a forced flood (the scanner cave) run vanilla's flood in one go.
const FLOOD_BUDGET_USEC := 6000
var _flood: Array = []              # cells waiting, breadth-first from _flood_head
var _flood_head := 0
var _flood_closed: Dictionary = {}
var _flooding := false              # inside a flood step: border and texture updates wait
var _border_batch: Dictionary = {}


func floodRevealTiles(forceUpdate: = false):
	if forceUpdate or not _slice_floods():
		# What is still pending goes first; the new cells take vanilla's way.
		if flood_pending():
			_run_flood(-1)
		super(forceUpdate)
	else:
		_take_queue()
		_run_flood(FLOOD_BUDGET_USEC)


func _slice_floods() -> bool:
	return Story.is_story() and Level.stage != null and is_instance_valid(Level.stage) and Level.stage.get("keeperInputStarted") == true


func flood_pending() -> bool:
	return _flood_head < _flood.size()


# Reveals everything still waiting, now (playtests that dig and look at once).
func finish_flood() -> void:
	_take_queue()
	_run_flood(-1)


func _take_queue() -> void:
	_flood.append_array(tileCoordsToReveal)
	tileCoordsToReveal.clear()


# Vanilla's floodRevealTiles loop, breadth-first, skipping cells already done,
# for at most `budget` usec (-1: until done).
func _run_flood(budget: int) -> void:
	var t0 := Time.get_ticks_usec()
	var offsets = get("NEIGHBOR_TILE_OFFSETS" + str(Data.of("map.revealdistance")))
	_flooding = true
	var n := 0
	while _flood_head < _flood.size():
		var cell: Vector2 = _flood[_flood_head]
		_flood_head += 1
		if _flood_closed.has(cell):
			continue
		_flood_closed[cell] = true
		n += 1
		if tileData.get_hardnessv(cell) > -1:
			var resv = tileData.get_resourcev(cell)
			if resv == -1:
				if not visibleTileCoords.has(cell) or visibleTileCoords[cell] != -1:
					visibleTileCoords[cell] = -1
					revealTile(cell)
					onTileRemoved(cell)
					removeTileVisually(cell)
				for d in offsets:
					var nc: Vector2 = cell + d
					if not _flood_closed.has(nc) and not visibleTileCoords.has(nc):
						_flood.append(nc)
			elif not visibleTileCoords.has(cell) or visibleTileCoords[cell] != resv:
				revealTile(cell)
		if budget >= 0 and (n & 31) == 0 and Time.get_ticks_usec() - t0 > budget:
			break
	_flooding = false
	for key: Vector2i in _border_batch:
		_update_border_sprite(key.x, key.y)
	_border_batch.clear()
	updateDirtyTextures()
	if not flood_pending():
		_flood.clear()
		_flood_head = 0
		_flood_closed.clear()
	elif _flood_head > 8192:
		_flood = _flood.slice(_flood_head)
		_flood_head = 0


func _process(delta):
	super(delta)
	if flood_pending():
		_run_flood(FLOOD_BUDGET_USEC)


# Vanilla's onTileRemoved, with one change (#159). To see whether the removed
# cell's column holds a lift entry, vanilla scanned every B1 cell
# (tileData.get_entry_coords()) for each removed cell. Breaking into the lava
# ocean removes about 6,000 open cells in one flood reveal, and that scan froze
# the game for seconds. An entry is an open, non-border B1 cell at row -2, so
# the column is checked directly: the same answer for one cell's cost.
func onTileRemoved(tileCoord: Vector2):
	tileData.clear_resource(tileCoord)
	for listener in tileDestroyedListeners.get(tileCoord, []):
		listener.tileDestroyed(tileCoord)
	pathfinder.add_point_in_coord(tileCoord)
	for n in NEIGHBOR_TILE_OFFSETS1:
		var c = n + tileCoord
		if not tiles.has(c):
			pathfinder.try_connect_coord(tileCoord, c)
	updateBorderSpriteOfTileCoord(tileCoord)
	if _has_entry(int(tileCoord.x)):
		updateLiftLength(tileCoord.x)
	var world_tile_pos: Vector2 = getTilePos(tileCoord)
	tile_destroyed.emit(world_tile_pos)


# Whether get_entry_coords() holds a cell in column x.
func _has_entry(x: int) -> bool:
	var c := Vector2i(x, -2)
	if tileData.get_biomev(c) == 0 and tileData.get_hardnessv(c) != -1 and tileData.get_resourcev(c) == -1:
		return true
	# With no entry anywhere, get_entry_coords() answers (0, 0).
	return x == 0 and tileData.get_entry_coords().has(Vector2.ZERO)


func revealTile(coord: Vector2):
	coord = Vector2(int(coord.x), int(coord.y))
	var had: bool = tiles.has(coord)
	super(coord)
	if had or not tiles.has(coord):
		return
	var tile = tiles[coord]
	if Minerals.is_mod_mineral(tile.type):
		tile.richness = float(Minerals.TABLE[tile.type]["richness"])
		_reveal_visually(coord)
	elif Metal.is_metal(tile.type):
		_reveal_visually(coord)
	elif tile.type == Bones.TYPE:
		# Miner bones (#94). Their data log opens when they are sold at the dome
		# (drops/BonesDrop.gd), not when they are uncovered.
		_reveal_visually(coord)


# Inside a flood step the map textures upload once, at its end (#159).
func _reveal_visually(coord: Vector2) -> void:
	if _flooding:
		revealTileVisuallyWithoutTexturesUpdate(coord)
	else:
		revealTileVisually(coord)


func destroyTile(teamId: String, keeperTechId: String, tile: Tile):
	var type: String = tile.type
	var richness: float = tile.richness
	# Vanilla counts iron per biome at map start and assumes every iron tile was
	# counted. Story Mode biomes can hold iron vanilla never counted there.
	if type == CONST.IRON and not currentIronCountByLayer.has(tile.layer):
		currentIronCountByLayer[tile.layer] = 1
	super(teamId, keeperTechId, tile)
	# Story beats (#26): the first gem mined, the gate broken.
	if Story.is_story() and is_server():
		if Minerals.TABLE.has(type) and Minerals.TABLE[type]["shape"] == "star":
			StoryBeats.trigger("first_gem")
		elif type == Metal.GATE_TYPE:
			StoryBeats.trigger("gate_broken")
		if type == "unobtainium":
			# Each piece mined weakens the horror's seal (#95).
			Awakening.unobtainium_mined(Vector2i(tile.coord))
	if type == Bones.TYPE and is_inside_tree() and is_server():
		# The bones come loose; they sell by the biome they were found in.
		var biome: int = tileData.get_biomev(Vector2i(tile.coord))
		var drop = Level.drops.network_spawn({"type": Bones.TYPE, "position": tile.global_position, "impulse": Vector2.ZERO})
		if drop != null:
			drop.value = Bones.value_for(biome)
			drop.biome = biome
		return
	if not Minerals.is_mod_mineral(type):
		return
	if not is_inside_tree() or not is_server():
		return
	# Same drop count rule vanilla uses for iron, with its own running delta.
	var goalRichness: float = richness * Data.ofOr("resourcemodifiers.richness." + type, 1.0)
	var drops: int = int(floor(goalRichness - 1 + (randi() % 3)))
	var newDelta = dropDeltas.get(type, 0) + drops - goalRichness
	if newDelta >= 3:
		drops -= 1
		newDelta -= 1
	elif newDelta <= -3:
		drops += 1
		newDelta += 1
	dropDeltas[type] = newDelta
	if drops < 3 and Level.difficulty() * 0.1 < - randf():
		drops += 1
	for _i in range(0, max(1, drops)):
		spawnDrop(tile, teamId)


# Story Mode has no gadget chambers; its gadget tile id holds a translator
# chamber (#93, placed by map/story_gen.gd place_translators).
func getSceneForTileType(tileType: int) -> PackedScene:
	if tileType == Data.TILE_GADGET and Story.is_story():
		return load("res://mods-unpacked/cejdan-StoryMode/map/TranslatorChamber.tscn")
	return super(tileType)


func updateBorderSprite(x: int, y: int):
	if _flooding:
		# A flood step updates each touched sprite once, at its end (#159).
		_border_batch[Vector2i(x, y)] = true
	else:
		_update_border_sprite(x, y)


func _update_border_sprite(x: int, y: int):
	super.updateBorderSprite(x, y)
	var key = Vector2(x, y)
	if not borderSprites.has(key):
		return
	var r_tl: int = tileData.get_resource(x, y)
	var r_tr: int = tileData.get_resource(x + 1, y)
	var r_br: int = tileData.get_resource(x + 1, y + 1)
	var r_bl: int = tileData.get_resource(x, y + 1)
	var tileMeta = borderSprites[key]
	var overlays: Dictionary = tileMeta[2]
	var has_empty: bool = r_tl == Data.TILE_EMPTY or r_tr == Data.TILE_EMPTY or r_br == Data.TILE_EMPTY or r_bl == Data.TILE_EMPTY
	if overlays.has(Data.TILE_IRON):
		# Story Mode iron is grey: same overlay node, the mod's sheet, whose border
		# block sits at the sheet origin (vanilla's iron block is 8 rows down).
		var iron_sheet: Texture2D = Minerals.sheet_for_type("iron")
		if iron_sheet != null:
			var io = overlays[Data.TILE_IRON]
			io.texture = iron_sheet
			io.set_frame_coords(layouts[tileMeta[0]])
			io.material.set_shader_parameter("frame_coords", layouts[tileMeta[0]])
	for typeId: int in [r_tl, r_tr, r_br, r_bl]:
		var sheet: Texture2D = Minerals.sheet_for_tile_id(typeId)
		if sheet == null:
			continue
		if not overlays.has(typeId):
			var overlay = RESOURCE_BORDER_OVERLAY.instantiate()
			overlay.material = overlay.material.duplicate()
			overlay.texture = sheet
			overlay.position.x = x * GameWorld.TILE_SIZE + borderSpriteOffset.x
			overlay.position.y = y * GameWorld.TILE_SIZE + borderSpriteOffset.y
			overlay.name = "%dx%d_m%d" % [key.x, key.y, typeId]
			tile_borders_node.add_child(overlay)
			overlays[typeId] = overlay
			Style.init(overlay)
		# The mineral sheets keep their border block at the sheet origin, which is
		# where vanilla looks for any type it has no row offset for.
		var o = overlays[typeId]
		o.set_frame_coords(layouts[tileMeta[0]])
		o.material.set_shader_parameter("frame_coords", layouts[tileMeta[0]])
		o.material.set_shader_parameter("hide_tl", float(r_tl != typeId or not has_empty))
		o.material.set_shader_parameter("hide_tr", float(r_tr != typeId or not has_empty))
		o.material.set_shader_parameter("hide_bl", float(r_bl != typeId or not has_empty))
		o.material.set_shader_parameter("hide_br", float(r_br != typeId or not has_empty))


# Lava hardened by water (#47) becomes rock again: the opposite of
# removeTileVisually's hole mark, so the map draws solid rock there.
func restoreTileVisually(tileCoord: Vector2) -> void:
	var c: Vector2 = tileCoord + MAP_TO_TEXTURE_OFFSET_COORD
	var draw_pos_es = (Vector2(c.x, c.y) + Vector2(tilemap_size.x / 2, 0)) * edge_scaling
	for x in edge_scaling:
		for y in edge_scaling:
			holeImage.set_pixelv(draw_pos_es + Vector2(x, y), Color.BLACK)
	holeTextureIsDirty = true
	updateDirtyTextures()
