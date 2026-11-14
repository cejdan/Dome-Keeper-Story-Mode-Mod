extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 162: the final battle on the surface. Starts at the end of the chase
# (the keeper is in the dome), sees the tentacles burst out beside the dome,
# shoots one with the real laser from the station with real input, sees a slam
# hurt the dome, plays both rounds, and watches the monsters arrive, finish the
# horror and thank the keeper in runes. Then the saved ending starts.

const Director = preload("res://mods-unpacked/cejdan-StoryMode/boss/boss_director.gd")
const BossText = preload("res://mods-unpacked/cejdan-StoryMode/data/boss_text.gd")
const TIMEOUT := 420


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


func run(h) -> void:
	h.disable_waves()
	await h.wait(1.0)
	var boss = Director.instance()
	var dome = Level.getDome("team1")
	var k = h.keeper()
	h.check("the keeper starts in the dome", k.isInsideDome)
	# Jump to the end of the chase.
	boss._ensure_layer()
	boss._stop_waves()
	boss._set_state("chase")
	boss._start_chase(Vector2(0, 400))
	var started: bool = await h.until(func(): return Director.current() == "finale", 5.0)
	h.check("reaching the dome in the chase starts the finale", started, Director.current())
	if not started:
		return
	var fin = boss.finale
	await h.wait(1.2)
	await h.shot("rumble")
	await h.until(func(): return fin.step == "round1", 6.0)
	await h.wait(0.5)
	await h.burst("bursting_out", 4, 6)
	await h.wait(1.2)
	await h.shot("round1")
	h.check("round 1: two tentacles beside the dome", fin.living() == 2, fin.living())
	h.check("they are real monster targets", fin.alive.all(func(m): return m is Monster and m.is_in_group("monster") and m.collision_layer == 128))
	h.check("the dome is at battle stations", Data.of("team1.monsters.wavepresent") == true)
	h.note("tentacle health", {"unit": fin.unit_hp, "each": fin.alive.map(func(m): return m.maxHealth)})

	# ---- the real laser, real input
	var st = _station(dome)
	h.check("the dome has a weapon station", st != null)
	var left = fin.alive.filter(func(m): return m.global_position.x < dome.global_position.x)[0]
	if st != null:
		st.useHit(k)
		await h.wait(2.5)
		h.note("in station", {"keeper_in_station": k.isInsideStation, "weapons": st.getControlledWeapons().size()})
		var hurt: bool = false
		for i in 30:
			# Key-down events are edges; send them again in case the station's
			# input was not listening yet.
			h.up("ui_left")
			h.up("dome1_fire")
			await h.frames(2)
			h.down("ui_left")
			h.down("dome1_fire")
			await h.wait(0.5)
			hurt = not is_instance_valid(left) or left.currentHealth < left.maxHealth
			if hurt:
				break
		await h.shot("laser_hits")
		h.check("the laser hurts a tentacle", hurt, left.currentHealth if is_instance_valid(left) else -1.0)
		var killed: bool = await h.until(func(): return not is_instance_valid(left) or left.dead, 25.0)
		h.up("ui_left")
		h.up("dome1_fire")
		await h.wait(0.4)
		await h.shot("tentacle_dying")
		h.check("and kills it", killed, left.currentHealth if is_instance_valid(left) else -1.0)

	# ---- a slam hurts the dome
	var hp0: float = float(Data.of("team1.dome.health"))
	var right = fin.alive.filter(func(m): return is_instance_valid(m) and not m.dead)
	if not right.is_empty():
		right[0].next_slam = 0.1
		await h.wait(0.6)
		await h.shot("slam_telegraph")
		await h.wait(0.7)
		await h.burst("slam", 4, 3)
	h.check("a tentacle's slam damages the dome", float(Data.of("team1.dome.health")) < hp0, [hp0, Data.of("team1.dome.health")])
	for m in fin.alive:
		if is_instance_valid(m) and not m.dead:
			m.hit("laser", 99999.0, 0.0)

	# ---- round 2, with the great eye
	var r2: bool = await h.until(func(): return fin.step == "round2", 12.0)
	await h.wait(2.5)
	await h.shot("round2")
	h.check("round 2: three tentacles and the great eye", r2 and fin.living() == 4 and fin.alive.any(func(m): return is_instance_valid(m) and m.great), fin.living())
	for m in fin.alive:
		if is_instance_valid(m) and not m.dead:
			m.hit("laser", 99999.0, 0.0)
			await h.wait(0.5)
	await h.shot("great_eye_dying")

	# ---- the monsters come
	var came: bool = await h.until(func(): return fin.step == "allies", 8.0)
	h.check("after the final blow the surface monsters arrive", came and fin.allies.size() >= 4, fin.allies.size())
	h.check("the battle is over for the dome", Data.of("team1.monsters.wavepresent") == false)
	await h.wait(2.5)
	await h.shot("monsters_arriving")
	await h.wait(3.0)
	await h.shot("final_blows")
	await h.until(func(): return fin.step == "thanks", 6.0)
	for i in BossText.THANKS.size():
		await h.until(func(): return fin.said.size() > i, 6.0)
		await h.wait(1.2)
		await h.shot("thanks_%d" % (i + 1))
	h.check("they thank the keeper, every line", fin.said == BossText.THANKS, fin.said)
	var shown = h.get_tree().get_nodes_in_group("story-plea")
	h.note("thanks on screen", shown.map(func(n): return n.get_meta("line", "")))
	var ed = Level.mode.get_node_or_null("StoryEndings")
	var saved: bool = await h.until(func(): return ed.playing == "saved", 12.0)
	await h.wait(2.0)
	await h.shot("saved_ending")
	h.check("then the saved ending plays", saved and Director.current() == "won", [ed.playing, Director.current()])
