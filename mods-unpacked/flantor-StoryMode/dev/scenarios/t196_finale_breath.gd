extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 196: the finale draws a breath of silence until the keeper takes the
# dome's weapon. The keeper sits at the console and opens the shop: the
# bells wait however long the shop stays open. Back out of it and pick
# Battle: the bells start at once. Then the game is paused mid-intro (the
# console's menu would do that): the music holds, and every toll still lands
# on its crack.
#
# t196_finale_console: idle in the console's menu instead, which holds the
# bells until Battle.


const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
const Boss = preload("res://mods-unpacked/flantor-StoryMode/data/boss.gd")
const TIMEOUT := 120


func boot() -> Dictionary:
	return {"seed": 12345}


func _station(node: Node):
	for c in node.get_children():
		if c is DomeStation:
			return c
		var s = _station(c)
		if s != null:
			return s
	return null


func start(h):
	h.disable_waves()
	await h.wait(1.0)
	var boss = Director.instance()
	boss._ensure_layer()
	load("res://mods-unpacked/flantor-StoryMode/dev/boss_dev.gd").give_gear()
	await h.frames(5)
	boss._stop_waves()
	boss._set_state("finale")
	boss._start_finale()
	await h.until(func(): return Director.current() == "finale", 5.0)
	return boss


func run(h) -> void:
	var boss = await start(h)
	var fin = boss.finale
	var m = boss.music
	var k = h.keeper()
	var st = _station(Level.getDome("team1"))
	h.check("the finale opens with a breath of silence", fin.step == "breath" and m.intro_time() < 0.0 and m.playing().is_empty(), [fin.step, m.playing()])
	h.check("no wave-start gong in the breath", not Audio.soundPlayers.any(func(p): return p.playing and p.stream == Audio.wavestart))
	var loud: AudioStreamWAV = load("res://content/sounds/UI/Alarm.wav")
	var peak = func(s: AudioStreamWAV) -> int:
		var d: PackedByteArray = s.data
		var mx: int = 0
		for i in range(0, d.size() - 1, 2):
			mx = maxi(mx, absi(d.decode_s16(i)))
		return mx
	var drop: float = linear_to_db(float(peak.call(Audio.alarm)) / float(maxi(1, peak.call(loud))))
	h.check("the blinking alarm is turned down %.0f dB" % -Boss.FINALE_ALARM_DB, Audio.alarm != loud and absf(drop - Boss.FINALE_ALARM_DB) < 0.5, snappedf(drop, 0.1))

	# ---- the shop holds the bells off
	st.useHit(k)
	await h.until(func(): return fin.activity() == "console", 3.0)
	h.check("at the console: its menu", fin.activity() == "console" and GameWorld.paused, fin.activity())
	await h.press("dome_upgrades")
	await h.until(func(): return fin.activity() == "", 3.0)
	await h.wait(0.5)
	await h.shot("in_the_shop")
	await h.wait(Boss.FINALE_BREATH + 3.0)
	h.check("the shop holds the bells off (%.0f s in it)" % (Boss.FINALE_BREATH + 3.5), fin.step == "breath" and m.intro_time() < 0.0, [fin.step, fin.activity()])

	# ---- out of the shop, Battle: the bells at once
	await h.press("ui_cancel")
	await h.wait(0.4)
	var back: String = fin.activity()
	h.note("out of the shop", back)
	if back == "keeper":
		st.useHit(k)
		await h.until(func(): return fin.activity() == "console", 3.0)
	h.check("still the breath, back from the shop", fin.step == "breath", [fin.step, fin.activity()])
	var b0: float = h.now()
	await h.press("dome_battle")
	await h.until(func(): return fin.step == "rumble", 2.0)
	h.check("Battle starts the bells at once", fin.step == "rumble" and fin.bells_by == "battle" and h.now() - b0 < 0.5, [fin.step, fin.bells_by, snappedf(h.now() - b0, 0.01)])
	h.check("at the weapon, the world running", fin.activity() == "battle" and not GameWorld.paused and k.isInsideStation, [fin.activity(), GameWorld.paused])
	await h.until(func(): return m.intro_time() >= 0.0, 2.0)
	h.check("the bell intro plays", m.intro_time() >= 0.0, m.playing())

	# ---- a pause mid-intro: the music holds, the cracks keep time
	var tolls: Array = []
	var seen: int = -1
	var paused_once: bool = false
	var t0: float = h.now()
	while fin.step == "rumble" and h.now() - t0 < 25.0:
		if fin._toll_k > seen:
			seen = fin._toll_k
			var at: float = m.intro_time()
			tolls.append(snappedf(at - float(Boss.FINALE_TOLLS[seen]) * Boss.FINALE_BEAT, 0.001))
			if seen == 2 and not paused_once:
				paused_once = true
				await h.wait(0.3)
				Level.stage.pause()
				await h.frames(3)
				var held: float = m.intro_time()
				await h.wait(2.0)
				h.check("paused mid-intro, the music holds", GameWorld.paused and absf(m.intro_time() - held) < 0.02 and m.intro.stream_paused, [held, m.intro_time()])
				h.check("and so does the cracking", fin._toll_k == 2, fin._toll_k)
				Level.stage.unpause()
		await h.frames(1)
	h.note("toll lateness (s)", tolls)
	h.check("every toll still lands on its crack (within 0.06 s)", tolls.size() == Boss.FINALE_TOLLS.size() and tolls.all(func(x): return absf(x) <= 0.06), tolls)
	await h.until(func(): return fin.step == "round1", 5.0)
	var loop_pos: Array = m.cues["finale"].map(func(p): return snappedf(p.get_playback_position(), 0.001))
	h.check("round 1 breaks out on the drop", fin.step == "round1" and loop_pos.all(func(p): return p <= 0.1), loop_pos)
	await h.wait(1.0)
	await h.shot("round1")
