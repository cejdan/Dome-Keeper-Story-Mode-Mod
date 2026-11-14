extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 94: miner bones, one set per biome. A 20-seed map check finds exactly
# one bones tile in each of B1..B8, still bones after the gate, metal and pools
# are placed. In the running game the keeper uncovers each set (no log yet),
# drills it out, and the bones delivered at the dome pay their biome's value and
# open its data log (captured page by page). Saves to slot 13 for t94_reload.

const MapConfig = preload("res://mods-unpacked/cejdan-StoryMode/data/map_config.gd")
const Bones = preload("res://mods-unpacked/cejdan-StoryMode/data/bones.gd")
const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")


func boot() -> Dictionary:
	return {"seed": 12345, "beats": true}


func _report(h) -> void:
	var bad: Array = []
	for s in 20:
		var td = h.generate_map(MapConfig.make_archetype(), 3000 + s)
		if td == null:
			bad.append([3000 + s, "no map"])
			continue
		var placed: Array = td.get_meta("story_bones", [])
		var biomes: Array = placed.map(func(p): return int(p[2]))
		biomes.sort()
		if biomes != [0, 1, 2, 3, 4, 5, 6, 7]:
			bad.append([3000 + s, "biomes", biomes])
		var cells: Array = td.get_resource_cells_by_id(Bones.TILE_ID)
		if cells.size() != 8:
			bad.append([3000 + s, "bones tiles left after generation", cells.size()])
		var pools: Dictionary = {}
		for pool in td.get_meta("story_pools", []):
			for c in pool:
				pools[Vector2i(c)] = true
		for c: Vector2i in cells:
			if pools.has(c):
				bad.append([3000 + s, "in a lava pool", c])
		td.queue_free()
		await h.frames(1)
	h.check("20 seeds: exactly one set of bones in each of B1..B8, none lost to the gate, metal or lava", bad.is_empty(), bad)


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	await _report(h)
	var td = Level.map.tileData
	var placed: Array = td.get_meta("story_bones", [])
	h.check("the run has 8 sets of bones", placed.size() == 8, placed)
	# Only the logs may play: mark the depth and event beats played.
	Data.apply("team1.story.beatsplayed", "biome_b2,biome_b3,biome_b4,biome_b5,biome_b6,biome_b7,biome_b8,lava_ocean,first_gem,gate_broken,lava_death_1,lava_death_2,lava_death_3,lava_death_4")
	h.set_inv("money", 10000000)
	for n in range(1, 5):
		await h.buy("storyheatshield%d" % n)
	h.set_inv("money", 0)
	var dome = Level.getDome("team1")
	placed.sort_custom(func(a, b): return int(a[2]) < int(b[2]))
	for p in placed:
		var at: Vector2i = Vector2i(int(p[0]), int(p[1]))
		var b: int = int(p[2])
		await h.dig_room(at + Vector2i(-2, -3), at + Vector2i(2, -1))
		await h.teleport_tile(at + Vector2i(0, -1))
		# Uncover the bones: no log yet, it comes home with them.
		await h.reveal([at])
		await h.wait(1.5)
		h.check("B%d: uncovering the bones opens no log" % (b + 1), not StoryBeats.is_open() and not StoryBeats.has_played("log_b%d" % (b + 1)), StoryBeats.instance().open_id)
		await h.shot("bones_b%d" % (b + 1))
		# Drill them out and bring them home.
		var m0: int = int(h.inv("money"))
		Level.map.destroyTile("team1", "", Level.map.getTile(Vector2(at)))
		await h.wait(0.5)
		var drop = null
		for d in Level.drops.find_children("*", "", true, false):
			if d.get("type") == Bones.TYPE and not d.absorbed:
				drop = d
		h.check("B%d: the bones drop, worth $%d" % [b + 1, Bones.value_for(b)], drop != null and drop.value == Bones.value_for(b), drop.value if drop else null)
		if drop != null:
			drop.global_position = dome.getDropTarget("iron").global_position + Vector2(0, -8)
			drop.linear_velocity = Vector2.ZERO
			await h.until(func(): return int(h.inv("money")) > m0, 10.0)
		h.check("B%d: delivered bones pay $%d" % [b + 1, Bones.value_for(b)], int(h.inv("money")) - m0 == Bones.value_for(b), int(h.inv("money")) - m0)
		var id: String = await h.read_beat("log_b%d" % (b + 1), 5.0)
		h.check("B%d: selling the bones opens log_b%d" % [b + 1, b + 1], id == "log_b%d" % (b + 1), id)
	var logs: Array = Array(str(Data.ofOr("team1.story.beatsplayed", "")).split(",", false)).filter(func(x): return x.begins_with("log_"))
	h.check("all 8 logs played once", logs.size() == 8, logs)
	h.check("a log never plays twice", not StoryBeats.fire("log_b1"))
	# A bones drop keeps its value through a save: leave one in the mine.
	var spare: Vector2i = Vector2i(int(placed[3][0]), int(placed[3][1])) + Vector2i(0, -2)
	var d2 = Level.drops.network_spawn({"type": Bones.TYPE, "position": Level.map.getTilePos(spare), "impulse": Vector2.ZERO})
	d2.value = 4242
	await h.wait(0.5)
	await SaveGame.saveGame("singleplayer", 13, true)
	await h.wait(1.0)
	h.note("saved slot 13", {"logs": logs})
