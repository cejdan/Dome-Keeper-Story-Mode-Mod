extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 171: the surface finale played for real. A bot sits in the dome's
# weapon station and works the laser with real input (left, right, fire): it
# swings to the target nearest its aim, fires when lined up, and goes for the
# great eye while it charges its gaze. It plays the whole battle and reports
# who won, how long it took and how much dome was left.
#
#   --laser=<0..4>   the laser's strength upgrades (default 4, Laser IV)
#   --expect=win|fall|lose|any   what the run must end in (default any):
#                    fall = the dome falls; lose = it falls before round 3
#
# t171_finale_laser4, t171_finale_laser3 and t171_finale_base are this
# scenario with the results the fight is tuned for: Laser IV wins, Laser III
# falls (playtest 2026-11-15: the user wants it that hard), a base laser falls
# early.

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
const Boss = preload("res://mods-unpacked/flantor-StoryMode/data/boss.gd")
const Dev = preload("res://mods-unpacked/flantor-StoryMode/dev/boss_dev.gd")
const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
const TIMEOUT := 600

var _held: Dictionary = {}


func boot() -> Dictionary:
	return {"seed": 12345}


func laser_level() -> int:
	return int(Story.user_arg("laser", "4"))


func expect() -> String:
	return Story.user_arg("expect", "any")


func _station(node: Node):
	for c in node.get_children():
		if c is DomeStation:
			return c
		var s = _station(c)
		if s != null:
			return s
	return null


func _hold(h, action: String, on: bool, force: bool = false) -> void:
	if on and (force or not _held.get(action, false)):
		if force:
			h.up(action)
		h.down(action)
	elif not on and _held.get(action, false):
		h.up(action)
	_held[action] = on


func _aim_point(m) -> Vector2:
	var box = m.get_node_or_null("HitboxDefault")
	return m.to_global(box.position) if box != null else m.global_position


func run(h) -> void:
	h.disable_waves()
	await h.wait(1.0)
	var boss = Director.instance()
	var dome = Level.getDome("team1")
	var k = h.keeper()
	boss._ensure_layer()
	var level: int = laser_level()
	var gear: Array = Dev.give_gear([], level)
	if level >= 4 and not gear.has("laserstrength4") and not GameWorld.boughtUpgrades.has("laserstrength4"):
		GameWorld.serverAddUpgrade("laserstrength4", "team1")
	await h.frames(5)
	h.note("gear", {"laser level": level, "laser dps": Data.of("team1.laser.dps"), "dome health": Data.of("team1.dome.maxhealth"), "given": gear})
	boss._stop_waves()
	boss._set_state("finale")
	boss._start_finale()
	var fin = boss.finale
	var st = _station(dome)
	var t0: float = h.now()
	# Take the laser once the first round breaks out (before a battle the
	# station opens the dome's menu instead, which pauses the game).
	await h.until(func(): return fin.step == "round1", 20.0)
	st.useHit(k)
	# The station opens its menu (Battle / Upgrades / Exit) and pauses: pick
	# Battle, which is "left".
	for i in 12:
		await h.wait(0.5)
		if not GameWorld.paused and k.isInsideStation and i > 0:
			break
		await h.press("ui_left")
	await h.wait(0.5)
	var weapons: Array = st.getControlledWeapons()
	h.check("the keeper is at the laser", k.isInsideStation and weapons.size() >= 1, weapons.size())
	if weapons.is_empty():
		return
	var gun = weapons[0]
	var round_at: Dictionary = {}
	var next_shot: float = 3.0
	var hp_max: float = float(Data.of("team1.dome.maxhealth"))
	var low: float = hp_max
	var great = null
	while h.now() - t0 < 300.0 and not GameWorld.paused:
		await h.frames(2)
		if GameWorld.lost or Director.current() == "lost" or fin.step in ["allies", "thanks", "done"]:
			break
		if not round_at.has(fin.step):
			round_at[fin.step] = snappedf(h.now() - t0, 0.1)
		low = minf(low, float(Data.of("team1.dome.health")))
		var origin: Vector2 = gun.global_position
		var aim: Vector2 = Vector2.UP.rotated(gun.global_rotation)
		var best = null
		var best_a: float = 99.0
		for m in fin.alive:
			if not is_instance_valid(m) or m.dead or m.invulnerable:
				continue
			if m.get("great") == true:
				great = m
			var a: float = aim.angle_to(_aim_point(m) - origin)
			# The gaze must be broken: the charging eye comes first.
			if m.get("great") == true and m.gaze_t >= 0.0 and m.gaze_t < Boss.FINALE_GAZE_CHARGE:
				best = m
				best_a = a
				break
			if absf(a) < absf(best_a):
				best = m
				best_a = a
		var early: bool = h.now() - t0 < 4.0 and int((h.now() - t0) * 2.0) != int((h.now() - t0 - 0.034) * 2.0)
		if best == null:
			_hold(h, "ui_left", false)
			_hold(h, "ui_right", false)
			_hold(h, "dome1_fire", false)
		else:
			var off: float = absf(best_a) * origin.distance_to(_aim_point(best))   # px off target
			_hold(h, "ui_right", best_a > 0.0 and off > 4.0, early)
			_hold(h, "ui_left", best_a < 0.0 and off > 4.0, early)
			_hold(h, "dome1_fire", off < 14.0, early)
		if h.now() - t0 > next_shot:
			next_shot += 12.0
			await h.shot("battle_%03ds" % int(h.now() - t0))
	for a: String in ["ui_left", "ui_right", "dome1_fire"]:
		_hold(h, a, false)
	var took: float = snappedf(h.now() - t0, 0.1)
	var won: bool = fin.step in ["allies", "thanks", "done"]
	var lost: bool = GameWorld.lost or Director.current() == "lost"
	await h.wait(1.0)
	await h.shot("end")
	var report: Dictionary = {"laser level": level, "laser dps": Data.of("team1.laser.dps"), "result": "won" if won else ("lost" if lost else "unfinished"),
		"seconds": took, "step": fin.step, "steps at": round_at, "dome health left": snappedf(float(Data.of("team1.dome.health")), 1.0), "dome health max": hp_max,
		"lowest dome health": snappedf(low, 1.0), "fury": snappedf(fin.fury, 0.01), "flyers": fin.flyers_made,
		"gazes fired": great.gazes_fired if is_instance_valid(great) else -1, "gazes broken": great.gazes_broken if is_instance_valid(great) else -1}
	h.note("battle", report)
	match expect():
		"win":
			h.check("Laser level %d wins the final battle" % level, won, report)
			h.check("with a real margin: at least a fifth of the dome left", won and float(Data.of("team1.dome.health")) >= hp_max * 0.2, report)
		"fall":
			h.check("Laser level %d cannot win the final battle: the dome falls" % level, lost and not won, report)
		"lose":
			h.check("Laser level %d cannot win the final battle: the dome falls" % level, lost and not won, report)
			h.check("and it is not close: it never reaches the last round", not round_at.has("round3"), report)
		_:
			h.check("the battle ends, won or lost", won or lost, report)
