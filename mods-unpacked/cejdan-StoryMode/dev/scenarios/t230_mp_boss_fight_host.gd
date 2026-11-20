extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #230 (1/3), host half: Velle's chamber fight for a team. The fight starts
# with only the client's keeper in the chamber and Velle hits it (the host's
# keeper is still at the dome, untouched and not sealed in); the host's keeper
# joins and is held; the client's Suit Blaster pops a stalk; the client's
# overheat costs a heart; and a won fight moves the team to the chase.
# Pair: t230_mp_boss_fight_client.

const Director = preload("res://mods-unpacked/cejdan-StoryMode/boss/boss_director.gd")
const Boss = preload("res://mods-unpacked/cejdan-StoryMode/data/boss.gd")
const Awakening = preload("res://mods-unpacked/cejdan-StoryMode/beats/awakening.gd")
const TIMEOUT := 480


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func _client_keeper(h):
	for k in Keepers.getAll():
		if k.peerId != h.multiplayer.get_unique_id():
			return k
	return null


func _facts(velle) -> Dictionary:
	return {"state": velle.state, "phase": velle.phase, "hp": velle.hp, "stalks": velle.stalks.size(), "alive": velle.alive_stalks(),
		"attacks": velle.attacks.size(), "t": velle.time}


func run(h) -> void:
	if not await host_start(h):
		return
	# The Data race behind the "client reads no boss state" oddity (see
	# boss_director.gd): vanilla sends a client all of Data when it changes
	# stage (Client.full_data_sync), in chunks over a few frames; a small change
	# made meanwhile goes straight out, arrives first, and is then overwritten
	# by the older full copy. race_a is made in that window, race_b after it;
	# since #242 the host sends race_a again once the copies have landed.
	# (Not in the client's first moments: its first, large update is itself
	# sent in chunks, in order behind the full copies.)
	await h.wait(2.0)
	for i in 3:
		Network.clients[0].full_data_sync()
	Data.apply("story.dev.race_a", 1)
	await h.wait(1.0)
	Data.apply("story.dev.race_b", 1)
	var boss = Director.instance()
	var ck = _client_keeper(h)
	h.check("boss director and a client keeper on the host", boss != null and ck != null, keeper_rows(h))
	if boss == null or ck == null:
		return
	# The run as it stands when a team reaches Velle: the chamber found, the
	# horror awake, its beat read, the gear bought (dev/boss_dev.gd).
	var dev = load("res://mods-unpacked/cejdan-StoryMode/dev/boss_dev.gd")
	# Every keeper's gear: Heat Shielding IV and the Suit Blaster too (#265).
	dev.give_gear()
	var ch: Rect2i = Level.map.tileData.get_meta("story_boss_chamber")
	var cells: Array = []
	for y in range(ch.position.y - 3, ch.end.y + 2):
		for x in range(ch.position.x - 2, ch.end.x + 2):
			cells.append(Vector2i(x, y))
	await h.reveal(cells)
	Data.apply("team1.story.beatsplayed", str(Data.ofOr("team1.story.beatsplayed", "")) + ",boss_chamber")
	Data.apply(Awakening.AWAKE, true)
	await h.wait(1.0)
	var home: Vector2i = h.keeper_tile()
	h.check("no fight while nobody is in the chamber", Director.current() == "", Director.current())

	# ---- the client's keeper alone starts the fight
	share("chamber", [ch.position.x, ch.position.y, ch.size.x, ch.size.y])
	var started: bool = await h.until(func(): return Director.current() == "fight", 40.0)
	h.check("the fight starts with only the client's keeper in the chamber", started, {"state": Director.current(), "keepers": keeper_rows(h)})
	if not started:
		return
	var velle = boss.velle
	var health = boss.health
	await h.until(func(): return velle.state == "fight", 8.0)
	await h.shot("host_far_away")
	h.check("the host's keeper, at the dome, is not pulled into the chamber", h.keeper_tile().distance_to(home) < 3, [home, h.keeper_tile()])
	var hurt: bool = await h.until(func(): return health.hearts() < Boss.HEARTS, 60.0)
	h.check("Velle hits the client's keeper: the team loses a heart", hurt, {"hearts": health.hearts(), "hits": health.hits, "velle": velle.stats})
	h.check("the client's keeper is safe for a moment; the host's was not hit", health.safe_left(ck) > 0.0 and health.invulnerable == 0.0, [health.safe_left(ck), health.invulnerable])
	h.check("the client's keeper is held in the chamber", ch.has_point(Level.map.getTileCoord(ck.global_position)), keeper_rows(h))
	await h.wait(1.5)
	# Nobody dies in this test from here on.
	health.set_safe(ck, 99999.0)
	health.invulnerable = 99999.0
	health.refill()

	# ---- the host's keeper joins
	await h.teleport_tile(ch.position + Vector2i(3, 2))
	await h.wait(0.6)
	await h.teleport_tile(ch.position + Vector2i(3, -3))
	await h.wait(0.5)
	h.check("the host's keeper, once in, is held too", ch.has_point(h.keeper_tile()), h.keeper_tile())
	await h.teleport_tile(ch.position + Vector2i(3, 2))
	velle.attack_enabled = false
	velle.spawn_bombs = false
	velle.attacks.clear()
	velle.orbs.clear()
	await h.wait(1.5)
	share("look1", _facts(velle))
	await h.wait(0.5)
	await h.shot("host_stalks")
	# One attack at the client's keeper, for both to shoot.
	velle.start_attack("lunge", velle.to_local(ck.global_position), ck)
	velle.start_attack("beam1", velle.to_local(ck.global_position), ck)
	share("look2", _facts(velle))
	await h.wait(0.6)
	await h.shot("host_attack_telegraph")
	await h.wait(0.75)
	await h.shot("host_attack")
	await h.wait(2.0)

	# ---- the client's Suit Blaster
	Data.apply(ck.playerId + ".suitblaster.charge", 1.0)
	var target: Dictionary = velle.stalks[velle.stalks.size() - 1]
	var popped0: int = velle.stats["stalks_popped"]
	var at: Vector2 = velle.to_global(target["pos"] + Vector2(-24, 10))
	share("blast", [at.x, at.y])
	var popped: bool = await h.until(func(): return not target["alive"], 20.0)
	h.check("the client's Suit Blaster pops the stalk beside it", popped, {"popped": [popped0, velle.stats["stalks_popped"]], "client charge": Data.ofOr(ck.playerId + ".suitblaster.charge", null), "keepers": keeper_rows(h)})
	await h.shot("host_after_blast")

	# ---- the client's suit overheats: a heart, not a recall
	var h0: int = health.hearts()
	share("overheat", true)
	var cost: bool = await h.until(func(): return health.hearts() < h0, 20.0)
	await h.wait(1.0)
	h.check("the client's overheat costs the team one heart", cost and health.hearts() == h0 - 1, [h0, health.hearts()])
	h.check("and its keeper is not recalled", ch.has_point(Level.map.getTileCoord(ck.global_position)), keeper_rows(h))
	health.set_safe(ck, 99999.0)

	# ---- the eye opens; the fight is won
	var guard: int = 0
	while Director.current() == "fight" and guard < 40:
		guard += 1
		if velle.state == "fight":
			for s: Dictionary in velle.stalks.duplicate():
				if s["alive"]:
					Director.explosion_at(velle.to_global(s["pos"]), "bomb")
					await h.wait(0.2)
		elif velle.state == "open" and velle.is_open():
			if guard % 2 == 0 and velle.hp > 6.0:
				share("look3", _facts(velle))
				await h.wait(0.5)
				await h.shot("host_eye_open_%d" % velle.phase)
			Director.explosion_at(velle.to_global(velle.eye_pos()), "bomb")
		await h.wait(0.6)
	h.check("the fight is won: the team is in the chase", Director.current() == "chase", [Director.current(), velle.hp, guard])
	await h.wait(1.0)
	await h.shot("host_husk")
	share("done", {"state": Director.current(), "hearts": health.hearts(), "velle": velle.state})
	h.note("velle stats", velle.stats)
	h.note("host music", boss.music.playing())
	await host_wait_clients_left(h)
