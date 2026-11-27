extends "res://content/gadgets/mineraltree/MineralTree.gd"

# Story Mode's Mineral Tree (#328): a tree grows what it is planted on. A tree
# planted on one of the mod's minerals (bronze through diamond) grows that
# mineral where vanilla grows iron, and its roots reach for mineral tiles as
# vanilla's reach for iron; each root on a mineral counts as that mineral. A
# tree planted on anything else (iron, water, cobalt, plain rock) runs
# vanilla's code untouched, in every mode: vanilla's roots don't see the mod's
# tiles, and its free fruit is iron. (#55 made every Story Mode tree grow gold
# where vanilla grows iron, so a cobalt or water tree grew gold.) The three
# functions below are vanilla's, with only that mapping changed.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
static var _Minerals = Minerals  # calls go through this: lazy_preload makes const-preload calls slow


# The mod mineral a resource id stands for, or "" (vanilla ids and rock).
static func _mineral_of(res: int) -> String:
	return _Minerals.by_tile_id(res) if res >= 40 else ""


# The mod mineral this tree is planted on, or "" for a vanilla tree.
func _planted_mineral() -> String:
	if rootCoords.is_empty() or not _Story.is_story():
		return ""
	return _mineral_of(int(Level.map.getTileData().get_resourcev(rootCoords.front())))


# Vanilla's test for a tile roots grow into and that counts toward the stem.
static func _is_resource(res: int) -> bool:
	return (res >= 0 and res <= 2) or _mineral_of(res) != ""


func updateFruitType():
	var planted: String = _planted_mineral()
	if planted == "":
		super()
		return
	# Vanilla starts every tree with one free iron; this one with its mineral.
	var rooted: = {planted: 1}
	for rootCoord in rootCoords:
		var res: int = int(Level.map.getTileData().get_resourcev(rootCoord))
		match res:
			0: rooted[CONST.IRON] = 1 + rooted.get(CONST.IRON, 0)
			1: rooted[CONST.WATER] = 1 + rooted.get(CONST.WATER, 0)
			2: rooted[CONST.SAND] = min(1, 1 + rooted.get(CONST.SAND, 0))
			_:
				var m: String = _mineral_of(res)
				if m != "":
					rooted[m] = 1 + rooted.get(m, 0)
	for f in fruits[fruitStage]:
		if f.type != "":
			rooted[f.type] = rooted.get(f.type, 0) - 1
	# Vanilla's order (cobalt, water, then iron), with the planted mineral and
	# then any other mineral its roots reach ahead of iron.
	var order: Array = [CONST.SAND, CONST.WATER, planted]
	for m: String in Minerals.ORDER:
		if m != planted and m != CONST.IRON:
			order.append(m)
	order.append(CONST.IRON)
	for fs in fruits[fruitStage]:
		if not fs.type or fs.type == "":
			for t: String in order:
				if rooted.get(t, 0) > 0:
					rooted[t] -= 1
					fs.setType(t)
					break


func tryGrowingStem(growthStage: int):
	if _planted_mineral() == "":
		super(growthStage)
		return
	var resourceTiles: = 0
	for rootCoord in rootCoords:
		if _is_resource(int(Level.map.getTileData().get_resourcev(rootCoord))):
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
	if _planted_mineral() == "":
		super()
		return
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
			var res: int = int(Level.map.getTileData().get_resourcev(root + d))
			if _is_resource(res):
				grown_on_tile.emit(coord)
				return
			elif res == 10:
				freeTiles.append(coord)
	if freeTiles.size() > 0:
		var coord = freeTiles[randi() % freeTiles.size()]
		grown_on_tile.emit(coord)
