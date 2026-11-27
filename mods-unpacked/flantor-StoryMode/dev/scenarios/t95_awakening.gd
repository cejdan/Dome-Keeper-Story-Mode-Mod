extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 95: the awakening. The keeper breaks the ten chain anchors in the lava
# ocean (#365; it mined ten unobtainium tiles before Unobtainium went); the
# log shows the seal weakening with each. The seal beats were cut in the
# user's script pass (#285), so a break plays nothing. Breaking into the boss
# chamber wakes it fully and plays the awakening beat.
# Saves to slot 14 for t95_reload.

const Awakening = preload("res://mods-unpacked/flantor-StoryMode/beats/awakening.gd")
static var _Awakening = Awakening  # calls go through this: lazy_preload makes const-preload calls slow
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
static var _StoryBeats = StoryBeats  # calls go through this: lazy_preload makes const-preload calls slow

const Anchors = preload("res://mods-unpacked/flantor-StoryMode/map/chain_anchors.gd")
static var _Anchors = Anchors  # calls go through this: lazy_preload makes const-preload calls slow


func boot() -> Dictionary:
	return {"seed": 12345, "beats": true}


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	Data.apply("team1.story.beatsplayed", "biome_b2,biome_b3,biome_b4,biome_b5,biome_b6,biome_b7,biome_b8,lava_ocean,first_gem,gate_broken,lava_death_1,lava_death_2,lava_death_3,lava_death_4")
	load("res://mods-unpacked/flantor-StoryMode/dev/boss_dev.gd").give_gear()
	h.set_inv("money", 10000000)
	for n in range(1, 5):
		await h.buy("storyheatshield%d" % n)
	h.set_inv("money", 0)
	var field = Level.map.get_node_or_null("StoryLavaField")
	var td = Level.map.tileData
	var anchors = _Anchors.find()
	h.check("the ocean has its ten chain anchors", anchors != null and anchors.anchors.size() == 10, anchors.anchors.size() if anchors else 0)
	h.check("asleep at the start", _Awakening.level() == 0.0 and not _Awakening.is_awake())
	var levels: Array = []
	for i in 10:
		var a: Dictionary = anchors.anchors[i]
		await h.teleport_tile(a["cell"] + Vector2i(0, -2))
		if field != null:
			field.heat = 0.0
		anchors.dev_break(a["id"])
		await h.until(func(): return a["broken"], 3.0)
		await h.frames(3)
		var n: int = i + 1
		levels.append(snappedf(_Awakening.level(), 0.01))
		h.note("chain %d broken" % n, {"anchor": a["id"], "chains": _Awakening.chains(), "level": _Awakening.level()})
		await h.wait(1.0)
		h.check("after chain %d: no beat" % n, not _StoryBeats.is_open())
	h.note("awakening levels", levels)
	var rising: bool = true
	for i in range(1, levels.size()):
		rising = rising and levels[i] >= levels[i - 1]
	h.check("the seal weakens with every chain (to its cap)", rising and levels[0] > 0.0 and _Awakening.chains() == 10, levels)

	# Into the boss chamber. The fight that follows has its own scenarios (#160).
	load("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd").enabled = false
	var room: Rect2i = td.get_meta("story_boss_chamber", Rect2i())
	h.check("the map has a boss chamber", room.size != Vector2i.ZERO, room)
	var inside: Vector2i = room.position + room.size / 2
	await h.teleport_tile(inside)
	var id: String = await h.read_beat("chamber", 6.0)
	h.check("entering the chamber plays the awakening beat", id == "boss_chamber", id)
	h.check("the horror is awake", _Awakening.is_awake() and _Awakening.level() == 1.0, _Awakening.level())
	await h.teleport_tile(inside)
	await h.wait(1.5)
	h.check("re-entering plays nothing", not _StoryBeats.is_open())
	await SaveGame.saveGame("singleplayer", 14, true)
	await h.wait(1.0)
	h.note("saved slot 14", {"chains": _Awakening.chains(), "awake": _Awakening.is_awake()})
