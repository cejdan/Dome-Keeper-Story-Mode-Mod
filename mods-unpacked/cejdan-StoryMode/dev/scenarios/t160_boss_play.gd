extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 160: the chamber fight played with real input by a simple bot, with
# every attack on and real hearts. The bot flies to a mining charge, picks it
# up, carries it to the nearest eye stalk (or the open great eye), drops it and
# backs off. It does not dodge, so it shows the worst case: how long the fight
# takes and what hits a careless player. Boot `--hearts=<n>` gives the bot
# extra hearts so the run reaches the later phases.

const Director = preload("res://mods-unpacked/cejdan-StoryMode/boss/boss_director.gd")
const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const TIMEOUT := 600

var _held: Dictionary = {}


func boot() -> Dictionary:
	return {"seed": 12345}


func _steer(h, dir: Vector2) -> void:
	var want: Dictionary = {"ui_left": dir.x < -0.3, "ui_right": dir.x > 0.3, "ui_up": dir.y < -0.3, "ui_down": dir.y > 0.3}
	for a: String in want:
		if want[a] and not _held.get(a, false):
			h.down(a)
		elif not want[a] and _held.get(a, false):
			h.up(a)
		_held[a] = want[a]


func run(h) -> void:
	h.disable_waves()
	var ch: Rect2i = Level.map.tileData.get_meta("story_boss_chamber")
	var area: Array = []
	for y in range(ch.position.y - 3, ch.end.y + 2):
		for x in range(ch.position.x - 2, ch.end.x + 2):
			area.append(Vector2i(x, y))
	await h.reveal(area)
	await h.teleport_tile(ch.position + Vector2i(3, 2))
	await h.until(func(): return Director.current() == "fight", 8.0)
	var boss = Director.instance()
	var velle = boss.velle
	var health = boss.health
	var extra: int = int(Story.user_arg("hearts", "0"))
	var causes: Dictionary = {}
	health.hurt_taken.connect(func(_left, cause): causes[cause] = int(causes.get(cause, 0)) + 1)
	var k = h.keeper()
	var t0: float = h.now()
	var next_shot: float = 6.0
	var phase_times: Dictionary = {}
	var carrying_since: float = -1.0
	while Director.current() == "fight" and h.now() - t0 < 420.0:
		await h.frames(2)
		if extra > 0 and health.hearts() <= 1:
			extra -= 1
			health.refill()
		var kp: Vector2 = velle.to_local(k.global_position)
		if not phase_times.has(velle.phase):
			phase_times[velle.phase] = snappedf(h.now() - t0, 0.1)
		var carried: Array = k.carriedCarryables.filter(func(c): return is_instance_valid(c) and c.get("type") == CONST.CAVEBOMB)
		if carried.is_empty() and not k.carriedCarryables.is_empty():
			await h.press("keeper1_drop")   # something else got picked up (a fallen gem)
		var goal: Vector2 = kp
		if carried.is_empty():
			carrying_since = -1.0
			# Fetch the nearest idle charge.
			var best = null
			for b in velle.bombs:
				if is_instance_valid(b) and not b.activated and (best == null or kp.distance_to(velle.to_local(b.global_position)) < kp.distance_to(velle.to_local(best.global_position))):
					best = b
			if best != null:
				goal = velle.to_local(best.global_position) + Vector2(0, -6)
				if kp.distance_to(goal) < 14.0:
					await h.press("keeper1_pickup")
			else:
				# Nothing to carry: hover high in the middle, away from the body.
				goal = Vector2(velle.arena.get_center().x + 90.0 * sin(h.now() * 0.7), velle.arena.position.y + 60.0)
		else:
			if carrying_since < 0.0:
				carrying_since = h.now()
			# Deliver: the open eye, else the nearest stalk.
			var target: Vector2 = velle.eye_pos() + Vector2(0, -40)
			if not velle.is_open():
				var bd: float = 1e9
				for s: Dictionary in velle.stalks:
					if s["alive"] and kp.distance_to(s["pos"]) < bd:
						bd = kp.distance_to(s["pos"])
						target = s["pos"] + (kp - s["pos"]).normalized() * 26.0
			goal = target
			if kp.distance_to(goal) < 12.0 or h.now() - carrying_since > 12.0:
				await h.press("keeper1_drop")
				# Back off while the fuse burns.
				var away: Vector2 = (kp - velle.eye_pos()).normalized()
				_steer(h, Vector2(away.x, -0.2))
				await h.wait(1.4)
		_steer(h, goal - kp if kp.distance_to(goal) > 6.0 else Vector2.ZERO)
		if h.now() - t0 > next_shot:
			next_shot += 14.0
			await h.shot("play_%03ds" % int(h.now() - t0))
	_steer(h, Vector2.ZERO)
	var took: float = snappedf(h.now() - t0, 0.1)
	h.note("fight result", {"state": Director.current(), "seconds": took, "phase_starts": phase_times, "hits_by_cause": causes,
		"hits": health.hits, "hearts": health.hearts(), "velle_hp": velle.hp if is_instance_valid(velle) else -1.0, "stats": velle.stats if is_instance_valid(velle) else {}})
	h.check("the bot hurt Velle with carried charges", velle.stats["core_hits"] >= 1 and velle.stats["stalks_popped"] >= 3, velle.stats)
	h.check("the fight ended (won or lost) inside 7 minutes", Director.current() != "fight", [Director.current(), took])
	await h.wait(3.0)
	await h.shot("after")
