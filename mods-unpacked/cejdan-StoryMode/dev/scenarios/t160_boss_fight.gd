extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 160: Velle's chamber fight. Enters the chamber, sees the fight start
# and the chamber seal, takes a hit, pops eye stalks with a real cave bomb and
# with explosions, hurts the open great eye, walks through all three phases
# with a shot of every attack, and finishes the fight.

const Director = preload("res://mods-unpacked/cejdan-StoryMode/boss/boss_director.gd")
const Boss = preload("res://mods-unpacked/cejdan-StoryMode/data/boss.gd")
const TIMEOUT := 420


func boot() -> Dictionary:
	return {"seed": 12345}


func _enter(h) -> Rect2i:
	h.disable_waves()
	var td = Level.map.tileData
	var ch: Rect2i = td.get_meta("story_boss_chamber")
	var area: Array = []
	for y in range(ch.position.y - 3, ch.end.y + 2):
		for x in range(ch.position.x - 2, ch.end.x + 2):
			area.append(Vector2i(x, y))
	await h.reveal(area)
	await h.teleport_tile(ch.position + Vector2i(3, 2))
	return ch


# Pops every living stalk with explosions, as bombs would.
func _pop_all(h, velle) -> void:
	for s: Dictionary in velle.stalks.duplicate():
		if s["alive"]:
			Director.explosion_at(velle.to_global(s["pos"]), "bomb")
			await h.wait(0.3)


func run(h) -> void:
	var ch: Rect2i = await _enter(h)
	var boss = Director.instance()
	h.check("the boss director runs in a Story Mode run", boss != null)
	var started: bool = await h.until(func(): return Director.current() == "fight", 8.0)
	h.check("entering the chamber after the awakening beat starts the fight", started, Director.current())
	if not started:
		return
	var velle = boss.velle
	var health = boss.health
	velle.attack_enabled = false
	velle.spawn_bombs = false
	await h.wait(1.2)
	await h.shot("rising")
	await h.until(func(): return velle.state == "fight", 6.0)
	await h.wait(1.6)
	await h.shot("phase1_stalks")
	h.check("phase 1 has %d eye stalks" % Boss.STALKS[0], velle.alive_stalks() == Boss.STALKS[0], velle.alive_stalks())
	h.check("the keeper starts with %d hearts" % Boss.HEARTS, health.hearts() == Boss.HEARTS, health.hearts())
	h.check("the waves have stopped", Level.monstersByTeamId.values().all(func(mm): return mm.disabled))

	# ---- sealed in
	await h.teleport_tile(ch.position + Vector2i(3, -3))
	await h.wait(0.4)
	h.check("the keeper cannot leave the chamber", ch.has_point(h.keeper_tile()), h.keeper_tile())
	h.down("ui_left")
	await h.wait(3.0)
	h.up("ui_left")
	h.check("flying at the wall keeps the keeper inside", ch.has_point(h.keeper_tile()), h.keeper_tile())

	# ---- a hit: one heart, then safe for a moment
	var s0: Dictionary = velle.stalks[0]
	h.keeper().global_position = velle.to_global(s0["pos"])
	await h.wait(0.25)
	await h.burst("hit", 6, 3)
	h.check("touching an eye stalk costs one heart", health.hearts() == Boss.HEARTS - 1, health.hearts())
	h.keeper().global_position = velle.to_global(s0["pos"])
	await h.wait(0.3)
	h.check("no second hit while the keeper is blinking", health.hearts() == Boss.HEARTS - 1, health.hearts())
	await h.teleport_tile(ch.position + Vector2i(10, 4))
	await h.wait(1.5)

	# ---- a spat orb
	velle.attack_enabled = true
	var fired: bool = await h.until(func(): return velle.orbs.size() > 0, 10.0)
	await h.wait(0.4)
	await h.shot("orbs")
	h.check("eye stalks spit orbs at the keeper", fired, velle.stats)
	health.invulnerable = 9999.0
	# ---- phase 1's attack
	velle.attacks.clear()
	velle.start_attack("sweep", velle.to_local(h.keeper().global_position))
	await h.wait(0.5)
	await h.shot("sweep_telegraph")
	await h.wait(0.6)
	await h.burst("sweep", 5, 4)
	velle.attack_enabled = false
	await h.wait(1.5)

	# ---- a real cave bomb pops a stalk
	var target: Dictionary = velle.stalks[1]
	var bomb = velle.spawn_bomb(target["home"] + Vector2(0, 20))
	h.check("a mining charge drops into the chamber", bomb != null and is_instance_valid(bomb))
	await h.wait(2.5)
	await h.shot("bomb_lying")
	h.check("the charge lies still until it is carried", is_instance_valid(bomb) and not bomb.activated)
	if is_instance_valid(bomb):
		bomb.global_position = velle.to_global(target["pos"] + Vector2(0, 14))
		bomb.freeze = true
		bomb.activate()
		await h.until(func(): return not is_instance_valid(bomb), 6.0)
	await h.wait(0.3)
	await h.shot("bomb_popped_stalk")
	h.check("the bomb's explosion pops the stalk next to it", not target["alive"], velle.stats)

	# ---- the real Suit Blaster pops a stalk, and recharges fast down here
	var pid: String = h.keeper().playerId
	GameWorld.serverAddUpgrade(pid + ".suitblaster", "team1")
	await h.wait(0.5)
	Data.apply(pid + ".suitblaster.charge", 1.0)
	var s2: Dictionary = velle.stalks[2]
	h.keeper().global_position = velle.to_global(s2["pos"] + Vector2(-24, 10))
	await h.frames(3)
	await h.press("keeper_gadget1")
	await h.wait(0.4)
	await h.shot("blaster_charging")
	await h.wait(0.6)
	await h.shot("blaster_popped_stalk")
	h.check("a Suit Blaster blast pops the stalk beside the keeper", not s2["alive"], velle.stats)
	var c0: float = float(Data.of(pid + ".suitblaster.charge"))
	await h.wait(3.0)
	var c1: float = float(Data.of(pid + ".suitblaster.charge"))
	h.check("the blaster recharges fast in the chamber (%.0f s a charge)" % Boss.BLASTER_RECHARGE, c1 - c0 > 0.2, [c0, c1])
	await h.teleport_tile(ch.position + Vector2i(10, 4))

	# ---- the lid holds while stalks live
	var hp0: float = velle.hp
	Director.explosion_at(velle.to_global(velle.eye_pos()), "bomb")
	await h.wait(0.2)
	await h.shot("lid_holds")
	h.check("the shut eye takes no damage", velle.hp == hp0 and velle.stats["blocked"] == 1, velle.stats)

	# ---- all stalks gone: the eye opens
	await _pop_all(h, velle)
	var opened: bool = await h.until(func(): return velle.is_open(), 6.0)
	await h.wait(0.6)
	await h.shot("eye_open")
	h.check("with every stalk popped the great eye opens", opened, velle.state)
	Director.explosion_at(velle.to_global(velle.eye_pos()), "blast", 60.0)
	await h.wait(0.15)
	await h.shot("core_hit")
	h.check("a Suit Blaster blast hurts the open eye", velle.hp == hp0 - Boss.DAMAGE["blast"]["core"], velle.hp)
	Director.explosion_at(velle.to_global(velle.eye_pos()), "bomb")
	await h.wait(0.2)
	h.check("a bomb hurts it more", velle.hp == hp0 - Boss.DAMAGE["blast"]["core"] - Boss.DAMAGE["bomb"]["core"], velle.hp)

	# ---- phase 2
	Director.explosion_at(velle.to_global(velle.eye_pos()), "bomb")
	await h.wait(0.5)
	await h.shot("roar")
	h.check("at %d health phase 2 begins" % Boss.PHASE_AT[0], velle.phase == 1, [velle.phase, velle.hp])
	await h.until(func(): return velle.state == "fight", 6.0)
	await h.wait(1.5)
	h.check("phase 2 has %d eye stalks" % Boss.STALKS[1], velle.alive_stalks() == Boss.STALKS[1], velle.alive_stalks())
	for kind: String in ["lunge", "pull"]:
		velle.attacks.clear()
		velle.start_attack(kind, velle.to_local(h.keeper().global_position))
		await h.wait(0.5)
		await h.shot(kind + "_telegraph")
		await h.wait(0.55)
		await h.burst(kind, 4, 4)
		await h.wait(2.0)
	await _pop_all(h, velle)
	await h.until(func(): return velle.is_open(), 6.0)
	await h.wait(2.2)
	await h.shot("ring_burst")
	Director.explosion_at(velle.to_global(velle.eye_pos()), "bomb")
	await h.wait(0.2)
	Director.explosion_at(velle.to_global(velle.eye_pos()), "bomb")
	await h.wait(0.5)
	h.check("at %d health phase 3 begins" % Boss.PHASE_AT[1], velle.phase == 2, [velle.phase, velle.hp])

	# ---- phase 3
	await h.until(func(): return velle.state == "fight", 6.0)
	await h.wait(1.5)
	await h.shot("phase3_stalks")
	h.check("phase 3 has %d eye stalks" % Boss.STALKS[2], velle.alive_stalks() == Boss.STALKS[2], velle.alive_stalks())
	velle.attacks.clear()
	velle.start_attack("erupt", velle.to_local(h.keeper().global_position))
	await h.wait(0.5)
	await h.shot("erupt_telegraph")
	await h.wait(0.5)
	await h.burst("erupt", 5, 5)
	await h.wait(2.0)
	velle.attacks.clear()
	velle.start_attack("beam", velle.to_local(h.keeper().global_position))
	await h.wait(0.6)
	await h.shot("beam_aim")
	await h.wait(0.6)
	await h.shot("beam_locked")
	await h.wait(0.3)
	await h.burst("beam_fire", 3, 4)
	velle.attacks.clear()

	# ---- the end
	await _pop_all(h, velle)
	await h.until(func(): return velle.is_open(), 6.0)
	await h.wait(0.5)
	for i in 6:
		if velle.state == "open":
			Director.explosion_at(velle.to_global(velle.eye_pos()), "bomb")
			await h.wait(0.2)
	await h.wait(0.4)
	await h.burst("dying", 4, 12)
	h.check("at zero health Velle is dying", velle.state == "dying", [velle.state, velle.hp])
	var ended: bool = await h.until(func(): return Director.current() != "fight", 8.0)
	await h.wait(0.5)
	await h.shot("husk")
	h.check("the fight ends when Velle falls", ended, Director.current())
	h.note("velle stats", velle.stats)
	h.note("sounds played", load("res://mods-unpacked/cejdan-StoryMode/boss/sfx.gd").played)
