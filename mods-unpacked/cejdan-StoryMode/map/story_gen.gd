extends RefCounted

# Story Mode's own steps in map generation, run after vanilla has placed its
# resources (see extensions/content/map/generation/TileDataGenerator.gd).

const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")


static func after_resources(_gen, map_data, _rand: RandomNumberGenerator) -> void:
	# First mineral: every iron tile in the top biome is bronze. The per-biome
	# mineral mix replaces this when the Story Mode map ticket lands.
	var bronze: int = int(Minerals.TABLE["bronze"]["tile_id"])
	for cell: Vector2i in map_data.get_resource_cells_by_id(Data.TILE_IRON):
		if map_data.get_biomev(cell) == 0:
			map_data.set_resourcev(cell, bronze)
