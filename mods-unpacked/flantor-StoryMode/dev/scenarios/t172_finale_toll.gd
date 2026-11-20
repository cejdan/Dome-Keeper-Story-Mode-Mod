extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 172: the finale's bell intro and the first cracking keep time. Starts
# the finale and, frame by frame, logs each bell toll the ground answers
# against the music's own clock, with a screenshot of each; checks the cracks
# open further with every toll, and that round 1 breaks out as the battle loop
# starts (its first beat), with a frame burst of the breakout.

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const Boss = preload("res://mods-unpacked/flantor-StoryMode/data/boss.gd")
const TIMEOUT := 120


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	await h.wait(1.0)
	var boss = _Director.instance()
	boss._ensure_layer()
	load("res://mods-unpacked/flantor-StoryMode/dev/boss_dev.gd").give_gear()
	await h.frames(5)
	boss._stop_waves()
	boss._set_state("finale")
	boss._start_finale()
	var started: bool = await h.until(func(): return _Director.current() == "finale", 5.0)
	h.check("the finale starts", started, _Director.current())
	if not started:
		return
	var fin = boss.finale
	var m = boss.music
	var b0: float = h.now()
	await h.until(func(): return m.intro_time() >= 0.0, Boss.FINALE_BREATH + 4.0)
	h.check("the bell intro plays, after a breath of %.0f s with the keeper idle" % Boss.FINALE_BREATH,
		m.intro_time() >= 0.0 and fin.bells_by == "idle" and h.now() - b0 >= Boss.FINALE_BREATH - 0.2, [snappedf(h.now() - b0, 0.01), fin.bells_by, m.playing()])
	var tolls: Array = []
	var seen: int = -1
	var t0: float = h.now()
	while fin.step == "rumble" and h.now() - t0 < 15.0:
		var at: float = m.intro_time()
		if fin._toll_k > seen:
			seen = fin._toll_k
			var want: float = float(Boss.FINALE_TOLLS[seen]) * Boss.FINALE_BEAT
			tolls.append({"toll": seen, "music s": snappedf(at, 0.001), "bell s": snappedf(want, 0.001), "late s": snappedf(at - want, 0.001)})
			await h.wait(0.25)
			tolls[-1]["cracks open"] = snappedf(fin._toll_grow, 0.01)
			await h.shot("toll_%d" % seen)
		await h.frames(1)
		if not fin._toll_roll:
			continue
		if not tolls.is_empty() and not tolls[-1].has("roll"):
			tolls.append({"roll": snappedf(m.intro_time(), 0.001)})
			await h.shot("roll")
	h.note("tolls", tolls)
	var rung: Array = tolls.filter(func(e): return e.has("toll"))
	h.check("the ground answers all %d tolls" % Boss.FINALE_TOLLS.size(), rung.size() == Boss.FINALE_TOLLS.size(), rung.size())
	h.check("each within a frame or two of its bell (0.06 s)", rung.all(func(e): return absf(float(e["late s"])) <= 0.06), rung.map(func(e): return e["late s"]))
	var opening: bool = true
	for i in range(1, rung.size()):
		opening = opening and float(rung[i]["cracks open"]) > float(rung[i - 1]["cracks open"])
	h.check("the cracks open further with each toll", opening, rung.map(func(e): return e["cracks open"]))
	# The drop.
	await h.until(func(): return fin.step == "round1", 5.0)
	var loop_pos: Array = m.cues["finale"].map(func(p): return snappedf(p.get_playback_position(), 0.001))
	h.note("at the breakout", {"seconds since the intro began": snappedf(h.now() - t0, 0.01), "loop positions": loop_pos, "playing": m.playing()})
	h.check("round 1 breaks out as the loop starts (within 0.1 s of its first beat)", fin.step == "round1" and loop_pos.all(func(p): return p <= 0.1), loop_pos)
	await h.burst("breakout", 10, 3)
	await h.wait(1.0)
	await h.shot("round1")
	h.check("two tentacles are up", fin.living() == 2, fin.living())
