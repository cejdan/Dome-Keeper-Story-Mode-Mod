extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 96 (review fix): a beat still waiting when Retire Rich is bought must
# not open over the doom ending. Sells a set of miner bones (its log waits out
# the sale pop's hold), opens the shop at once and buys Retire Rich. Only the
# horror's thanks may open; the miner's log stays queued through the last
# words, the narration cards and the end screen.

const TIMEOUT := 200

const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")


func boot() -> Dictionary:
	return {"seed": 12345, "beats": true}


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	var ed = Level.mode.get_node_or_null("StoryEndings")
	h.check("the ending director is in the run", ed != null)
	# The bones' log is queued with a hold, as a sale does (drops/BonesDrop.gd).
	h.check("the miner's log is queued", StoryBeats.fire("log_b1"))
	StoryBeats.hold(2.0)
	h.set_inv("money", 1000000)
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.0)
	var ok: bool = await h.buy("storyretirerich")
	h.check("Retire Rich bought", ok)
	var id: String = await h.read_beat("thanks", 8.0, false)
	h.check("the first beat is the horror's thanks", id == "doom_thanks", id)
	# Through the rest of the ending, nothing else opens.
	var opened: Array = []
	var t_end: float = h.now() + 60.0
	while h.now() < t_end and Level.stage.endingPanel == null:
		if StoryBeats.is_open() and not opened.has(StoryBeats.instance().open_id):
			opened.append(StoryBeats.instance().open_id)
			await h.shot("beat_over_ending")
		await h.wait(0.2)
	await h.wait(2.0)
	await h.shot("end_screen")
	h.check("no beat opened during the ending", opened.is_empty(), opened)
	h.check("the end screen showed", Level.stage.endingPanel != null)
	h.check("the miner's log never played", not StoryBeats.has_played("log_b1"))
