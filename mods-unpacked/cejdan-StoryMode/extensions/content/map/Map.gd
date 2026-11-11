extends "res://content/map/Map.gd"

# Story Mode minerals on the map: reveal (richness and the visible ore mark),
# drops when a mineral tile breaks, and the ore edge overlay between tiles.
# Vanilla resources and vanilla modes run vanilla code only.

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")
const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")


func revealTile(coord: Vector2):
	coord = Vector2(int(coord.x), int(coord.y))
	var had: bool = tiles.has(coord)
	super(coord)
	if had or not tiles.has(coord):
		return
	var tile = tiles[coord]
	if Minerals.is_mod_mineral(tile.type):
		tile.richness = float(Minerals.TABLE[tile.type]["richness"])
		revealTileVisually(coord)
	elif Metal.is_metal(tile.type):
		revealTileVisually(coord)


func destroyTile(teamId: String, keeperTechId: String, tile: Tile):
	var type: String = tile.type
	var richness: float = tile.richness
	# Vanilla counts iron per biome at map start and assumes every iron tile was
	# counted. Story Mode biomes can hold iron vanilla never counted there.
	if type == CONST.IRON and not currentIronCountByLayer.has(tile.layer):
		currentIronCountByLayer[tile.layer] = 1
	super(teamId, keeperTechId, tile)
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


func updateBorderSprite(x: int, y: int):
	super(x, y)
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
