extends RefCounted

# The awakening (#95): how far the horror has woken. Each unobtainium tile
# mined (the moment it breaks) weakens the seal; breaking into the boss chamber
# wakes it fully. Saved with the run in Data, readable by anything:
#   Awakening.mined()      unobtainium tiles broken so far
#   Awakening.level()      0.0 asleep .. 1.0 awake
#   Awakening.is_awake()   the boss chamber has been entered
#   Awakening.freed(cell)  whether the deposit cell was mined (chains, #101)
# Beats: "unobtainium:<n>" after the 1st, 3rd, 5th, 7th and 10th (data/beats.gd),
# then "boss_chamber" on entering the chamber; when it closes the fight starts
# (boss/boss_director.gd, #160).

const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")

const MINED := "team1.story.unobmined"
const CELLS := "team1.story.unobcells"
const AWAKE := "team1.story.awake"
# The seal is this much weaker per unobtainium; the chamber does the rest.
const PER_PIECE := 0.08
const SEAL_MAX := 0.8


static func mined() -> int:
	return int(Data.ofOr(MINED, 0))


static func is_awake() -> bool:
	return bool(Data.ofOr(AWAKE, false))


static func level() -> float:
	if is_awake():
		return 1.0
	return minf(SEAL_MAX, mined() * PER_PIECE)


static func freed(cell: Vector2i) -> bool:
	return str(Data.ofOr(CELLS, "")).split(";", false).has("%d,%d" % [cell.x, cell.y])


# An unobtainium tile at `cell` just broke.
static func unobtainium_mined(cell: Vector2i) -> void:
	var n: int = mined() + 1
	Data.apply(MINED, n)
	var cells: String = str(Data.ofOr(CELLS, ""))
	Data.apply(CELLS, cells + "%d,%d;" % [cell.x, cell.y])
	ModLoaderLog.info("Awakening: unobtainium %d mined at %s, seal at %.2f" % [n, cell, level()], "cejdan-StoryMode")
	StoryBeats.trigger("unobtainium:%d" % n)


# The keeper broke into the boss chamber.
static func wake() -> void:
	if is_awake():
		return
	Data.apply(AWAKE, true)
	ModLoaderLog.info("Awakening: the horror is awake", "cejdan-StoryMode")
	StoryBeats.trigger("boss_chamber")
