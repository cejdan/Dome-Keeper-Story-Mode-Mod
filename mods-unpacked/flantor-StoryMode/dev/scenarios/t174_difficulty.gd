extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 174: the chamber fight scales with difficulty, nobody talks during
# the boss sequence, and Velle's death hands hearts back by difficulty.
#
#   --tier=<-2|-1|0|2>   the run's difficulty: easy, normal (default), brutal,
#                        You Asked For It
#
# Starts the fight at that difficulty and counts what Velle actually does in
# each phase (stalks grown, lasers on screen at once for the grid, the open
# eye's volleys) against data/boss.gd. Checks that a waiting story beat and a
# plea stay shut during the fight, then kills Velle with one heart left and
# counts the hearts handed back.

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
const Boss = preload("res://mods-unpacked/flantor-StoryMode/data/boss.gd")
const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
const TIMEOUT := 300


func difficulty() -> int:
	return int(Story.user_arg("tier", "-1"))


func boot() -> Dictionary:
	return {"seed": 12345, "difficulty": difficulty()}


func _rays(velle) -> int:
	return velle.attacks.filter(func(a): return a["kind"] == "ray").size()


func _sweeps(velle) -> int:
	return velle.attacks.filter(func(a): return a["kind"] == "sweep").size()


func run(h) -> void:
	h.disable_waves()
	var tier: int = Boss.tier()
	h.note("difficulty", {"level": Level.difficulty("team1"), "tier": Boss.TIER_NAMES[tier]})
	h.check("the run is on the asked difficulty", Level.difficulty("team1") == difficulty() and tier == Boss.TIER_BY_DIFFICULTY[difficulty()], [Level.difficulty("team1"), tier])
	var ch: Rect2i = Level.map.tileData.get_meta("story_boss_chamber")
	var area: Array = []
	for y in range(ch.position.y - 3, ch.end.y + 2):
		for x in range(ch.position.x - 2, ch.end.x + 2):
			area.append(Vector2i(x, y))
	await h.reveal(area)
	await h.teleport_tile(ch.position + Vector2i(3, 2))
	var started: bool = await h.until(func(): return Director.current() == "fight", 8.0)
	h.check("the fight starts", started, Director.current())
	if not started:
		return
	var boss = Director.instance()
	var velle = boss.velle
	var health = boss.health
	velle.attack_enabled = false
	velle.spawn_bombs = false
	await h.until(func(): return velle.state == "fight", 8.0)
	await h.wait(1.0)
	health.invulnerable = 9999.0
	var kp: Vector2 = velle.to_local(h.keeper().global_position)

	# ---- nobody talks during the boss sequence
	var beats = StoryBeats.instance()
	h.check("a story beat cannot open during the fight", Story.boss_active() and not beats._can_show())
	var pleas = load("res://mods-unpacked/flantor-StoryMode/pleas/plea_director.gd").instance()
	var n0: int = pleas.shown.size()
	Data.apply("team1.monsters.wavepresent", true)
	await h.wait(0.5)
	var line: String = pleas.say("fight")
	Data.apply("team1.monsters.wavepresent", false)
	h.check("the monsters' pleas are off: not when a wave arrives, not when asked", line == "" and pleas.shown.size() == n0, [line, pleas.shown.size() - n0])
	await h.shot("fight_no_text")

	# ---- each phase, as this difficulty plays it
	var seen: Dictionary = {}
	for p in 3:
		velle.phase = p
		velle.attacks.clear()
		for s: Dictionary in velle.stalks:
			s["alive"] = false
		velle.stalks.clear()
		velle._grow_stalks()
		var stalks: int = velle.alive_stalks()
		velle._volley = 0
		velle._open_volley(kp)
		var beams: int = _rays(velle)
		velle.attacks.clear()
		velle._open_volley(kp)
		var second: String = "%d walls of light" % _sweeps(velle) if _sweeps(velle) > 0 else "%d beams" % _rays(velle)
		var walls: int = _sweeps(velle)
		velle.attacks.clear()
		seen[p] = {"stalks": stalks, "beams": beams, "then": second}
		h.check("phase %d: %d stalks, %d gaze beams in a volley" % [p + 1, Boss.stalks(p), Boss.open_beams(p)], stalks == Boss.stalks(p) and beams == Boss.open_beams(p), seen[p])
		if p == 2:
			h.check("phase 3's walls of light: %s" % ("two, closing" if Boss.T_JAWS[tier] else "one"), walls == (2 if Boss.T_JAWS[tier] else 1), walls)
			velle.start_attack("grid", kp)
			var grid: int = _rays(velle)
			await h.wait(1.1)
			await h.shot("phase3_grid")
			h.check("phase 3's grid is %d lasers at once" % Boss.T_GRID_RAYS[tier], grid == Boss.T_GRID_RAYS[tier], grid)
			velle.attacks.clear()
			velle.start_attack("lunge", kp)
			var lunges: int = velle.attacks.filter(func(a): return a["kind"] == "strike").size()
			h.check("phase 3's lunges come %s" % ("in pairs" if Boss.T_DOUBLE_LUNGE[tier] else "one at a time"), lunges == (2 if Boss.T_DOUBLE_LUNGE[tier] else 1), lunges)
			velle.attacks.clear()
	h.note("what Velle does on " + Boss.TIER_NAMES[tier], seen)
	h.note("timing", {"attack every": Boss.T_ATTACK_EVERY[tier], "stalk fire every": Boss.T_STALK_FIRE_EVERY[tier], "stalk laser share": Boss.T_STALK_LASER_SHARE[tier]})
	if tier <= 1:
		h.check("normal and below: phases 1 and 2 as on brutal, phase 3 thinner", Boss.T_STALKS[tier][0] == Boss.STALKS[0] and Boss.T_STALKS[tier][1] == Boss.STALKS[1]
			and Boss.T_OPEN_BEAMS[tier][2] < Boss.T_OPEN_BEAMS[2][2] and Boss.T_GRID_RAYS[tier] < Boss.T_GRID_RAYS[2] and Boss.T_STALK_LASER_SHARE[tier][2] < Boss.STALK_LASER_SHARE[2])
	elif tier == 3:
		h.check("You Asked For It: phases 1 and 2 are harder than brutal", Boss.T_STALKS[3][0] > Boss.STALKS[0] and Boss.T_STALKS[3][1] > Boss.STALKS[1]
			and Boss.T_ATTACK_EVERY[3][0] < Boss.ATTACK_EVERY[0] and Boss.T_ATTACK_EVERY[3][1] < Boss.ATTACK_EVERY[1])

	# ---- Velle dies: hearts back, by difficulty
	Data.apply("team1.story.hearts", 1)
	velle._damage_core(9999.0)
	var chased: bool = await h.until(func(): return Director.current() == "chase", 15.0)
	await h.frames(5)
	var want: int = mini(Boss.HEARTS, 1 + Boss.hearts_after_velle())
	await h.shot("hearts_after_velle")
	h.check("Velle's death hands back %d hearts on %s (1 -> %d)" % [Boss.hearts_after_velle(), Boss.TIER_NAMES[tier], want], chased and health.hearts() == want, health.hearts())
	h.check("still no text in the chase", Story.boss_active() and not beats._can_show() and pleas.say("arrive") == "")
