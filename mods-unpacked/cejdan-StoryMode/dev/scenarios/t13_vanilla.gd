extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 13: vanilla modes generate no bronze and keep iron.


func boot() -> Dictionary:
	return {"mode": "relichunt", "seed": 12345}


func run(h) -> void:
	h.disable_waves()
	var td = Level.map.tileData
	var mod_tiles: int = 0
	for id in range(40, 50):
		mod_tiles += td.get_resource_cells_by_id(id).size()
	h.check("no mod mineral tiles in a vanilla map", mod_tiles == 0, mod_tiles)
	h.check("vanilla map has iron", td.get_resource_cells_by_id(Data.TILE_IRON).size() > 0, td.get_resource_cells_by_id(Data.TILE_IRON).size())
	var iron0: int = h.inv("iron")
	await h.deliver("iron", 2)
	await h.until(func(): return h.inv("iron") >= iron0 + 2, 8.0)
	h.check("iron still delivered as iron", h.inv("iron") == iron0 + 2, h.inv("iron"))
