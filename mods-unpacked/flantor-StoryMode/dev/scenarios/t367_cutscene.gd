extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t368_land.gd"

# #367: the last-chain cutscene, live (huge map, seed 12345, the Engineer).
# Nine chains break quietly; the keeper hovers by the last anchor (the one
# nearest the ship) and the last one breaks by the real tile path. Then:
#   play freezes (the keeper doesn't move with a key held, its heat doesn't
#   change, the wave clock and the lava stop, nothing takes damage); every
#   step in order, shot at each and bursts over the moves (the rise, the
#   break-out, the carry, the set-down); the coil drags the ship under in the
#   ocean, then the ship comes up out of the ground by the dome in the coil,
#   is set down and the coil goes back in; the ship stands at the dome, clean
#   and lit; the beat ("last_chain", [DRAFT]) opens over it and is read; the
#   camera comes back to the keeper; play resumes; done once, live (signal,
#   waiter, Data); the seal's opening waited for the end and then plays as
#   the seal is seen. Saves slot 67 after it (t367_reload).
# `-Extra "--midsave"`: saves slot 70 in the middle of the carry instead and
# stops there (t367_reload_mid loads it).

const LastChain = preload("res://mods-unpacked/flantor-StoryMode/endgame/last_chain.gd")
static var _LastChain = LastChain  # calls go through this: lazy_preload makes const-preload calls slow
const LairSeal = preload("res://mods-unpacked/flantor-StoryMode/endgame/lair_seal.gd")
static var _LairSeal = LairSeal  # calls go through this: lazy_preload makes const-preload calls slow
const Cut = preload("res://mods-unpacked/flantor-StoryMode/data/last_chain.gd")
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
static var _StoryBeats = StoryBeats  # calls go through this: lazy_preload makes const-preload calls slow
const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const AFTER_SLOT := 67
const MID_SLOT := 70


var cut
var steps_seen: Array = []
var finished: Array = []
var waited: Array = []


func boot() -> Dictionary:
	return {"seed": 12345, "boss": false}


# The last_chain beat may play (every other beat stays muted).
func unmute_cut_beat() -> void:
	var played: Array = Array(str(Data.ofOr(_StoryBeats.PLAYED, "")).split(",", false))
	played.erase(Cut.BEAT_ID)
	Data.apply(_StoryBeats.PLAYED, ",".join(PackedStringArray(played)))


# Every chain but the one nearest the ship, quietly; returns that one.
func break_all_but_last(h) -> Dictionary:
	var home: Vector2 = ship.to_global(ship.ocean_home)
	var list: Array = anchors.anchors.duplicate()
	list.sort_custom(func(x, y): return x["centre"].distance_to(home) > y["centre"].distance_to(home))
	var last: Dictionary = list.pop_back()
	for a in list:
		anchors.dev_break(a["id"], false)
	await h.wait(1.0)
	return last


func run(h) -> void:
	if not await setup(h):
		return
	ship = _Ship.find()
	cut = _LastChain.find()
	if not h.check("the run has a ship and the cutscene", ship != null and cut != null, [ship, cut]):
		return
	unmute_cut_beat()
	cut.step_changed.connect(func(s): steps_seen.append([s, snappedf(cut.total, 0.01)]))
	cut.cutscene_finished.connect(func(l): finished.append(l))
	_LastChain.when_done(func(l): waited.append(l))
	var k = h.keeper()
	await reveal_ocean(h)
	var last: Dictionary = await break_all_but_last(h)
	h.check("nine chains: the ship still in the coil, no cutscene", ship.mode == "ocean" and cut.step == "idle" and not _LastChain.is_done(), [ship.mode, cut.step])
	# The keeper by the last anchor, its camera on it.
	var spot: Dictionary = stand_by(last)
	await h.teleport_tile(spot["cell"])
	cool(h)
	await h.wait(1.0)
	await h.shot("before_last_chain")
	var midsave: bool = _Story.has_user_arg("midsave")
	var seal = _LairSeal.find()
	var k_at: Vector2 = k.global_position
	h.down("ui_left")
	anchors.dev_break(last["id"], true)
	var started: bool = await h.until(func(): return cut.step == "hold", 3.0)
	h.check("the last chain starts the cutscene", started and _EndGame.is_free() and ship.mode == "carried", [cut.step, ship.mode])
	h.check("play freezes", GameWorld.paused, GameWorld.paused)
	var heat0: float = lava.heat_of(k)
	k_at = k.global_position
	var wave0 = Data.ofOr("monsters.wavecooldown", null)
	await h.wait(0.5)
	await h.shot("hold_coil_lets_go")
	await h.until(func(): return cut.step == "rise", 4.0)
	await h.wait(0.2)
	await h.burst("rise", 10, 8)
	await h.until(func(): return cut.step == "crack", 8.0)
	await h.wait(0.6)
	await h.shot("crack")
	await h.until(func(): return cut.step == "burst", 4.0)
	await h.burst("burst", 8, 3)
	await h.until(func(): return cut.step == "carry", 4.0)
	await h.wait(0.5)
	if midsave:
		SaveGame.saveGame("singleplayer", MID_SLOT, true)
		await h.wait(1.0)
		h.note("saved slot %d mid-cutscene" % MID_SLOT, {"step": cut.step, "done_key": Data.ofOr(_LastChain.DONE_KEY, null), "state": _EndGame.state()})
		h.check("saved mid-cutscene (the done key says it is playing)", float(Data.ofOr(_LastChain.DONE_KEY, 0.0)) < 0.0, Data.ofOr(_LastChain.DONE_KEY, null))
		h.up("ui_left")
		return
	await h.burst("carry", 10, 6)
	await h.until(func(): return cut.step == "set", 4.0)
	await h.burst("set_down", 6, 4)
	await h.until(func(): return cut.step == "mend", 4.0)
	await h.wait(0.35)
	await h.shot("mend")
	await h.until(func(): return cut.step == "release", 4.0)
	await h.wait(0.5)
	await h.shot("coil_unwinds")
	await h.wait(0.6)
	await h.shot("arm_pulls_back")
	await h.until(func(): return cut.step == "dock", 4.0)
	h.check("the ship stands at the dome, set down live, clean and lit", ship.mode == "dome" and _Ship.is_landed() and not ship._scorched and ship._lights_on
		and _Ship.events.any(func(e): return e["what"] == "landed" and e["live"]), [ship.mode, ship._scorched, ship._lights_on])
	h.check("no coil left on the ship", ship.carrier.get_node_or_null("CutGripBack") == null or ship.carrier.get_node("CutGripBack").is_queued_for_deletion(), ship.carrier.get_children().map(func(c): return c.name))
	await h.wait(0.6)
	await h.shot("docked")
	# The beat, over the ship.
	var id: String = await h.read_beat("beat", 12.0)
	h.check("the beat plays over the docked ship: last_chain", id == Cut.BEAT_ID and cut.step in ["beat", "return"], [id, cut.step])
	h.check("frozen all through: the keeper (a key held) and its heat never changed", k.global_position.distance_to(k_at) < 0.5 and is_equal_approx(lava.heat_of(k), heat0) and GameWorld.paused, [k.global_position - k_at, lava.heat_of(k), heat0])
	h.check("the wave clock stopped", Data.ofOr("monsters.wavecooldown", null) == wave0, [wave0, Data.ofOr("monsters.wavecooldown", null)])
	h.check("the seal's opening waits (play is frozen)", seal == null or seal.mode in ["pending", "sealed"], seal.mode if seal != null else null)
	h.up("ui_left")
	await h.until(func(): return cut.step == "return", 4.0)
	await h.wait(cut._ret_s * 0.8)
	await h.shot("return")
	var done: bool = await h.until(func(): return cut.step == "done", 8.0)
	await h.wait(0.3)
	await h.shot("back_on_keeper")
	var cam = Level.viewports.getPlayerCam(k.playerId)
	h.check("the cutscene ends: play resumes, the camera is back on the keeper at its zoom", done and not GameWorld.paused and cam.global_position.distance_to(k.global_position + cam.targetOffset) < 40.0 and is_equal_approx(cam.zoom.x, float(cam.zoomStagePx)),
		[done, GameWorld.paused, cam.global_position - k.global_position, cam.zoom, cam.zoomStagePx])
	var order: Array = steps_seen.map(func(s): return s[0])
	h.check("every step, in order", order == ["hold", "rise", "crack", "burst", "carry", "set", "mend", "release", "dock", "beat", "return", "done"], steps_seen)
	h.check("done once, live: the signal, a waiter from before, the Data", finished == [true] and waited == [true] and float(Data.ofOr(_LastChain.DONE_KEY, -1.0)) > 0.0 and _LastChain.is_done(), [finished, waited, Data.ofOr(_LastChain.DONE_KEY, null)])
	var late: Array = []
	_LastChain.when_done(func(l): late.append(l))
	await h.frames(2)
	h.check("a waiter after it is told at once, not live", late == [false], late)
	h.check("with the game's sounds", int(Sfx.played.get("grow", 0)) >= 1 and int(Sfx.played.get("boom", 0)) >= 1 and int(Sfx.played.get("ship_land", 0)) == 1 and int(Sfx.played.get("burrow", 0)) >= 2, Sfx.played)
	h.note("cutscene length (frozen seconds)", {"total": cut.total, "steps": steps_seen, "rise_s": cut._rise_s, "return_s": cut._ret_s})
	await h.hold("ui_up", 1.0)
	await h.shot("play_resumed")
	h.check("the keeper moves again by real input", k.global_position.distance_to(k_at) > 2.0, k.global_position - k_at)
	# The seal opens when it is first seen now.
	if seal != null:
		var ch: Rect2i = Level.map.tileData.get_meta("story_boss_chamber")
		await h.teleport_tile(Vector2i(ch.position.x + ch.size.x / 2, ch.position.y - 3))
		var opened: bool = await h.until(func():
			cool(h)
			return seal.mode == "open", 12.0)
		h.check("the seal's opening plays once it is seen after the cutscene", opened and _LairSeal.events.any(func(e): return e["what"] == "opening"), _LairSeal.events)
		await h.shot("seal_opened_after")
	_check_at_dome(h, k)
	SaveGame.saveGame("singleplayer", AFTER_SLOT, true)
	await h.wait(1.5)
	h.note("saved slot %d" % AFTER_SLOT, {"state": _EndGame.state(), "done": Data.ofOr(_LastChain.DONE_KEY, null)})
