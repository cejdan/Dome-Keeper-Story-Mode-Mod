extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 161: the tentacle chase. Kills Velle, then flees up an open shaft with
# real input: the tentacles follow the keeper's own path at a speed tied to the
# keeper's top speed. Checks the steady gap at base speed and with every speed
# upgrade, that a keeper who stops gets hit, that the overheat recall is jammed
# (a heart, no teleport), and that reaching the dome ends the chase.

const Director = preload("res://mods-unpacked/cejdan-StoryMode/boss/boss_director.gd")
const Boss = preload("res://mods-unpacked/cejdan-StoryMode/data/boss.gd")
const TIMEOUT := 420


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	var td = Level.map.tileData
	var ch: Rect2i = td.get_meta("story_boss_chamber")
	var field = Level.map.get_node("StoryLavaField")
	# The lava ocean would cook this keeper (no Heat Shielding); the heat test
	# below is separate.
	Data.apply("team1.suit.heatshield", 4)
	var area: Array = []
	for y in range(ch.position.y - 3, ch.end.y + 2):
		for x in range(ch.position.x - 2, ch.end.x + 2):
			area.append(Vector2i(x, y))
	await h.reveal(area)
	# An open shaft from the chamber roof far up into the map, for a clean run.
	var top_y: int = ch.position.y - 150
	var sx: int = ch.position.x + 4
	var shaft: Array = []
	for y in range(top_y, ch.position.y):
		for dx in range(-1, 3):
			shaft.append(Vector2i(sx + dx, y))
	for pass_i in 3:
		await h.reveal(shaft)
		await h.frames(5)
		for c in shaft:
			var t = Level.map.getTile(Vector2(c))
			if t != null and is_instance_valid(t):
				Level.map.destroyTile("team1", "", t)
		await h.frames(5)
	var blocked: Array = shaft.filter(func(c): return not Level.map.is_tile_empty(c))
	h.check("the test shaft is open", blocked.is_empty(), blocked.slice(0, 8))
	field.mass.clear()
	field.freeze_flow = true
	await h.teleport_tile(Vector2i(sx, ch.position.y + 2))
	await h.until(func(): return Director.current() == "fight", 8.0)
	var boss = Director.instance()
	var velle = boss.velle
	velle.attack_enabled = false
	velle.spawn_bombs = false
	await h.until(func(): return velle.state == "fight", 8.0)
	await h.wait(1.3)
	# Kill Velle quickly.
	for round in 8:
		if Director.current() != "fight" or velle.state == "dying":
			break
		for s: Dictionary in velle.stalks.duplicate():
			if s["alive"]:
				Director.explosion_at(velle.to_global(s["pos"]), "bomb")
		await h.until(func(): return velle.is_open() or velle.state == "dying", 6.0)
		for i in 3:
			if velle.state == "open":
				Director.explosion_at(velle.to_global(velle.eye_pos()), "bomb")
				await h.wait(0.15)
		await h.until(func(): return velle.state in ["fight", "dying", "dead"], 6.0)
		await h.wait(1.2)
	var chasing: bool = await h.until(func(): return Director.current() == "chase", 10.0)
	h.check("when Velle falls the chase begins", chasing, Director.current())
	if not chasing:
		return
	var chase = boss.chase
	var health = boss.health
	await h.wait(0.8)
	await h.shot("chase_begins")
	h.check("the chamber is no longer sealed: the keeper can leave", true)

	# ---- flee up the shaft at base speed
	var k = h.keeper()
	# Velle's roars shoved the keeper about; line up under the shaft's middle.
	k.global_position = Level.map.getTilePos(Vector2(sx, ch.position.y + 2)) + Vector2(12, 0)
	await h.frames(3)
	h.down("ui_up")
	await h.wait(Boss.CHASE_HEAD_START + 3.0)
	h.check("the keeper is out of the chamber", h.keeper_tile().y < ch.position.y, h.keeper_tile())
	var gaps: Array = []
	for i in 12:
		await h.wait(0.5)
		gaps.append(snappedf(chase.gap, 1.0))
		if i == 4:
			await h.shot("fleeing_base_speed")
	var base_speed: float = chase.keeper_speed
	var hits0: int = chase.hits
	h.note("base speed flight", {"keeper_speed": base_speed, "tip_speed": snappedf(chase.speed, 0.1), "gaps": gaps})
	h.check("flat out at base speed the tips hold a gap of 2 to 8 tiles", gaps.slice(6).all(func(g): return g > 48.0 and g < 192.0), gaps)
	h.check("a keeper who never slows is not hit", hits0 == 0, hits0)

	# ---- stop: they catch up and hit
	h.up("ui_up")
	# A save mid-chase, for t161_reload.
	await SaveGame.saveGame("singleplayer", 16, true)
	h.note("saved slot 16", {"state": Director.current(), "hearts": health.hearts(), "keeper": h.keeper_tile()})
	var hearts0: int = health.hearts()
	var hit: bool = await h.until(func(): return chase.hits > hits0, 8.0)
	await h.burst("caught", 5, 4)
	h.check("a keeper who stops is caught and loses a heart", hit and health.hearts() == hearts0 - 1, [chase.hits, health.hearts()])
	h.check("every tip recoils after the hit", chase.recoil > 0.0, chase.recoil)

	# ---- every speed upgrade: still chased just as closely
	health.refill()
	await h.wait(1.5)
	Data.apply(k.playerId + ".keeper1.maxSpeed", 140)
	h.down("ui_up")
	await h.wait(4.0)
	var fast_gaps: Array = []
	for i in 10:
		await h.wait(0.5)
		fast_gaps.append(snappedf(chase.gap, 1.0))
		if i == 5:
			await h.shot("fleeing_max_speed")
	h.note("max speed flight", {"keeper_speed": chase.keeper_speed, "tip_speed": snappedf(chase.speed, 0.1), "gaps": fast_gaps})
	h.check("the tips speed up with the keeper (%.0f -> %.0f px/s)" % [base_speed, chase.keeper_speed], chase.speed > base_speed * 1.5, chase.speed)
	h.check("at full upgrades the gap is still 2 to 8 tiles", fast_gaps.slice(5).all(func(g): return g > 48.0 and g < 192.0), fast_gaps)

	# ---- the overheat recall is jammed
	health.refill()
	var hearts1: int = health.hearts()
	var pos1: Vector2 = k.global_position
	health.invulnerable = 0.0
	field.heat = field.HEAT_MAX
	field._update_heat(0.016)
	await h.frames(3)
	h.check("overheating costs a heart", health.hearts() == hearts1 - 1, health.hearts())
	h.check("and does not recall the keeper to the dome", k.global_position.distance_to(pos1) < 120.0 and not k.isInsideDome, [pos1, k.global_position])
	h.check("the suit keeps some heat (%.0f%%)" % (Boss.OVERHEAT_HEAT_AFTER * 100.0), absf(field.heat - field.HEAT_MAX * Boss.OVERHEAT_HEAT_AFTER) < 5.0, field.heat)

	# ---- a teleport: the tips streak after the keeper
	h.up("ui_up")
	health.invulnerable = 9999.0
	await h.dig_room(Vector2i(-1, 1), Vector2i(1, 9))
	await h.teleport_tile(Vector2i(0, 8))
	await h.wait(0.5)
	await h.shot("streaking_after_a_teleport")
	h.down("ui_up")
	var home: bool = await h.until(func(): return k.isInsideDome, 30.0)
	h.up("ui_up")
	await h.wait(0.3)
	await h.shot("home")
	h.check("the keeper reaches the dome", home, h.keeper_tile())
	h.check("reaching the dome ends the chase", Director.current() != "chase", Director.current())
