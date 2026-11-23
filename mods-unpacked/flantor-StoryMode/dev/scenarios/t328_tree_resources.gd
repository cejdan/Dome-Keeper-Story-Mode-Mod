extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 328: a Mineral Tree grows what it is planted on. On cobalt and water
# it grows exactly what vanilla grows (its free fruit is iron, and its roots
# ignore the mod's mineral tiles next to it, here gold); on a mod mineral it
# grows that mineral. Each tree is planted on a row of root tiles in its own
# dug-out room, and its stem, roots and fruit are stepped by hand the way the
# seed cave steps them. Run with -Extra "--mode=relichunt" to see vanilla give
# the same cobalt and water fruit.

const GOLD_ID := 41
const BRONZE_ID := 40
const SAPPHIRE_ID := 42


func boot() -> Dictionary:
	return {"seed": 12345}


# Plants a tree on `roots[0]` at (x0, y); roots[i] goes at x0 + i, `left` at x0 - 1.
func _plant(h, x0: int, y: int, roots: Array, left: int):
	var td = Level.map.tileData
	# No magma or gas pocket of the map's own near the set (t289's clear_hazards).
	var lava = Level.map.get_node_or_null("StoryLavaField")
	var gas = Level.map.get_node_or_null("StoryGasField")
	for yy in range(y - 8, y + 7):
		for x in range(x0 - 8, x0 + 9):
			if lava != null:
				lava.magma.erase(Vector2i(x, yy))
			if gas != null:
				gas.rock.erase(Vector2i(x, yy))
	for yy in range(y - 4, y + 3):
		for x in range(x0 - 4, x0 + 5):
			td.set_resourcev(Vector2i(x, yy), Data.TILE_DIRT_START)
	for i in roots.size():
		td.set_resourcev(Vector2i(x0 + i, y), roots[i])
	if left >= 0:
		td.set_resourcev(Vector2i(x0 - 1, y), left)
	await h.dig_room(Vector2i(x0 - 3, y - 4), Vector2i(x0 + 3, y - 1))
	var row: Array = []
	for x in range(x0 - 4, x0 + 5):
		row.append(Vector2i(x, y))
		row.append(Vector2i(x, y + 1))
	await h.reveal(row)
	var tree = load("res://content/gadgets/mineraltree/MineralTree.tscn").instantiate()
	tree.name = "TestTree%d" % y
	tree.teamId = "team1"
	tree.UID = 4300 + y
	tree.global_position = Level.map.getTilePos(Vector2(x0, y - 1))
	tree.growOnTile(Vector2(x0, y))
	Level.map.add_child(tree)
	tree.growthCooldown = 1e9  # the stem is stepped below, not on its timer
	# A seed cave wires these up for the trees it plants (SeedCave.registerTree).
	tree.fruits_grown.connect(tree.growFruits)
	tree.stem_grown.connect(tree.tryGrowingStem)
	tree.grown_on_tile.connect(tree.growOnTile)
	# Nine steps: stage 15 by the seventh; roots reach at most nine tiles, short
	# of the next set ten rows down.
	for i in 9:
		tree.tryGrowingStem(tree.currentGrowthStage)
		tree.tryRooting()
		tree.growFruits(tree.currentGrowthStage)
		await h.frames(2)
	await h.teleport_tile(Vector2i(x0 + 2, y - 1))
	await h.wait(0.5)
	return tree


func _types(tree) -> Array:
	var types: Array = []
	for fs in tree.fruits.get(tree.fruitStage, []):
		types.append(fs.type)
	types.sort()
	return types


func _case(h, label: String, tree, want: Array) -> void:
	want = want.duplicate()
	want.sort()
	var types: Array = _types(tree)
	var td = Level.map.tileData
	var root_res: Array = []
	for c in tree.rootCoords:
		root_res.append(td.get_resourcev(Vector2i(c)))
	h.note(label, {"stage": tree.currentGrowthStage, "roots": root_res, "fruit": types})
	h.check(label + ": fruit is " + str(want), types == want, types)
	await h.shot(label.replace(" ", "_"))


func run(h) -> void:
	h.disable_waves()
	var story: bool = Level.loadout.modeId == "storymode"
	var gold: int = GOLD_ID if story else -1
	h.note("mode", Level.loadout.modeId)

	# Vanilla: cobalt + cobalt roots -> stage 10, one cobalt and the free iron.
	var t1 = await _plant(h, -6, 10, [Data.TILE_SAND, Data.TILE_SAND], gold)
	await _case(h, "on cobalt", t1, [CONST.SAND, CONST.IRON])
	if story:
		h.check("on cobalt: no root on the gold beside it, as vanilla",
			not t1.rootCoords.has(Vector2(-7, 10)), t1.rootCoords)

	# Vanilla: water + two iron roots -> stage 15, the water and two iron.
	var t2 = await _plant(h, -6, 20, [Data.TILE_WATER, Data.TILE_IRON, Data.TILE_IRON], gold)
	await _case(h, "on water", t2, [CONST.WATER, CONST.IRON, CONST.IRON])

	if not story:
		return

	# Mod minerals: what the tree is planted on.
	var t3 = await _plant(h, -6, 30, [BRONZE_ID, BRONZE_ID, BRONZE_ID], -1)
	await _case(h, "on bronze", t3, ["bronze", "bronze", "bronze"])

	var t4 = await _plant(h, -6, 40, [SAPPHIRE_ID, Data.TILE_SAND], -1)
	await _case(h, "on sapphire", t4, ["sapphire", CONST.SAND])

	# Hitting the sapphire fruit drops a sapphire.
	var fruit = null
	for fs in t4.fruits[t4.fruitStage]:
		if fs.type == "sapphire":
			fruit = fs
	if fruit != null:
		fruit.remainingCycles = 0
		fruit.visible = true
		var floating0: int = int(Data.ofOr("inventory.floatingsapphire", 0))
		fruit.registerHit("player1")
		await h.wait(1.0)
		h.check("hitting the sapphire fruit drops a sapphire",
			int(Data.ofOr("inventory.floatingsapphire", 0)) == floating0 + 1, Data.ofOr("inventory.floatingsapphire", 0))
		await h.shot("sapphire_hit")
	else:
		h.check("hitting the sapphire fruit drops a sapphire", false, "no sapphire fruit")
