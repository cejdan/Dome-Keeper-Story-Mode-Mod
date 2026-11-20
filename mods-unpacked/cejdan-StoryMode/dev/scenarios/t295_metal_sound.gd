extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 295: drilling metal clanks on steel; the dig sound and the pitch that
# climbs as a tile wears down stay quiet. Rock still sounds as before.

const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")
const Sounds = preload("res://mods-unpacked/cejdan-StoryMode/extensions/content/keeper/keeper1/TileHitSounds.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


# While `action` is held for `sec`, which of the keeper's tile hit sounds are
# heard (sampled every few frames).
func _drill_and_listen(h, action: String, sec: float) -> Dictionary:
	var sounds: Node = h.keeper().get_node("TileHitSounds")
	var heard: Dictionary = {}
	h.down(action)
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		for s in sounds.get_children():
			if s is AudioStreamPlayer and s.playing:
				heard[String(s.name)] = true
		await h.frames(3)
	h.up(action)
	return heard


func _dig_sound(heard: Dictionary) -> bool:
	return heard.has("TileHitPitch") or heard.keys().any(func(n): return n.begins_with("TileHitHardness"))


func run(h) -> void:
	h.disable_waves()
	var td = Level.map.tileData
	var y: int = 9
	for x in range(-4, 5):
		td.set_resourcev(Vector2i(x, y), Data.TILE_DIRT_START)
		td.set_resourcev(Vector2i(x, y + 1), Data.TILE_DIRT_START)
	td.set_resourcev(Vector2i(0, y), Metal.TILE_ID)
	td.set_resourcev(Vector2i(0, y + 1), Metal.GATE_ID)
	await h.dig_room(Vector2i(-4, y - 3), Vector2i(4, y - 1))
	var row: Array = []
	for x in range(-5, 6):
		row.append(Vector2i(x, y))
		row.append(Vector2i(x, y + 1))
	await h.reveal(row)
	await h.teleport_tile(Vector2i(0, y - 1))
	await h.wait(2.0)

	var sounds: Node = h.keeper().get_node("TileHitSounds")
	h.check("the keeper's tile hit sounds run the Story Mode extension", sounds.has_method("_metal_player"))
	var hits0: int = Sounds.metal_hits
	var heard: Dictionary = await _drill_and_listen(h, "ui_down", 4.0)
	h.note("drilling metal", {"heard": heard.keys(), "metal hits": Sounds.metal_hits - hits0})
	h.check("drilling metal plays the metal clank", heard.has("TileHitMetal") and Sounds.metal_hits - hits0 >= 3, heard.keys())
	h.check("and no dig or rising-pitch sound", not _dig_sound(heard), heard.keys())
	h.check("the metal is still there", Level.map.getTile(Vector2(0, y)) != null)
	await h.shot("metal_drilled")

	await h.teleport_tile(Vector2i(-2, y - 1))
	await h.wait(1.0)
	var hits1: int = Sounds.metal_hits
	heard = await _drill_and_listen(h, "ui_down", 3.0)
	h.note("drilling rock", {"heard": heard.keys(), "metal hits": Sounds.metal_hits - hits1})
	h.check("drilling rock plays the dig sounds as vanilla", _dig_sound(heard) and Sounds.metal_hits == hits1, heard.keys())
	h.check("and the rock breaks", Level.map.getTile(Vector2(-2, y)) == null)
