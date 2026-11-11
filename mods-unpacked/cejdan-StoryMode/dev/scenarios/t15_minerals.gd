extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 15: every mineral can be told apart on the map, and one of each pays
# the right total.

const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	var td = Level.map.tileData
	# A gallery row: the nine minerals, then water and cobalt, one tile apart,
	# under a dug room. Row y=9 is deep enough to be unrevealed rock.
	var y: int = 9
	var x0: int = -11
	var placed: Dictionary = {}
	var i: int = 0
	for m: String in Minerals.ORDER:
		var c: Vector2i = Vector2i(x0 + i * 2, y)
		td.set_resourcev(c, int(Minerals.TABLE[m]["tile_id"]))
		placed[m] = c
		i += 1
	td.set_resourcev(Vector2i(x0 + i * 2, y), Data.TILE_WATER)
	td.set_resourcev(Vector2i(x0 + (i + 1) * 2, y), Data.TILE_SAND)
	for x in range(x0 - 1, x0 + 24):
		if (x - x0) % 2 != 0:
			td.set_resourcev(Vector2i(x, y), Data.TILE_DIRT_START)
		td.set_resourcev(Vector2i(x, y + 1), Data.TILE_DIRT_START)
	await h.dig_room(Vector2i(x0 - 1, y - 3), Vector2i(x0 + 23, y - 1))
	var row: Array = []
	for x in range(x0 - 1, x0 + 24):
		row.append(Vector2i(x, y))
		row.append(Vector2i(x, y + 1))
	await h.reveal(row)
	await h.teleport_tile(Vector2i(x0 + 4, y - 1))
	await h.wait(4.0)
	await h.shot("gallery_left")
	await h.teleport_tile(Vector2i(x0 + 15, y - 1))
	await h.wait(4.0)
	await h.shot("gallery_right")

	for m: String in Minerals.ORDER:
		var tile = Level.map.getTile(Vector2(placed[m]))
		h.check(m + " tile has its type and is drillable", tile != null and tile.type == m and Data.isDestructable(tile), tile.type if tile else "none")

	# Break every gallery tile and look at the pieces.
	var coords: Array = []
	for m: String in Minerals.ORDER:
		coords.append(Vector2(placed[m]))
	Level.map.freeTiles(coords)
	await h.wait(2.5)
	await h.shot("pieces_right")
	await h.teleport_tile(Vector2i(x0 + 4, y - 1))
	await h.wait(4.0)
	await h.shot("pieces_left")
	var floating: Dictionary = {}
	for m: String in Minerals.ORDER:
		floating[m] = int(Data.ofOr("inventory.floating" + m, 0))
		h.check(m + " dropped pieces", floating[m] >= 1, floating[m])

	# Deliver one of each.
	var money0: int = h.inv("money")
	var total: int = 0
	for m: String in Minerals.ORDER:
		await h.deliver(m, 1)
		total += Minerals.value_of(m)
	await h.until(func(): return h.inv("money") >= money0 + total, 15.0)
	h.check("one of each pays $%d" % total, h.inv("money") == money0 + total, [money0, h.inv("money")])
	h.check("total is $101,966", total == 101966, total)
	await h.wait(1.0)
	await h.shot("after_delivery")
	h.snap("end", ["team1.story.pieces"])
