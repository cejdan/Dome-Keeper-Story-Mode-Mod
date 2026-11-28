extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 96 (review fix): a beat still waiting when the doom ending starts (the
# ship's escape since #368) must not open over it. Sells a set of miner bones
# (its log waits out the sale pop's hold) and boards the ship at once. Only the
# horror's thanks may open; the miner's log stays queued through the last
# words, the narration cards and the end screen.

const TIMEOUT := 200

const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
static var _StoryBeats = StoryBeats  # calls go through this: lazy_preload makes const-preload calls slow


func boot() -> Dictionary:
	return {"seed": 12345, "beats": true, "free": true}


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	var ed = Level.mode.get_node_or_null("StoryEndings")
	h.check("the ending director is in the run", ed != null)
	# The bones' log is queued with a hold, as a sale does (drops/BonesDrop.gd).
	h.check("the miner's log is queued", _StoryBeats.fire("log_b1"))
	_StoryBeats.hold(2.0)
	var Ship = load("res://mods-unpacked/flantor-StoryMode/endgame/ship.gd")
	await h.until(func(): return Ship.is_landed(), 10.0)
	var ok: bool = Level.mode.board_ship(h.keeper().playerId)
	h.check("the keeper boards the ship (the escape)", ok)
	var id: String = await h.read_beat("thanks", 16.0, false)
	h.check("the first beat is the horror's thanks", id == "doom_thanks", id)
	# Through the rest of the ending, nothing else opens.
	var opened: Array = []
	var t_end: float = h.now() + 60.0
	while h.now() < t_end and Level.stage.endingPanel == null:
		if _StoryBeats.is_open() and not opened.has(_StoryBeats.instance().open_id):
			opened.append(_StoryBeats.instance().open_id)
			await h.shot("beat_over_ending")
		await h.wait(0.2)
	await h.wait(2.0)
	await h.shot("end_screen")
	h.check("no beat opened during the ending", opened.is_empty(), opened)
	h.check("the end screen showed", Level.stage.endingPanel != null)
	h.check("the miner's log never played", not _StoryBeats.has_played("log_b1"))
