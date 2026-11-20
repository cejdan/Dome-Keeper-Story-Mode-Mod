extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 169: the chamber fight's second pass. The great eye stays open until
# the phase ends (no timer) and fights back faster the longer it is open;
# charges fall when stalks pop and when the eye opens, and one that drops out
# through a hole in the floor comes back from the roof; each phase adds
# lasers (stalk lasers, wall eyes firing a cross and a grid, walls of light
# from the open eye); a new phase shakes a heart loose.

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
const Boss = preload("res://mods-unpacked/flantor-StoryMode/data/boss.gd")
const TIMEOUT := 420


func boot() -> Dictionary:
	return {"seed": 12345}


func _pop_all(h, velle) -> void:
	for s: Dictionary in velle.stalks.duplicate():
		if s["alive"]:
			Director.explosion_at(velle.to_global(s["pos"]), "bomb")
			await h.wait(0.3)


func _put(h, velle, p: Vector2) -> void:
	h.keeper().global_position = velle.to_global(p)
	await h.frames(2)


func run(h) -> void:
	h.disable_waves()
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
	var arena: Rect2 = velle.arena
	velle.attack_enabled = false
	await h.until(func(): return velle.state == "fight", 8.0)
	await h.wait(1.5)
	health.invulnerable = 9999.0

	# ---- a popped stalk shakes a charge loose
	velle._bomb_t = 99.0
	var b0: int = velle.stats["bombs_spawned"]
	Director.explosion_at(velle.to_global(velle.stalks[0]["pos"]), "bomb")
	await h.wait(0.4)
	h.check("popping a stalk shakes a charge loose", velle.stats["bombs_spawned"] == b0 + 1, velle.stats)

	# ---- the eye opens: charges fall beside it, and it stays open
	b0 = velle.stats["bombs_spawned"]
	await _pop_all(h, velle)
	var opened: bool = await h.until(func(): return velle.is_open(), 6.0)
	h.check("with every stalk popped the great eye opens", opened, velle.state)
	h.check("%d charges fall at once when it opens" % Boss.BOMBS_ON_OPEN, velle.stats["bombs_spawned"] >= b0 + Boss.BOMBS_ON_OPEN + Boss.STALKS[0] - 1, [b0, velle.stats["bombs_spawned"]])
	await h.wait(1.0)
	await h.shot("eye_open_charges_falling")
	velle.spawn_bombs = false
	await h.wait(16.0)
	await h.shot("still_open_after_17s")
	h.check("17 seconds later the eye is still open (no timer)", velle.is_open(), [velle.state, velle.stats["open_seconds"]])

	# ---- the open eye fights back, faster the longer it is open
	await _put(h, velle, arena.position + Vector2(90, 70))
	velle.attack_enabled = true
	var r0: int = velle.stats["rays"]
	velle._open_atk_t = 0.0
	await h.wait(0.6)
	await h.shot("gaze_aiming")
	await h.wait(0.9)
	await h.burst("gaze_fires", 3, 5)
	h.check("an open eye fires its gaze at the keeper", velle.stats["rays"] > r0, velle.stats)
	var hits0: int = health.hits
	health.invulnerable = 0.0
	velle._open_atk_t = 0.0
	await h.wait(2.2)
	h.check("the gaze costs a keeper who stands still a heart", health.hits > hits0, [health.hits, health.hearts()])
	health.invulnerable = 9999.0
	health.refill()
	var gap_now: float = maxf(Boss.OPEN_BEAM_FASTEST, Boss.OPEN_BEAM_EVERY[0] * maxf(0.0, 1.0 - Boss.OPEN_RAGE_PER_S * velle._open_t))
	h.note("gaze", {"seconds open": snappedf(velle._open_t, 0.1), "gap between volleys at first": Boss.OPEN_BEAM_EVERY[0], "gap now": snappedf(gap_now, 0.01)})
	h.check("the gap between volleys has shrunk with the time open", gap_now < Boss.OPEN_BEAM_EVERY[0] * 0.6, gap_now)
	velle.attack_enabled = false
	velle.attacks.clear()

	# ---- a charge that falls out through the floor comes back
	var hole_col: int = ch.position.x + 3
	await h.clear_tiles([Vector2i(hole_col, ch.end.y), Vector2i(hole_col, ch.end.y + 1)])
	await h.wait(0.3)
	var hole_x: float = arena.position.x + (3 + 0.5) * 24.0
	h.check("there is a hole in the chamber floor", not velle.floor_at(hole_x))
	for b in velle.bombs.duplicate():
		if is_instance_valid(b):
			b.queue_free()
	await h.frames(3)
	var ret0: int = velle.stats["bombs_returned"]
	var lost = velle.spawn_bomb(Vector2(hole_x, arena.end.y - 60.0))
	await h.wait(0.5)
	await h.shot("charge_falling_into_hole")
	var back: bool = await h.until(func(): return velle.stats["bombs_returned"] > ret0, 6.0)
	await h.wait(0.5)
	await h.shot("charge_back_from_roof")
	h.check("a charge that falls through the floor is not lost", back, velle.stats)
	h.check("it comes back down from the roof", velle.live_bombs() == 1 and not is_instance_valid(lost), velle.live_bombs())
	var inside: bool = await h.until(func(): return velle.bombs.size() == 1 and is_instance_valid(velle.bombs[0]) and velle.bombs[0].linear_velocity.length() < 2.0, 6.0)
	var bp: Vector2 = velle.to_local(velle.bombs[0].global_position) if velle.bombs.size() == 1 else Vector2.ZERO
	h.check("and lands on floor that is still there", inside and arena.has_point(bp) and velle.floor_at(bp.x), bp)

	# ---- phase 2: a heart, stalk lasers, the cross
	var hp0: float = velle.hp
	Director.explosion_at(velle.to_global(velle.eye_pos()), "bomb")
	await h.wait(0.3)
	h.check("a hit that does not end the phase leaves the eye open", velle.is_open() and velle.hp == hp0 - 5.0, [velle.state, velle.hp])
	Director.explosion_at(velle.to_global(velle.eye_pos()), "bomb")
	await h.wait(0.6)
	await h.shot("phase2_roar_heart")
	h.check("crossing %d health ends the phase: the eye shuts" % Boss.PHASE_AT[0], velle.phase == 1 and velle.state == "roar", [velle.phase, velle.state])
	h.check("the new phase shakes a heart loose", velle.pickups.size() == 1, velle.stats)
	await h.until(func(): return velle.state == "fight", 6.0)
	health.invulnerable = 0.0
	health.hurt(Vector2.ZERO, "test")
	health.invulnerable = 9999.0
	var before: int = health.hearts()
	await h.wait(0.6)
	await _put(h, velle, velle.pickups[0]["p"])
	await h.wait(0.3)
	h.check("picking the heart up heals one heart", health.hearts() == before + 1 and velle.pickups.is_empty(), [before, health.hearts()])
	await _put(h, velle, arena.position + Vector2(110, 120))
	await h.wait(1.0)
	velle.attack_enabled = true
	r0 = velle.stats["rays"]
	var lasered: bool = await h.until(func(): return velle.attacks.any(func(a): return a["kind"] == "ray" and a["track"] == "stalk" and a["t"] > 0.9), 25.0)
	await h.burst("stalk_laser", 3, 4)
	h.check("in phase 2 eye stalks fire thin lasers", lasered, velle.stats)
	velle.attack_enabled = false
	velle.attacks.clear()
	velle.orbs.clear()
	velle.start_attack("cross", velle.to_local(h.keeper().global_position))
	await h.wait(0.7)
	await h.shot("cross_telegraph")
	await h.wait(0.75)
	await h.burst("cross_fires", 3, 4)
	await h.wait(1.0)

	# ---- phase 2's open eye: the wall of light
	await _pop_all(h, velle)
	await h.until(func(): return velle.is_open(), 6.0)
	velle.attacks.clear()
	await _put(h, velle, arena.position + Vector2(70, 150))
	velle.start_attack("wall", velle.to_local(h.keeper().global_position))
	await h.wait(0.8)
	await h.shot("wall_telegraph")
	health.invulnerable = 0.0
	hits0 = health.hits
	await h.wait(0.9)
	await h.burst("wall_of_light", 6, 12)
	await h.wait(1.0)
	h.check("the wall of light burns a keeper who stays on its side", health.hits > hits0, health.hits)
	velle.attacks.clear()
	await _put(h, velle, arena.position + Vector2(arena.size.x - 70, 150))
	# Aimed at the left half, where the keeper no longer is.
	velle.start_attack("wall", arena.position + Vector2(70, 150))
	health.invulnerable = 0.0
	hits0 = health.hits
	await h.wait(3.9)
	h.check("and misses a keeper on the other side of the chamber", health.hits == hits0, health.hits)
	health.invulnerable = 9999.0
	health.refill()

	# ---- phase 3: the grid, and the closing jaws
	Director.explosion_at(velle.to_global(velle.eye_pos()), "bomb")
	await h.wait(0.3)
	Director.explosion_at(velle.to_global(velle.eye_pos()), "bomb")
	await h.until(func(): return velle.state == "fight" and velle.phase == 2, 8.0)
	h.check("phase 3 begins", velle.phase == 2, velle.hp)
	await h.wait(1.5)
	await _put(h, velle, arena.position + Vector2(130, 110))
	velle.attacks.clear()
	velle.start_attack("grid", velle.to_local(h.keeper().global_position))
	await h.wait(1.1)
	await h.shot("grid_telegraph")
	await h.wait(0.75)
	await h.burst("grid_fires", 3, 4)
	h.check("more eyes have opened in the walls (12)", velle.phase == 2)
	await h.wait(1.0)
	await _pop_all(h, velle)
	await h.until(func(): return velle.is_open(), 6.0)
	velle.attacks.clear()
	# Straight above the eye: the one safe place.
	await _put(h, velle, velle.eye_pos() + Vector2(0, -120))
	velle.start_attack("jaws", velle.to_local(h.keeper().global_position))
	await h.wait(0.9)
	await h.shot("jaws_telegraph")
	health.invulnerable = 0.0
	hits0 = health.hits
	await h.wait(1.6)
	await h.burst("jaws_closing", 5, 10)
	await h.wait(1.6)
	h.check("the closing walls of light leave the space above the eye safe", health.hits == hits0, health.hits)
	health.invulnerable = 9999.0
	h.note("velle stats", velle.stats)
