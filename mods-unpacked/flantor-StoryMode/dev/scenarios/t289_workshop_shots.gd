extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 289: Workshop screenshots (run fullscreen at 1920x1080, see
# dev/workshop_shoot.gd): the shop, the first four minerals in the rock, a
# miner's bones, a translator chamber opened, and the first story beat (B2).

const Shoot = preload("res://mods-unpacked/flantor-StoryMode/dev/workshop_shoot.gd")
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
const Bones = preload("res://mods-unpacked/flantor-StoryMode/data/bones.gd")
const TIMEOUT := 900


func boot() -> Dictionary:
	return {"seed": 12345}


func _settle(h, at: Vector2i) -> void:
	await h.teleport_tile(at)
	h.keeper().set("gravity_scale", 0.0)
	await h.wait(1.5)
	h.snap_camera()
	await h.wait(1.0)


func run(h) -> void:
	Shoot.window_1080()
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.5)
	h.disable_waves()
	var td = Level.map.tileData

	# ---- the shop
	h.set_inv("money", 2400)
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(2.0)
	await h.shot("shop")
	await h.press("ui_cancel")
	await h.wait(1.0)

	# ---- minerals: bronze, iron, gold, sapphire in the walls of a B1/B2 room
	var o: Vector2i = Shoot.find_rock(td, 12, 5, [0, 1], 6, 40, -30, 20)
	h.check("rock for the mineral room", o.x != -9999, o)
	var room: Array = Shoot.rect(o + Vector2i(1, 1), 10, 3)
	var ores := {40: [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(0, 3)],
		0: [Vector2i(4, 0), Vector2i(5, 0), Vector2i(3, 4), Vector2i(4, 4)],
		41: [Vector2i(7, 0), Vector2i(8, 0), Vector2i(7, 4), Vector2i(8, 4)],
		42: [Vector2i(10, 0), Vector2i(11, 1), Vector2i(11, 2), Vector2i(10, 4)]}
	for id in ores:
		for d in ores[id]:
			td.set_resourcev(o + d, id)
	await h.reveal(Shoot.rect(o - Vector2i(2, 2), 16, 9))
	await h.clear_tiles(room)
	await _settle(h, o + Vector2i(5, 2))
	await h.shot("minerals")

	# ---- a miner's bones in the rock
	var bones := Vector2i(-9999, -9999)
	for c in td.get_used_cells(MapData.LAYER_BIOME):
		if td.get_resourcev(c) == Bones.TILE_ID and td.get_biomev(c) == 1:
			bones = c
	h.check("B2 has its bones", bones.x != -9999, bones)
	await h.reveal(Shoot.rect(bones - Vector2i(4, 3), 10, 7))
	await h.clear_tiles([bones + Vector2i(1, 0), bones + Vector2i(2, 0), bones + Vector2i(3, 0), bones + Vector2i(1, -1), bones + Vector2i(2, -1)])
	await _settle(h, bones + Vector2i(2, 0))
	await h.shot("bones")

	# ---- a translator chamber, opened
	var chambers: Array = []
	for c in Level.map.find_children("*", "", true, false):
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("TranslatorChamber.gd"):
			chambers.append(c)
	chambers.sort_custom(func(a, b): return a.global_position.y < b.global_position.y)
	h.check("a translator chamber", not chambers.is_empty(), chambers.size())
	var ch = chambers[0]
	var at: Vector2i = Level.map.getTileCoord(ch.global_position + Vector2(12, 12))
	await h.dig_room(at + Vector2i(-3, -3), at + Vector2i(4, -1))
	await h.reveal([at, at + Vector2i(1, 0), at + Vector2i(0, 1), at + Vector2i(1, 1)])
	await _settle(h, at + Vector2i(-1, -1))
	await h.shot("translator_sealed")
	for c: Vector2i in [at, at + Vector2i(1, 0), at + Vector2i(0, 1), at + Vector2i(1, 1)]:
		var t = Level.map.getTile(Vector2(c))
		if t != null:
			Level.map.destroyTile("team1", "", t)
	await h.until(func(): return ch.currentState == ch.State.OPEN, 8.0)
	await h.wait(1.5)
	await h.shot("translator_open")

	# ---- the first story beat, in B2
	await _settle(h, o + Vector2i(5, 2))
	# The harness marked every beat played: take B2's back out and play it.
	var played: Array = Array(str(Data.ofOr("team1.story.beatsplayed", "")).split(",", false))
	played.erase("biome_b2")
	Data.apply("team1.story.beatsplayed", ",".join(PackedStringArray(played)))
	StoryBeats.instance().set("muted", false)
	StoryBeats.fire("biome_b2")
	await h.until(func(): return StoryBeats.is_open(), 8.0)
	for page in 4:
		await h.wait(5.0)
		await h.shot("beat_b2_p%d" % (page + 1))
		await h.press("ui_select")
		await h.wait(0.4)
		if not StoryBeats.is_open():
			break
