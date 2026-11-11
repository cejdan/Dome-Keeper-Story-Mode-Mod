extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 20: a metal tile that drills cannot hurt, other explosions leave
# alone, and a Suit Blaster blast breaks.

const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


func _metal_at(td, c: Vector2i) -> void:
	td.set_resourcev(c, Metal.TILE_ID)


func run(h) -> void:
	h.disable_waves()
	var td = Level.map.tileData
	var y: int = 9
	var x0: int = 0

	# A row under a dug room: rock, metal, metal, rock, metal (and rock below).
	for x in range(x0 - 4, x0 + 5):
		td.set_resourcev(Vector2i(x, y), Data.TILE_DIRT_START)
		td.set_resourcev(Vector2i(x, y + 1), Data.TILE_DIRT_START)
	for x in [x0 - 1, x0, x0 + 3]:
		_metal_at(td, Vector2i(x, y))
	_metal_at(td, Vector2i(x0, y + 1))
	await h.dig_room(Vector2i(x0 - 4, y - 3), Vector2i(x0 + 4, y - 1))
	var row: Array = []
	for x in range(x0 - 5, x0 + 6):
		row.append(Vector2i(x, y))
		row.append(Vector2i(x, y + 1))
	await h.reveal(row)
	await h.teleport_tile(Vector2i(x0, y - 1))
	await h.wait(3.0)
	await h.shot("metal_row")

	var tile = Level.map.getTile(Vector2(x0, y))
	h.check("metal tile has type metal", tile != null and tile.type == Metal.TYPE, tile.type if tile else "none")
	h.check("metal tile counts as destructable (blasts reach it)", tile != null and Data.isDestructable(tile))
	var full: float = tile.health

	# Drill straight down into it for 10 seconds.
	await h.hold("ui_down", 10.0)
	tile = Level.map.getTile(Vector2(x0, y))
	h.check("10 s of drilling leaves the metal tile", tile != null)
	h.check("and at full health", tile != null and tile.health == full, [tile.health if tile else -1, full])
	h.snap("after_drill", [])
	h.note("metal health", {"health": tile.health if tile else -1, "max": tile.max_health if tile else -1})
	await h.shot("after_drill")

	# Drill the rock next to it for comparison: rock breaks.
	await h.hold("ui_left", 0.3)
	var rock_coord: Vector2 = Vector2(x0 - 2, y)
	await h.teleport_tile(Vector2i(x0 - 2, y - 1))
	await h.hold("ui_down", 6.0)
	h.check("the rock tile next to it breaks under the same drill", Level.map.getTile(rock_coord) == null)

	# A non-Suit-Blaster explosion (Blast Mining and bomb caves use this call).
	await h.teleport_tile(Vector2i(x0 + 2, y - 1))
	Level.map.damageTileCircleArea(Level.map.getTilePos(Vector2(x0 + 3, y)), 1.5, 5000, "team1")
	await h.wait(1.5)
	h.check("another explosion leaves the metal tile", Level.map.getTile(Vector2(x0 + 3, y)) != null)

	# Now the Suit Blaster: grant it, stand on the metal, blast.
	GameWorld.serverAddUpgrade("player1.suitblaster", "team1")
	await h.wait(1.0)
	Data.apply("player1.suitblaster.charge", 1.0)
	h.note("blaster", {"radius": Data.ofOr("team1.suitblaster.radius", -1), "charge": Data.ofOr("player1.suitblaster.charge", -1)})
	await h.teleport_tile(Vector2i(x0, y - 1))
	await h.wait(1.0)
	await h.shot("before_blast")
	await h.press("keeper_gadget1")
	await h.burst("blast", 16, 3)
	await h.wait(2.0)
	h.check("Suit Blaster blast breaks the metal tile under the keeper", Level.map.getTile(Vector2(x0, y)) == null)
	h.check("and the metal tile beside it", Level.map.getTile(Vector2(x0 - 1, y)) == null)
	await h.shot("after_blast")
	h.snap("end", [])
