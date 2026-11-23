extends "res://content/map/Map.gd"

# Story Mode minerals on the map: reveal (richness and the visible ore mark),
# drops when a mineral tile breaks, and the ore edge overlay between tiles.
# Vanilla resources and vanilla modes run vanilla code only, except
# onTileRemoved's lift-entry check (#159), which gives vanilla's answer cheaper,
# and the drone path graph's upkeep (#313), which only drops vanilla's leftovers.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
static var _Minerals = Minerals  # calls go through this: lazy_preload makes const-preload calls slow
const Metal = preload("res://mods-unpacked/flantor-StoryMode/data/metal.gd")
static var _Metal = Metal  # calls go through this: lazy_preload makes const-preload calls slow
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
static var _StoryBeats = StoryBeats  # calls go through this: lazy_preload makes const-preload calls slow
const Bones = preload("res://mods-unpacked/flantor-StoryMode/data/bones.gd")
static var _Bones = Bones  # calls go through this: lazy_preload makes const-preload calls slow
const Awakening = preload("res://mods-unpacked/flantor-StoryMode/beats/awakening.gd")
static var _Awakening = Awakening  # calls go through this: lazy_preload makes const-preload calls slow


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
	return _Story.is_story() and Level.stage != null and is_instance_valid(Level.stage) and Level.stage.get("keeperInputStarted") == true


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
	if _pets_changed or not _pets_waiting.is_empty():
		_pets_pass()


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
	_path_open(tileCoord)
	updateBorderSpriteOfTileCoord(tileCoord)
	if _has_entry(int(tileCoord.x)):
		updateLiftLength(tileCoord.x)
	var world_tile_pos: Vector2 = getTilePos(tileCoord)
	tile_destroyed.emit(world_tile_pos)


# --- the drone path graph follows the map (#313) ----------------------------------
# Vanilla's graph (content/map/Pathfinding.gd, an AStar2D) only ever gains
# points: each time a cell opens, add_point_in_coord makes a new point and
# drops the old one's id from its lookup, but the old point stays in the graph
# with its links. A dug tile opens twice (destroyTile, then the flood reveal),
# and Story Mode opens cells again and again (lava melting rock, water
# hardening it back, gas bursts), so the graph fills with these leftover points.
# And a cell that turns back into rock (lava hardened by water) keeps its
# point, so drones and the wave meter's way home are routed through solid rock.
# Here a cell has one point at most: opening reuses it, and a cell that becomes
# rock again loses it, and drones whose path crosses it look for a new one.
# A cell that gets a point again is announced too (path_cell_opened): drones
# that found no way home listen while they wait (TransportDrone.gd).

signal path_cell_closed(coord: Vector2)
signal path_cell_opened(coord: Vector2)


func _path_pos(coord: Vector2) -> Vector2:
	return coord * GameWorld.TILE_SIZE + CONST.TILE_OFFSET


func _path_open(tileCoord: Vector2) -> void:
	var pos := _path_pos(tileCoord)
	var new := not pathfinder.pointIdsByCoord.has(pos)
	if new:
		pathfinder.add_point_in_coord(tileCoord)
	for n in NEIGHBOR_TILE_OFFSETS1:
		var c = n + tileCoord
		if not tiles.has(c):
			pathfinder.try_connect_coord(tileCoord, c)
	if new:
		_pets_changed = true
		if not _pets_cells.has(Vector2i(tileCoord)):
			_pets_cells[Vector2i(tileCoord)] = false
		path_cell_opened.emit(tileCoord)


func _path_close(tileCoord: Vector2) -> void:
	if pathfinder == null:
		return
	var pos := _path_pos(tileCoord)
	if not pathfinder.pointIdsByCoord.has(pos):
		return
	var id: int = pathfinder.pointIdsByCoord[pos]
	pathfinder.pointIdsByCoord.erase(pos)
	if pathfinder.pathfinder.has_point(id):
		pathfinder.pathfinder.remove_point(id)
	_pets_changed = true
	_pets_cells[Vector2i(tileCoord)] = true
	path_cell_closed.emit(tileCoord)


# --- the Beastmaster's pets follow the map too (#313) ------------------------------
# The pets walk a graph of their own (content/keeper/keeper4/GoblinNavigator.gd,
# on the host), rebuilt from the whole map at most every 100 ms and 5 ms of it
# a frame, but only when the map's tile count has changed or a tile_destroyed
# marked it dirty. Two gaps, with Story Mode's rock coming and going all the
# time: a change that lands while a rebuild is under way is lost (the finished
# rebuild clears the mark and takes the new count), so the pets keep walking
# into rock that came back or ignore an opening; and a pet whose path crosses a
# cell that turns to rock walks on through it, as vanilla only checks the rock
# a path stands on. So once a frame with changes, each team's navigator is
# marked dirty (its throttle and budget still decide when it rebuilds), marked
# again when a rebuild under way finishes if a change was within
# PETS_REACH_TILES of a pet (farther off, the next rebuild picks it up; each
# rebuild costs several ms), and pets whose path crosses a cell that closed
# re-path once a rebuild after the change is done. With no pets, a frame with
# changes costs a dirty mark per team.

var _pets_changed := false
var _pets_cells: Dictionary = {}    # Vector2i -> closed (true) or opened, since the last pass
var _pets_waiting: Array = []       # [navigator, generation to wait for, pet or null, since (ms)]
const PETS_WAIT_MS := 5000          # given up after this (no pet asking, so no rebuild)
const PETS_REACH_TILES := 24


func _pets_pass() -> void:
	if _pets_changed:
		_pets_changed = false
		if is_server():
			for dome in Level.domesByTeamId.values():
				var g = dome.get("goblins") if is_instance_valid(dome) else null
				if g == null or g._navigator == null:
					continue
				var nav = g._navigator
				nav._dirty = true
				var gen: int = nav._graph_generation + 1
				if g.all_goblins.is_empty():
					continue
				if nav._pathfinder_scratch != null and _pets_near(g.all_goblins):
					# A rebuild under way may already have read these cells.
					_pets_waiting.append([nav, gen, null, Time.get_ticks_msec()])
					gen += 1
				for pet in g.all_goblins:
					if not is_instance_valid(pet):
						continue
					var path: Array = pet.current_surface_path
					for i in range(pet.surface_path_index, path.size()):
						if _pets_cells.get(path[i].get("coord", Vector2i.ZERO), false):
							_pets_waiting.append([nav, gen, pet, Time.get_ticks_msec()])
							break
		_pets_cells.clear()
	var i := 0
	while i < _pets_waiting.size():
		var w: Array = _pets_waiting[i]
		var nav = w[0]
		if nav._graph_generation < w[1]:
			if Time.get_ticks_msec() - int(w[3]) > PETS_WAIT_MS:
				_pets_waiting.remove_at(i)
			else:
				i += 1
			continue
		if w[2] == null:
			nav._dirty = true
		elif is_instance_valid(w[2]):
			# The pet's next look at its path (Goblin._is_path_stale) finds it
			# stale and asks the fresh graph for a new one.
			w[2]._stale_check_at_ms = Time.get_ticks_msec()
			w[2]._stale_cached_result = true
		_pets_waiting.remove_at(i)


# Whether a cell changed since the last pass lies within PETS_REACH_TILES of a pet.
func _pets_near(pets: Array) -> bool:
	for pet in pets:
		if not is_instance_valid(pet):
			continue
		var p: Vector2i = getTileCoord(pet.global_position)
		for c: Vector2i in _pets_cells:
			if absi(c.x - p.x) <= PETS_REACH_TILES and absi(c.y - p.y) <= PETS_REACH_TILES:
				return true
	return false


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
	# A tile where the path graph had an open cell: rock came back (#313).
	_path_close(coord)
	var tile = tiles[coord]
	if _Minerals.is_mod_mineral(tile.type):
		tile.richness = float(Minerals.TABLE[tile.type]["richness"])
		_reveal_visually(coord)
	elif _Metal.is_metal(tile.type):
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
	if _Story.is_story() and is_server():
		if Minerals.TABLE.has(type) and Minerals.TABLE[type]["shape"] == "star":
			_StoryBeats.trigger("first_gem")
		elif type == Metal.GATE_TYPE:
			_StoryBeats.trigger("gate_broken")
		if type == "unobtainium":
			# Each piece mined weakens the horror's seal (#95).
			_Awakening.unobtainium_mined(Vector2i(tile.coord))
	if type == Bones.TYPE and is_inside_tree() and is_server():
		# The bones come loose; they sell by the biome they were found in.
		var biome: int = tileData.get_biomev(Vector2i(tile.coord))
		var drop = Level.drops.network_spawn({"type": Bones.TYPE, "position": tile.global_position, "impulse": Vector2.ZERO})
		if drop != null:
			drop.value = _Bones.value_for(biome)
			drop.biome = biome
		return
	if not _Minerals.is_mod_mineral(type):
		return
	if not is_inside_tree() or not is_server():
		return
	# A fixed count (diamond, #186): no dice, no difficulty bonus.
	if Minerals.TABLE[type].has("drops"):
		for _i in int(Minerals.TABLE[type]["drops"]):
			spawnDrop(tile, teamId)
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
	if tileType == Data.TILE_GADGET and _Story.is_story():
		return load("res://mods-unpacked/flantor-StoryMode/map/TranslatorChamber.tscn")
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
		var iron_sheet: Texture2D = _Minerals.sheet_for_type("iron")
		if iron_sheet != null:
			var io = overlays[Data.TILE_IRON]
			io.texture = iron_sheet
			io.set_frame_coords(layouts[tileMeta[0]])
			io.material.set_shader_parameter("frame_coords", layouts[tileMeta[0]])
	for typeId: int in [r_tl, r_tr, r_br, r_bl]:
		var sheet: Texture2D = _Minerals.sheet_for_tile_id(typeId)
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
