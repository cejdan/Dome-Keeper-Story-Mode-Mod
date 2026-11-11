extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 55: in Story Mode the Iron Tree cave and the Mineral Tree grow gold.
# Run with -Extra "--mode=relichunt" to check that vanilla trees still give iron.


func boot() -> Dictionary:
	return {"seed": 12345}


func _find_tree_cave():
	for n in Level.map.find_children("*", "", true, false):
		if n.scene_file_path.ends_with("IronTreeCave.tscn"):
			return n
	return null


func run(h) -> void:
	h.disable_waves()
	var story: bool = Level.loadout.modeId == "storymode"
	var want: String = "gold" if story else "iron"
	h.note("mode", {"mode": Level.loadout.modeId, "fruit": want})

	# ---- Iron Tree cave
	var cave = _find_tree_cave()
	if cave == null:
		# This seed has none: place one the way the map places caves.
		cave = Data.CAVE_SCENES["iron"].instantiate()
		cave.updateUsedTileCoords()
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		Level.map.addCave(rng, cave, 1, 6)
		h.note("placed an Iron Tree cave", cave.coord)
	h.check("an Iron Tree cave is on the map", cave != null and cave.is_inside_tree())
	if cave != null:
		var area: Array = []
		for c in cave.tileCoords:
			area.append(Vector2i(cave.coord + Vector2(c)))
		await h.reveal(area)
		await h.clear_tiles(area)
		h.keeper().teleport(cave.get_node("%Iron1").global_position + Vector2(0, 10))
		h.snap_camera()
		await h.wait(3.0)
		await h.shot("tree_cave")
		var fruit = cave.get_node("%Iron1")
		var floating0: int = int(Data.ofOr("inventory.floating" + want, 0))
		var money0: int = int(h.inv("money"))
		var inv0: int = int(h.inv(want))
		fruit.registerHit("player1")
		await h.wait(1.0)
		h.check("hitting a fruit drops " + want, int(Data.ofOr("inventory.floating" + want, 0)) == floating0 + 1, Data.ofOr("inventory.floating" + want, 0))
		await h.shot("fruit_hit")
		# Carry it home: the keeper teleports into the dome with the drop on its line.
		var dome = Level.getDome("team1")
		h.keeper().teleport(dome.getDropTarget(want).global_position + Vector2(0, -10))
		h.snap_camera()
		await h.until(func(): return int(h.inv(want)) > inv0, 15.0)
		h.check("delivering it counts one " + want, int(h.inv(want)) == inv0 + 1, h.inv(want))
		if story:
			h.check("and pays $10", int(h.inv("money")) == money0 + 10, [money0, h.inv("money")])
		fruit.regrowCooldown = 0.05
		await h.wait(1.0)
		h.check("the fruit regrows", fruit.visible and not fruit.taken)

	# ---- Mineral Tree rooted on mineral tiles
	var td = Level.map.tileData
	var y: int = 12
	var x0: int = -6
	var root_id: int = 40 if story else Data.TILE_IRON  # bronze in Story Mode
	for x in range(x0 - 3, x0 + 4):
		td.set_resourcev(Vector2i(x, y), root_id)
		td.set_resourcev(Vector2i(x, y + 1), root_id)
	await h.dig_room(Vector2i(x0 - 3, y - 4), Vector2i(x0 + 3, y - 1))
	var row: Array = []
	for x in range(x0 - 4, x0 + 5):
		row.append(Vector2i(x, y))
		row.append(Vector2i(x, y + 1))
	await h.reveal(row)
	var tree = load("res://content/gadgets/mineraltree/MineralTree.tscn").instantiate()
	tree.name = "TestTree"
	tree.teamId = "team1"
	tree.UID = 4242
	tree.global_position = Level.map.getTilePos(Vector2(x0, y - 1))
	tree.growOnTile(Vector2(x0, y))
	Level.map.add_child(tree)
	# A seed cave wires these up for the trees it plants (SeedCave.registerTree).
	tree.fruits_grown.connect(tree.growFruits)
	tree.stem_grown.connect(tree.tryGrowingStem)
	tree.grown_on_tile.connect(tree.growOnTile)
	await h.teleport_tile(Vector2i(x0 + 2, y - 1))
	h.speed(6.0)
	# Stems grow on the tree's own timer; fruit grows each wave cycle.
	var grown: bool = false
	for i in 30:
		await h.wait(12.0)
		Data.changeByInt("team1.monsters.cycle", 1)
		await h.frames(2)
		for st in tree.fruits:
			for fs in tree.fruits[st]:
				if fs.type != "" and fs.visible:
					grown = true
		if grown:
			break
	h.speed(1.0)
	var types: Array = []
	for st in tree.fruits:
		for fs in tree.fruits[st]:
			if fs.type != "":
				types.append(fs.type)
	h.note("mineral tree", {"stage": tree.currentGrowthStage, "roots": tree.rootCoords.size(), "fruit types": types})
	h.check("the Mineral Tree grew fruit", grown, types)
	h.check("its fruit is " + want, types.size() > 0 and types.all(func(t): return t == want), types)
	await h.wait(1.0)
	await h.shot("mineral_tree")
