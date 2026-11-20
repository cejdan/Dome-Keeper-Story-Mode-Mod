extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 51: gadgets are bought, never found: no vanilla gadget chambers.
# The shop itself (New Gadget I-IV since #132) is checked by t132_new_gadget.

const MapConfig = preload("res://mods-unpacked/flantor-StoryMode/data/map_config.gd")
static var _MapConfig = MapConfig  # calls go through this: lazy_preload makes const-preload calls slow


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	# ---- no gadget chambers, 20 seeds
	var chambers: int = 0
	for s in 20:
		var td = h.generate_map(_MapConfig.make_archetype(), 2000 + s)
		if td != null:
			chambers += td.get_resource_cells_by_id(Data.TILE_GADGET).size()
			td.queue_free()
		await h.frames(1)
	h.check("20 seeds: the only gadget-id tiles are the 3 translator chambers (12 tiles a map, #93)", chambers == 20 * 12, chambers)
	h.check("this run's map: no vanilla gadget chamber", Level.map.find_children("GadgetChamber*", "", true, false).is_empty())
