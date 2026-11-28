extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #367: the last-chain cutscene in splitscreen (#231). Keeper 1 is in the lava
# ocean by the ship, keeper 2 down a shaft under the dome. The last chain
# breaks: both views take part (each camera leaves its own keeper, both stand
# on the dome shot while the ship is set down, shot of both halves), both
# keepers are frozen (keys held on both devices), the beat opens once and is
# read; then each camera goes back to its own keeper and both play on.

const TIMEOUT := 300
const Split = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t231_split_restart.gd")
static var _Split = Split  # calls go through this: lazy_preload makes const-preload calls slow
const Anchors = preload("res://mods-unpacked/flantor-StoryMode/map/chain_anchors.gd")
static var _Anchors = Anchors  # calls go through this: lazy_preload makes const-preload calls slow
const Ship = preload("res://mods-unpacked/flantor-StoryMode/endgame/ship.gd")
static var _Ship = Ship  # calls go through this: lazy_preload makes const-preload calls slow
const LastChain = preload("res://mods-unpacked/flantor-StoryMode/endgame/last_chain.gd")
static var _LastChain = LastChain  # calls go through this: lazy_preload makes const-preload calls slow
const Cut = preload("res://mods-unpacked/flantor-StoryMode/data/last_chain.gd")
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
static var _StoryBeats = StoryBeats  # calls go through this: lazy_preload makes const-preload calls slow


func boot() -> Dictionary:
	return {"loadout": true, "splitscreen": true}


func run(h) -> void:
	if not await _Split.start_split(h):
		return
	var ok: bool = await h.until(func(): return _Anchors.find() != null and _Ship.find() != null and _LastChain.find() != null, 20.0)
	if not h.check("the anchors, the ship and the cutscene are built", ok):
		return
	var played: Array = Array(str(Data.ofOr(_StoryBeats.PLAYED, "")).split(",", false))
	played.erase(Cut.BEAT_ID)
	Data.apply(_StoryBeats.PLAYED, ",".join(PackedStringArray(played)))
	h.disable_waves()
	var anchors = _Anchors.find()
	var ship = _Ship.find()
	var cut = _LastChain.find()
	var k1 = Keepers.getLocalKeeperByDeviceId(0)
	var k2 = Keepers.getLocalKeeperByDeviceId(1)
	var lava = Level.map.get_node("StoryLavaField")
	var td = Level.map.tileData
	var ocean: Dictionary = td.get_meta("story_ocean")
	var cells: Array = []
	for y in range(int(ocean["ceiling"]), int(ocean["top"]) + 2):
		for x in range(int(ocean["x0"]) - 2, int(ocean["x1"]) + 3):
			cells.append(Vector2i(x, y))
	await h.reveal(cells)
	k1.teleport(ship.to_global(ship.ocean_home) + Vector2(-170, -70))
	await h.dig_room(Vector2i(-2, 8), Vector2i(1, 12))
	await h.teleport_tile(Vector2i(0, 11), k2)
	h.snap_camera(k1)
	h.snap_camera(k2)
	await h.wait(1.0)
	for k in [k1, k2]:
		lava.set_heat_of(k, 0.0)
	await h.shot("before")
	var list: Array = anchors.anchors.duplicate()
	var last: Dictionary = list.pop_back()
	for a in list:
		anchors.dev_break(a["id"], false)
	await h.wait(0.5)
	anchors.dev_break(last["id"], false)
	var started: bool = await h.until(func(): return cut.step == "hold", 3.0)
	h.check("the cutscene plays, with both cameras", started and cut._cams.size() == 2, [cut.step, cut._cams.keys()])
	var at1: Vector2 = k1.global_position
	var at2: Vector2 = k2.global_position
	h.down("ui_left")
	h.pad(1, "ui_right", true)
	await h.until(func(): return cut.step == "set", 20.0)
	var c1 = Level.viewports.getPlayerCam(k1.playerId)
	var c2 = Level.viewports.getPlayerCam(k2.playerId)
	h.check("both views on the dome shot as the ship comes down", c1.global_position.distance_to(cut._shot_c) < 2.0 and c2.global_position.distance_to(cut._shot_c) < 2.0, [c1.global_position, c2.global_position, cut._shot_c])
	await h.shot("both_views_set_down")
	var id: String = await h.read_beat("beat", 15.0)
	h.check("the beat opens once", id == Cut.BEAT_ID, id)
	h.check("both keepers frozen (keys held on both devices)", k1.global_position.distance_to(at1) < 0.5 and k2.global_position.distance_to(at2) < 0.5, [k1.global_position - at1, k2.global_position - at2])
	h.up("ui_left")
	h.pad(1, "ui_right", false)
	var done: bool = await h.until(func(): return cut.step == "done", 15.0)
	await h.wait(0.3)
	h.check("each camera back on its own keeper, play resumes", done and not GameWorld.paused and c1.global_position.distance_to(k1.global_position + c1.targetOffset) < 40.0 and c2.global_position.distance_to(k2.global_position + c2.targetOffset) < 40.0,
		[done, GameWorld.paused, c1.global_position - k1.global_position, c2.global_position - k2.global_position])
	await h.shot("after")
	var p2: Vector2 = k2.global_position
	await h.pad_stick(1, Vector2(1, 0), 1.0)
	h.check("keeper 2 moves again", k2.global_position.distance_to(p2) > 2.0, k2.global_position - p2)
