extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #230 (3/3), host half: the finale for a team. Starts at the finale with the
# dev command (`_dev_boss("finale")`). The client's keeper takes the dome's
# weapon, which ends the breath; its laser hurts the host's tentacle; then the
# host finishes the battle (every monster killed outright) and the client
# follows: flyers, the great eye, its fall, the monsters' thanks, and the
# saved ending on both instances.
# Pair: t230_mp_boss_finale_client.

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
const Boss = preload("res://mods-unpacked/flantor-StoryMode/data/boss.gd")
const TIMEOUT := 480


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func _client_keeper(h):
	for k in Keepers.getAll():
		if k.peerId != h.multiplayer.get_unique_id():
			return k
	return null


func _roster(fin) -> Array:
	var out: Array = []
	for m in fin.alive:
		if is_instance_valid(m):
			out.append([m.techId, m.UID, m.dead])
	return out


# Kills every monster that can be hit; `only` limits it to one kind (techId).
func _kill(fin, only: String = "") -> int:
	var n: int = 0
	for m in fin.alive:
		if is_instance_valid(m) and not m.dead and not m.invulnerable and (only == "" or m.techId == only):
			m.hit("laser", 999999.0, 0.0)
			n += 1
	return n


func run(h) -> void:
	if not await host_start(h):
		return
	var boss = Director.instance()
	var ck = _client_keeper(h)
	h.check("boss director and a client keeper on the host", boss != null and ck != null, keeper_rows(h))
	if boss == null or ck == null:
		return
	boss._dev_boss("finale")
	var started: bool = await h.until(func(): return Director.current() == "finale" and boss.finale != null, 10.0)
	h.check("`--boss=finale` starts the finale on the host", started, Director.current())
	if not started:
		return
	var fin = boss.finale
	share("finale", true)

	# ---- the client's keeper takes the weapon: the bells
	var bells: bool = await h.until(func(): return fin.step != "breath", 60.0)
	h.check("the client's keeper at the dome's weapon ends the breath", bells and fin.bells_by == "battle" and not h.keeper().isInsideStation,
		{"step": fin.step, "by": fin.bells_by, "host at station": h.keeper().isInsideStation, "client at station": ck.isInsideStation})
	var r1: bool = await h.until(func(): return fin.step == "round1", 40.0)
	h.check("round 1 breaks out", r1, fin.step)
	await h.wait(1.2)
	var tents: Array = fin.alive.filter(func(m): return is_instance_valid(m) and m.techId == "storytentacle")
	share("round1", tents.map(func(m): return m.UID))
	await h.shot("host_round1")

	# ---- the client's laser, on the host's tentacles
	var hp0: Dictionary = {}
	for m in tents:
		hp0[m.UID] = m.currentHealth
	var hurt_by_client := func() -> bool:
		for m in tents:
			if not is_instance_valid(m) or m.dead or m.currentHealth < float(hp0[m.UID]) - 1.0:
				return true
		return false
	var hurt: bool = await h.until(hurt_by_client, 40.0)
	h.check("the client's laser hurts the host's tentacles (the host's keeper is not at the weapon)", hurt and not h.keeper().isInsideStation,
		{"health": tents.map(func(m): return [m.UID, m.currentHealth if is_instance_valid(m) else -1, hp0[m.UID]]), "host at station": h.keeper().isInsideStation})
	share("hurt", tents.map(func(m): return [m.UID, m.currentHealth if is_instance_valid(m) else -1.0]))
	await h.wait(1.0)

	# ---- flyers: one tentacle dies and its eyes take to the sky
	_kill(fin, "storytentacle")
	var flew: bool = await h.until(func(): return fin.flyers_alive() > 0, 10.0)
	h.check("dead tentacles' eyes fly", flew, _roster(fin))
	await h.wait(1.5)
	share("flyers", _roster(fin))
	await h.shot("host_flyers")
	await h.wait(2.0)

	# ---- the host finishes the battle
	var t0: float = h.now()
	var great_seen: bool = false
	var shot_great: bool = false
	while not fin.step in ["allies", "thanks", "done"] and h.now() - t0 < 150.0 and not GameWorld.lost:
		if fin.step == "round3" and is_instance_valid(fin.great) and not fin.great.dead:
			great_seen = true
			if not shot_great and fin.great.emerge >= 1.0:
				shot_great = true
				share("great", fin.great.UID)
				await h.wait(1.0)
				await h.shot("host_great_eye")
				# The client looks at it too before it is beaten.
				await h.wait(2.5)
		_kill(fin)
		await h.wait(0.5)
	h.check("the battle is won (the great eye rose and fell)", great_seen and fin.step in ["allies", "thanks", "done"], {"step": fin.step, "lost": GameWorld.lost})
	await h.wait(2.0)
	await h.shot("host_allies")
	var won: bool = await h.until(func(): return Director.current() == "won", 60.0)
	h.check("the finale is done: the boss state is `won`", won, [Director.current(), fin.step])
	var ending: bool = await h.until(func(): return Level.mode.get("_ending") == true, 10.0)
	h.check("the saved ending plays on the host", ending)
	await h.wait(3.0)
	await h.shot("host_ending")
	var panel: bool = await h.until(func(): return Level.stage.endingPanel != null, 120.0)
	h.check("end screen on the host, titled saved", panel and GameWorld.won and Level.stage.endingPanel.titleLabel.text == load("res://mods-unpacked/flantor-StoryMode/data/endings.gd").SAVED_TITLE, [GameWorld.won, Level.stage.endingPanel.titleLabel.text if panel else null])
	await h.wait(2.5)
	await h.shot("host_end_screen")
	await h.wait(4.0)
	h.check("exactly one set of ending cards and one end screen here", Level.mode.get_node("StoryEndings").cards_shown == 1 and Level.mode.end_screens == 1, [Level.mode.get_node("StoryEndings").cards_shown, Level.mode.end_screens])
	await host_wait_clients_left(h)
