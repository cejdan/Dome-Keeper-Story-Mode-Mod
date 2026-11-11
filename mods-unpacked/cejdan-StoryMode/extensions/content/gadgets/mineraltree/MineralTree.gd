extends "res://content/gadgets/mineraltree/MineralTree.gd"

# Story Mode's Mineral Tree (#55): roots on any mineral tile (bronze through
# unobtainium) count as vanilla counts iron, and grow gold fruit where vanilla
# grows iron. Water and cobalt fruit stay vanilla. The two functions below are
# vanilla's with only that mapping changed; vanilla modes run vanilla's.

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")

const GOLD := "gold"


# A root tile's resource id as the tree sees it: every mineral reads as 0 (iron).
static func _root_res(res: int) -> int:
	if res >= 40 and Minerals.by_tile_id(res) != "":
		return 0
	return res


func updateFruitType():
	if not Story.is_story():
		super()
		return
	var rooted: = {GOLD: 1}
	for rootCoord in rootCoords:
		var res = _root_res(Level.map.getTileData().get_resourcev(rootCoord))
		match int(res):
			0: rooted[GOLD] = 1 + rooted.get(GOLD, 0)
			1: rooted[CONST.WATER] = 1 + rooted.get(CONST.WATER, 0)
			2: rooted[CONST.SAND] = min(1, 1 + rooted.get(CONST.SAND, 0))
	for f in fruits[fruitStage]:
		match f.type:
			GOLD, CONST.IRON: rooted[GOLD] = rooted.get(GOLD, 0) - 1
			CONST.WATER: rooted[CONST.WATER] = rooted.get(CONST.WATER, 0) - 1
			CONST.SAND: rooted[CONST.SAND] = rooted.get(CONST.SAND, 0) - 1
	for fs in fruits[fruitStage]:
		if not fs.type or fs.type == "":
			var type: String
			if rooted.get(CONST.SAND, 0) > 0:
				type = CONST.SAND
				rooted[CONST.SAND] = rooted.get(CONST.SAND, 0) - 1
			elif rooted.get(CONST.WATER, 0) > 0:
				type = CONST.WATER
				rooted[CONST.WATER] = rooted.get(CONST.WATER, 0) - 1
			elif rooted.get(GOLD, 0) > 0:
				type = GOLD
				rooted[GOLD] = rooted.get(GOLD, 0) - 1
			if type:
				fs.setType(type)


func tryGrowingStem(growthStage: int):
	if not Story.is_story():
		super(growthStage)
		return
	var resourceTiles: = 0
	for rootCoord in rootCoords:
		var res = _root_res(Level.map.getTileData().get_resourcev(rootCoord))
		if res >= 0 and res <= 2:
			resourceTiles += 1
	var baseCoord = rootCoords.front()
	baseCoord.y += 1 if Data.ofOr("world.inversegravity", false) else -1
	var relevantTiles: Array
	currentGrowthStage = growthStage
	if currentGrowthStage < 5:
		relevantTiles = stage5Tiles
	elif currentGrowthStage < 10:
		relevantTiles = stage10Tiles
	else:
		relevantTiles = stage15Tiles
	if Data.ofOr("world.inversegravity", false):
		relevantTiles = relevantTiles.duplicate()
		for x in relevantTiles.size():
			relevantTiles[x].y *= -1
	for d in relevantTiles:
		var tile = Level.map.getTile(baseCoord + d)
		if tile != null and Data.isDestructable(tile):
			tile.hit(Vector2.ZERO, tile.max_health, teamId)
	if currentGrowthStage < 5:
		currentGrowthStage += 1
	if currentGrowthStage == 5 and resourceTiles >= 2:
		currentGrowthStage = 10
	elif currentGrowthStage == 10 and resourceTiles >= 3:
		currentGrowthStage = 15
	$Stem.frame = currentGrowthStage


func tryRooting():
	if not Story.is_story():
		super()
		return
	# Vanilla's, with roots reaching for mineral tiles as they reach for iron.
	var baseCoord = rootCoords.front()
	var randDir: Array = CONST.DIRECTIONS.duplicate()
	randDir.shuffle()
	var roots = rootCoords.duplicate()
	roots.shuffle()
	var freeTiles: = []
	for root in roots:
		for d in randDir:
			var coord = root + d
			if rootCoords.has(coord) or (baseCoord - coord).length() >= 30:
				continue
			var res = _root_res(Level.map.getTileData().get_resourcev(root + d))
			if res >= 0 and res <= 2:
				grown_on_tile.emit(coord)
				return
			elif res == 10:
				freeTiles.append(coord)
	if freeTiles.size() > 0:
		var coord = freeTiles[randi() % freeTiles.size()]
		grown_on_tile.emit(coord)
