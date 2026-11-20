extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #230 (1/3), client half: the client's keeper walks into Velle's chamber
# alone. It reads the boss state, sees Velle (a puppet of the host's), is
# sealed in and hit, hears the fight, pops a stalk with its Suit Blaster,
# overheats for a heart and follows the team into the chase.
# Pair: t230_mp_boss_fight_host.

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const Boss = preload("res://mods-unpacked/flantor-StoryMode/data/boss.gd")
static var _Boss = Boss  # calls go through this: lazy_preload makes const-preload calls slow
const Sfx = preload("res://mods-unpacked/flantor-StoryMode/boss/sfx.gd")
const TIMEOUT := 480


func boot() -> Dictionary:
	return {"netjoin": true}


func _facts(velle) -> Dictionary:
	return {"state": velle.state, "phase": velle.phase, "hp": velle.hp, "stalks": velle.stalks.size(), "alive": velle.alive_stalks(),
		"attacks": velle.attacks.size(), "t": velle.time}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var c = await shared(h, "chamber", 120.0)
	h.check("the host set the chamber up", c != null)
	if c == null:
		return
	# Vanilla's Data race: a change made while a full Data sync is on its way
	# is overwritten here by that sync; StoryNet's settled resend (#242) sends
	# it again once the sync has landed.
	var race := func() -> Array: return [int(Data.ofOr("story.dev.race_a", 0)), int(Data.ofOr("story.dev.race_b", 0))]
	await h.until(func(): return race.call() == [1, 1], 5.0)
	h.check("a change made while a full Data sync is on its way arrives too (#242)", race.call() == [1, 1], race.call())
	var ch := Rect2i(int(c[0]), int(c[1]), int(c[2]), int(c[3]))
	# The host's playtest reveal of the chamber is local to it (real drilling
	# reveals tiles on every peer): the same here, for the screenshots.
	var cells: Array = []
	for y in range(ch.position.y - 3, ch.end.y + 2):
		for x in range(ch.position.x - 2, ch.end.x + 2):
			cells.append(Vector2i(x, y))
	var mid: Vector2 = Vector2(ch.get_center())
	var cell_facts := func(): return {"hard": Level.map.tileData.get_hardnessv(mid), "res": Level.map.tileData.get_resourcev(mid),
		"visible": Level.map.visibleTileCoords.get(mid, "no"), "tiles": Level.map.tiles.size(), "visibles": Level.map.visibleTileCoords.size(),
		"revealdistance": Data.ofOr("map.revealdistance", null), "pending": Level.map.flood_pending() if Level.map.has_method("flood_pending") else null}
	h.note("chamber cell before the reveal", cell_facts.call())
	await h.reveal(cells)
	h.note("chamber cell after the reveal", cell_facts.call())
	var boss = _Director.instance()
	h.check("the boss director is on the client", boss != null)
	h.check("no boss state yet", _Director.current() == "" and not _Director.jams_recall(), _Director.current())
	await h.teleport_tile(ch.position + Vector2i(ch.size.x - 4, 2))

	# ---- the fight, as the client reads and sees it
	var reads: bool = await h.until(func(): return _Director.current() == "fight", 15.0)
	h.check("the boss state reads `fight` on the client", reads, _Director.current())
	var built: bool = await h.until(func(): return boss.velle != null and boss.velle.puppet and boss.velle.time > 0.5, 10.0)
	h.check("the client has the boss layer and a puppet Velle", built and boss.layer != null, [boss.layer != null, boss.velle != null])
	if not built:
		return
	# The boss state lost from this client's Data comes back (the repeat, kept as insurance).
	Data.values.erase(Director.STATE)
	h.check("state gone from the client's Data", _Director.current() == "")
	var back: bool = await h.until(func(): return _Director.current() == "fight", 5.0)
	h.check("the host's repeat brings the boss state back within %.0f s" % Director.NET_REPEAT, back, _Director.current())
	await h.until(func(): return boss.velle != null and is_instance_valid(boss.velle) and boss.velle.puppet and boss.velle.time > 0.5, 5.0)
	var velle = boss.velle
	var health = boss.health
	await h.shot("client_rising")
	h.check("the recall is jammed for the client too", _Director.jams_recall())
	await h.until(func(): return velle.state == "fight" and velle.stalks.size() > 0, 8.0)
	h.check("Velle's stalks grow on the client", velle.stalks.size() == _Boss.stalks(0), _facts(velle))
	await h.teleport_tile(ch.position + Vector2i(ch.size.x - 4, -3))
	await h.wait(0.5)
	h.check("the client's keeper cannot leave the chamber", ch.has_point(h.keeper_tile()), h.keeper_tile())
	await h.teleport_tile(ch.position + Vector2i(ch.size.x - 4, 3))
	await h.wait(0.3)
	var p0: Vector2 = h.keeper().global_position
	var seen_hit: bool = await h.until(func(): return health.invulnerable > 0.0, 60.0)
	h.check("Velle's hit reaches the client's keeper (it blinks, safe for a moment)", seen_hit, {"hearts": health.hearts(), "safe": health.invulnerable})
	var thrown: float = 0.0
	for i in 12:
		await h.frames(1)
		thrown = maxf(thrown, h.keeper().global_position.distance_to(p0))
	var lower: bool = await h.until(func(): return health.hearts() < Boss.HEARTS, 1.0)
	h.check("the team's hearts read lower on the client", lower, health.hearts())
	await h.shot("client_hit")
	h.check("the hit throws the client's keeper", thrown > 4.0, thrown)
	h.check("the fight's music plays on the client", boss.music.mode == "fight" and boss.music.playing().size() > 0, boss.music.playing())
	h.check("Velle's sounds play on the client", int(Sfx.played.get("roar", 0)) > 0 and int(Sfx.played.get("grow", 0)) > 0, Sfx.played)

	# ---- both instances draw the same Velle
	var l1 = await shared(h, "look1", 60.0)
	await h.wait(0.5)
	await h.shot("client_stalks")
	h.check("Velle matches the host's (state, phase, health, stalks)", l1 != null and velle.state == l1["state"] and velle.phase == int(l1["phase"])
		and is_equal_approx(velle.hp, float(l1["hp"])) and velle.alive_stalks() == int(l1["alive"]), [l1, _facts(velle)])
	h.check("the client's clock follows the host's", l1 != null and absf(velle.time - 0.5 - float(l1["t"])) < 0.5, [l1, velle.time])
	var l2 = await shared(h, "look2", 30.0)
	await h.wait(0.6)
	await h.shot("client_attack_telegraph")
	var kinds: Array = velle.attacks.map(func(a): return a["kind"])
	h.check("the host's attacks show on the client (a lunge and a gaze)", kinds.has("strike") and kinds.has("ray"), [l2, kinds])
	await h.wait(0.75)
	await h.shot("client_attack")

	# ---- the Suit Blaster
	var b = await shared(h, "blast", 30.0)
	h.check("the client's keeper has a charged Suit Blaster", float(Data.ofOr(h.keeper().playerId + ".suitblaster.charge", 0.0)) >= 1.0, Data.ofOr(h.keeper().playerId + ".suitblaster.charge", null))
	h.keeper().global_position = Vector2(float(b[0]), float(b[1]))
	# The host places the blast where it sees this keeper: let the move arrive.
	await h.wait(0.6)
	await h.press("keeper_gadget1")
	await h.wait(0.4)
	await h.shot("client_blaster")
	await h.wait(1.2)
	await h.shot("client_after_blast")
	h.check("the stalk it popped is gone on the client too", velle.alive_stalks() == velle.stalks.size() - 1, _facts(velle))

	# ---- overheat: a heart, not a recall
	await shared(h, "overheat", 30.0)
	var lava = Level.map.get_node("StoryLavaField")
	var h0: int = health.hearts()
	lava.heat = lava.HEAT_MAX + 1.0
	var cost: bool = await h.until(func(): return health.hearts() < h0, 10.0)
	h.check("overheating in the fight costs a heart", cost, [h0, health.hearts()])
	h.check("and does not recall the keeper", ch.has_point(h.keeper_tile()) and lava.heat < lava.HEAT_MAX, [h.keeper_tile(), lava.heat])

	# ---- the eye opens, Velle dies, the chase begins
	var l3 = await shared(h, "look3", 60.0)
	await h.wait(0.5)
	await h.shot("client_eye_open")
	h.check("the open eye shows on the client", l3 != null and (velle.state == "open" or velle.hp < float(l3["hp"])), [l3, _facts(velle)])
	var done = await shared(h, "done", 120.0)
	await h.wait(1.0)
	await h.shot("client_husk")
	h.check("the won fight moves the client to the chase", done != null and _Director.current() == "chase", [done, _Director.current()])
	h.check("Velle is dead on the client", velle.state == "dead" and velle.hp <= 0.0, _facts(velle))
	h.check("the chase music plays on the client", boss.music.mode == "chase" and boss.music.playing().size() > 0, boss.music.playing())
	h.note("client sounds", Sfx.played)
