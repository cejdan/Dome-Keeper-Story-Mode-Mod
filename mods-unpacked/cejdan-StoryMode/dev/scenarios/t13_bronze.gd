extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 13: bronze from tile to dollars.

const BRONZE := 40


func boot() -> Dictionary:
	return {"seed": 12345}


func _bronze_cells() -> Array:
	return Level.map.tileData.get_resource_cells_by_id(BRONZE)


func run(h) -> void:
	h.disable_waves()
	var cells: Array = _bronze_cells()
	h.check("map has bronze tiles", cells.size() > 0, cells.size())
	var iron_top: int = 0
	for c: Vector2i in Level.map.tileData.get_resource_cells_by_id(Data.TILE_IRON):
		if Level.map.tileData.get_biomev(c) == 0:
			iron_top += 1
	h.check("no iron left in the top biome", iron_top == 0, iron_top)
	h.map_png("map_overview", {BRONZE: Color("#c99467")})

	# Nearest bronze tile to the shaft.
	cells.sort_custom(func(a, b): return Vector2(a).length() < Vector2(b).length())
	var target: Vector2i = cells[0]
	h.note("bronze tile", target)
	# Dig a room above the bronze tile and stand in it.
	await h.dig_room(target + Vector2i(-2, -2), target + Vector2i(2, -1))
	await h.reveal([target, target + Vector2i(-1, 0), target + Vector2i(1, 0), target + Vector2i(0, 1)])
	await h.teleport_tile(target + Vector2i(0, -1))
	await h.wait(4.0)
	await h.shot("bronze_tile")
	var tile = Level.map.getTile(Vector2(target))
	h.check("tile is bronze and drillable", tile != null and tile.type == "bronze" and Data.isDestructable(tile), tile.type if tile else "none")
	h.note("bronze tile health", {"max_health": tile.max_health, "hardness": tile.hardness, "layer": tile.layer})

	# Three world palettes, same scene: bronze must not change colour.
	for pal: String in ["palette_2_1", "palette_4_1", "palette_6_1"]:
		Style.setPalette(pal)
		await h.wait(0.6)
		await h.shot("bronze_under_" + pal)
	Style.setPalette(Level.loadout.palette)
	await h.wait(0.4)

	# Drill it.
	h.down("ui_down")
	var gone: bool = await h.until(func(): return Level.map.getTile(Vector2(target)) == null, 40.0)
	h.up("ui_down")
	h.check("bronze tile drilled", gone)
	await h.wait(0.5)
	var floating: int = int(Data.ofOr("inventory.floatingbronze", 0))
	h.check("bronze pieces dropped", floating >= 1, floating)
	await h.shot("bronze_drops")

	# Save with bronze on the map and a loose piece in the mine, then load.
	var count_before: int = _bronze_cells().size()
	SaveGame.saveGame(SaveGame.get_run_folder(), 11, true)
	await h.wait(1.5)
	SaveGame.loadGame(SaveGame.get_run_folder(), 11)
	await h.wait(1.0)
	await h.until(func(): return Level.stage != null and Level.stage.get("keeperInputStarted") == true and Level.map != null and Level.map.isMapReady(), 30.0)
	await h.wait(1.5)
	h.disable_waves()
	var count_after: int = _bronze_cells().size()
	h.check("bronze tiles survive save and load", count_after == count_before and count_after > 0, [count_before, count_after])
	var loose: int = 0
	for d in get_drops():
		if d.type == "bronze":
			loose += 1
	h.check("loose bronze pieces survive save and load", loose == floating, [floating, loose])
	await h.shot("after_load")

	# Deliver one piece.
	var money0: int = h.inv("money")
	await h.deliver("bronze", 1)
	await h.until(func(): return h.inv("bronze") >= 1, 8.0)
	h.check("delivered bronze pays $1", h.inv("money") == money0 + 1, [money0, h.inv("money")])
	h.snap("end", ["team1.inventory.bronze", "inventory.floatingbronze"])


func get_drops() -> Array:
	return Level.stage.get_tree().get_nodes_in_group("drops")
