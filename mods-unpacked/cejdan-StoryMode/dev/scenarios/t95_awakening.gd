extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 95: the awakening. The keeper mines ten unobtainium tiles in the lava
# ocean; the log shows the seal weakening with each, and the horror's beats
# play after the 1st, 3rd, 5th, 7th and 10th. Breaking into the boss chamber
# wakes it fully: the awakening beat, then the placeholder "not yet" beat.
# Saves to slot 14 for t95_reload.

const Awakening = preload("res://mods-unpacked/cejdan-StoryMode/beats/awakening.gd")
const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")

const UNOB_ID := 47


func boot() -> Dictionary:
	return {"seed": 12345, "beats": true}


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	Data.apply("team1.story.beatsplayed", "biome_b2,biome_b3,biome_b4,biome_b5,biome_b6,biome_b7,biome_b8,lava_ocean,first_gem,gate_broken,lava_death_1,lava_death_2,lava_death_3,lava_death_4")
	h.set_inv("money", 10000000)
	for n in range(1, 5):
		await h.buy("storyheatshield%d" % n)
	h.set_inv("money", 0)
	var field = Level.map.get_node_or_null("StoryLavaField")
	var td = Level.map.tileData
	var cells: Array = td.get_resource_cells_by_id(UNOB_ID)
	cells.sort_custom(func(a, b): return absi(a.x) + a.y < absi(b.x) + b.y)
	h.check("the ocean holds at least 10 unobtainium tiles", cells.size() >= 10, cells.size())
	h.check("asleep at the start", Awakening.level() == 0.0 and not Awakening.is_awake())
	var levels: Array = []
	var expect_beat: Dictionary = {1: "unobtainium_1", 3: "unobtainium_3", 5: "unobtainium_5", 7: "unobtainium_7", 10: "unobtainium_10"}
	for i in 10:
		var c: Vector2i = cells[i]
		await h.reveal([c])
		await h.teleport_tile(c + Vector2i(0, -1))
		if field != null:
			field.heat = 0.0
		Level.map.destroyTile("team1", "", Level.map.getTile(Vector2(c)))
		await h.frames(3)
		var n: int = i + 1
		levels.append(snappedf(Awakening.level(), 0.01))
		h.note("unobtainium %d mined" % n, {"cell": c, "mined": Awakening.mined(), "level": Awakening.level()})
		if expect_beat.has(n):
			var id: String = await h.read_beat("unob%02d" % n, 6.0)
			h.check("after the %s unobtainium: %s plays" % [["", "1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th", "10th"][n], expect_beat[n]], id == expect_beat[n], id)
		else:
			await h.wait(1.0)
			h.check("after unobtainium %d: no beat" % n, not StoryBeats.is_open())
	h.note("awakening levels", levels)
	var rising: bool = true
	for i in range(1, levels.size()):
		rising = rising and levels[i] > levels[i - 1]
	h.check("the seal weakens with every piece", rising and Awakening.mined() == 10, levels)
	h.check("the mined deposits are recorded per cell", Awakening.freed(cells[0]) and Awakening.freed(cells[9]) and not Awakening.freed(cells[10] if cells.size() > 10 else Vector2i(9999, 9999)))

	# Into the boss chamber.
	var room: Rect2i = td.get_meta("story_boss_chamber", Rect2i())
	h.check("the map has a boss chamber", room.size != Vector2i.ZERO, room)
	var inside: Vector2i = room.position + room.size / 2
	await h.teleport_tile(inside)
	var id: String = await h.read_beat("chamber", 6.0)
	h.check("entering the chamber plays the awakening beat", id == "boss_chamber", id)
	h.check("the horror is awake", Awakening.is_awake() and Awakening.level() == 1.0, Awakening.level())
	var wait_id: String = await h.read_beat("not_yet", 6.0)
	h.check("then the placeholder beat (come closer, not yet)", wait_id == "boss_wait", wait_id)
	await h.teleport_tile(inside)
	await h.wait(1.5)
	h.check("re-entering plays nothing", not StoryBeats.is_open())
	await SaveGame.saveGame("singleplayer", 14, true)
	await h.wait(1.0)
	h.note("saved slot 14", {"mined": Awakening.mined(), "awake": Awakening.is_awake(), "first cell": cells[0]})
