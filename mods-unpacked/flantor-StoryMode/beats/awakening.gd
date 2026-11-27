extends RefCounted

# The awakening (#95): how far the horror has woken. Each chain broken in the
# lava ocean (the chain anchors, #365, map/chain_anchors.gd) weakens the seal;
# breaking into the boss chamber wakes it fully. Read from the end-game state
# (endgame/end_game.gd), saved with the run in Data:
#   Awakening.chains()     chains broken so far, 0..10
#   Awakening.level()      0.0 asleep .. 1.0 awake
#   Awakening.is_awake()   the boss chamber has been entered
# Beats: "chain:<n>" as each chain breaks (fired by EndGame.record_break;
# data/beats.gd has no beat on them today, as the user cut the old
# "unobtainium:<n>" seal beats in #285), then "boss_chamber" on entering the
# chamber; when it closes the fight starts (boss/boss_director.gd, #160).
# Before #365 the seal counted unobtainium pieces mined (Data
# team1.story.unobmined / unobcells); those keys are dropped on load.

const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
static var _StoryBeats = StoryBeats  # calls go through this: lazy_preload makes const-preload calls slow
const EndGame = preload("res://mods-unpacked/flantor-StoryMode/endgame/end_game.gd")
static var _EndGame = EndGame  # calls go through this: lazy_preload makes const-preload calls slow

const AWAKE := "team1.story.awake"
# The seal is this much weaker per chain broken; the chamber does the rest.
const PER_CHAIN := 0.08
const SEAL_MAX := 0.8


static func chains() -> int:
	return _EndGame.chains_broken()


static func is_awake() -> bool:
	return bool(Data.ofOr(AWAKE, false))


static func level() -> float:
	if is_awake():
		return 1.0
	return minf(SEAL_MAX, chains() * PER_CHAIN)


# The keeper broke into the boss chamber.
static func wake() -> void:
	if is_awake():
		return
	Data.apply(AWAKE, true)
	ModLoaderLog.info("Awakening: the horror is awake", "flantor-StoryMode")
	_StoryBeats.trigger("boss_chamber")
