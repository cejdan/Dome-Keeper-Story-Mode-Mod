extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 136: selling miner bones pops "+$X" over the dome first; the miner's
# log opens only once that pop has been readable for a moment. Also sold with a
# batch of iron, so the bones' pop waits in line behind the iron pops.

const Bones = preload("res://mods-unpacked/cejdan-StoryMode/data/bones.gd")
const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const SalePops = preload("res://mods-unpacked/cejdan-StoryMode/hud/sale_pops.gd")


func boot() -> Dictionary:
	return {"seed": 12345, "beats": true}


func _sell(h, b: int, iron: int) -> void:
	var dome = Level.getDome("team1")
	var target: Vector2 = dome.getDropTarget("iron").global_position + Vector2(0, -8)
	var pops = SalePops.instance()
	var shown0: int = pops.shown.size()
	var m0: int = int(h.inv("money"))
	for i in iron:
		Level.drops.network_spawn({"type": "iron", "position": target + Vector2(randf_range(-4, 4), -4), "impulse": Vector2.ZERO})
	var drop = Level.drops.network_spawn({"type": Bones.TYPE, "position": target + Vector2(0, -12), "impulse": Vector2.ZERO})
	drop.value = Bones.value_for(b)
	drop.biome = b
	var log_id: String = "log_b%d" % (b + 1)
	await h.until(func(): return int(h.inv("money")) >= m0 + drop.value, 10.0)
	var sold_t: float = h.now()
	# Frames across the sale: the bones' pop, then the log.
	await h.burst("b%d_sale" % (b + 1), 10, 6)
	await h.until(func(): return StoryBeats.instance().open_id == log_id, 8.0)
	var open_t: float = h.now()
	var bones_pop_t: float = -1.0
	for p in pops.shown.slice(shown0):
		if int(p["amount"]) == drop.value:
			bones_pop_t = float(p["t"])
	var pops_t0: float = pops._time
	h.note("b%d timing" % (b + 1), {"sold": sold_t, "log_open": open_t, "bones_pop_shown_at_pops_clock": bones_pop_t, "pops_clock_now": pops_t0})
	# The pops' own clock: how long the bones' pop had been up when the log opened.
	var up_for: float = pops_t0 - bones_pop_t if bones_pop_t >= 0.0 else -1.0
	h.check("B%d (+%d iron): the bones' pop shows before the log" % [b + 1, iron], bones_pop_t >= 0.0, pops.shown.slice(shown0))
	h.check("B%d (+%d iron): the pop is up for about a second before the log opens (%.2f s)" % [b + 1, iron, up_for], up_for >= 0.9 and up_for <= 1.6, up_for)
	await h.shot("b%d_log_open" % (b + 1))
	await h.read_beat(log_id, 3.0, false)


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	Data.apply("team1.story.beatsplayed", "biome_b2,biome_b3,biome_b4,biome_b5,biome_b6,biome_b7,biome_b8,lava_ocean,first_gem,gate_broken,lava_death")
	await h.wait(0.5)
	await _sell(h, 0, 0)
	await h.wait(1.0)
	await _sell(h, 3, 8)
