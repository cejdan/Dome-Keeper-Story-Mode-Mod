extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Tickets 162, 171 and 173: the final battle on the surface. Starts with the
# keeper in the dome, sees the ground crack and the tentacles break out with
# four eyes each, sees eyes tear free of living tentacles and shoot the dome,
# shoots a tentacle dead with the real laser from the station with real input
# (its last eyes die with it), sees a slam hurt the dome, plays all three
# rounds, the great eye straight above the dome with its gaze (fired, and
# broken), sees it close when beaten and stay up until the rest is dead, then
# sway and crash down on one side of the dome, and watches the monsters arrive
# from that side only, finish the horror and thank the keeper in runes. Then
# the saved ending starts.

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const BossText = preload("res://mods-unpacked/flantor-StoryMode/data/boss_text.gd")
const Boss = preload("res://mods-unpacked/flantor-StoryMode/data/boss.gd")
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


# Kills everything alive, flyers set free along the way included.
func _kill_all(h, fin) -> void:
	for pass_i in 12:
		var any: bool = false
		for m in fin.alive:
			if is_instance_valid(m) and not m.dead and not m.invulnerable:
				m.hit("laser", 99999.0, 0.0)
				any = true
		await h.wait(0.4)
		if not any and fin.living() == 0:
			break


func run(h) -> void:
	h.disable_waves()
	await h.wait(1.0)
	var boss = _Director.instance()
	var dome = Level.getDome("team1")
	var k = h.keeper()
	h.check("the keeper starts in the dome", k.isInsideDome)
	# Jump to the end of the chase.
	boss._ensure_layer()
	# The dome of a keeper who got this far, with Laser III: this checks how the
	# battle works, not its balance (t171_finale_laser4), and Laser IV barely
	# moves while firing, which the swing to a tentacle below needs.
	load("res://mods-unpacked/flantor-StoryMode/dev/boss_dev.gd").give_gear([], 3)
	await h.frames(5)
	boss._stop_waves()
	boss._set_state("finale")
	boss._start_finale()
	var started: bool = await h.until(func(): return _Director.current() == "finale", 5.0)
	h.check("the finale starts", started, _Director.current())
	if not started:
		return
	var fin = boss.finale
	var Tentacle = load("res://mods-unpacked/flantor-StoryMode/boss/surface_tentacle.gd")
	var Flyer = load("res://mods-unpacked/flantor-StoryMode/boss/eye_flyer.gd")
	h.check("the hearts are put away: the keeper is home", not boss.health.visible)
	# A breath of silence (#196); the keeper stands idle, so the bells come
	# after Boss.FINALE_BREATH seconds.
	await h.until(func(): return fin.step == "rumble", Boss.FINALE_BREATH + 4.0)
	await h.wait(1.0)
	await h.shot("ground_cracking_early")
	await h.wait(7.0)
	await h.shot("ground_cracking_late")
	# The first cracking lasts the music's bell intro (#172), about 9.7 s.
	await h.until(func(): return fin.step == "round1", 14.0)
	await h.burst("breaking_out", 8, 3)
	await h.wait(1.2)
	await h.shot("round1")
	h.check("round 1: two tentacles beside the dome", fin.living() == 2, fin.living())
	h.check("they are real monster targets", fin.alive.all(func(m): return m is Monster and m.is_in_group("monster") and m.collision_layer == 128))
	h.check("the dome is at battle stations", Data.of("team1.monsters.wavepresent") == true)
	h.check("health is fixed, not scaled to the run", fin.alive.all(func(m): return m.maxHealth == Boss.FINALE_TENTACLE_HP), fin.alive.map(func(m): return m.maxHealth))
	h.check("the broken ground keeps its cracks and rubble", fin.alive.all(func(m): return m._cracks.size() >= 7 and m.debris.size() > 10))
	h.check("each comes up with %d eyes" % Boss.FINALE_TENTACLE_EYES, fin.alive.all(func(m): return m.eyes_left == Boss.FINALE_TENTACLE_EYES) and fin.flyers_made == 0, fin.alive.map(func(m): return m.eyes_left))

	# ---- eyes tear free of living tentacles, one every few seconds
	var tents: Array = fin.alive.duplicate()
	await h.until(func(): return tents[0].pop_t > Boss.FINALE_EYE_POP_EVERY - 0.4, 8.0)
	await h.shot("eye_about_to_tear_free")
	var popped: bool = await h.until(func(): return fin.flyers_made >= 2, 4.0)
	await h.burst("eyes_tear_free", 4, 6)
	h.check("after %.0f s the first eye tears free of each living tentacle" % Boss.FINALE_EYE_POP_EVERY,
		popped and tents.all(func(m): return not m.dead and m.eyes_left == Boss.FINALE_TENTACLE_EYES - 1) and fin.flyers_alive() == 2, [fin.flyers_made, fin.living()])
	h.check("ground and sky at once: two tentacles and two flyers", fin.living() == 4, fin.living())
	await h.until(func(): return fin.flyers_made >= 4, 7.0)
	await h.wait(0.6)
	await h.shot("second_eyes_free")
	h.check("%.0f s later the second" % Boss.FINALE_EYE_POP_EVERY, fin.flyers_made == 4 and tents.all(func(m): return m.eyes_left == Boss.FINALE_TENTACLE_EYES - 2), fin.flyers_made)
	# Hold the rest back so the checks below are steady.
	for m in tents:
		m.pop_t = -9999.0

	# ---- the flyers shoot the dome
	var flyer = fin.alive.filter(func(m): return is_instance_valid(m) and m.techId == Flyer.TECH)[0]
	h.check("a flyer is a real monster target too", flyer is Monster and flyer.is_in_group("monster") and flyer.maxHealth == Boss.FINALE_FLYER_HP, flyer.maxHealth)
	for m in tents:
		m.next_slam = 99.0
	var hp0: float = float(Data.of("team1.dome.health"))
	var hits0: int = flyer.hits
	var shot: bool = await h.until(func(): return flyer.hits > hits0, 12.0)
	await h.frames(3)
	await h.shot("flyers_over_the_dome")
	h.check("it hovers above the dome", flyer.global_position.y < dome.global_position.y - 60.0, flyer.global_position - dome.global_position)
	h.check("its bolts hurt the dome", shot and float(Data.of("team1.dome.health")) < hp0, [hp0, Data.of("team1.dome.health")])

	# ---- the real laser, real input
	var st = _station(dome)
	h.check("the dome has a weapon station", st != null)
	var left = tents.filter(func(m): return m.global_position.x < dome.global_position.x)[0]
	if st != null:
		st.useHit(k)
		await h.wait(2.5)
		h.note("in station", {"keeper_in_station": k.isInsideStation, "weapons": st.getControlledWeapons().size()})
		var hurt: bool = false
		for i in 30:
			# Key-down events are edges; send them again in case the station's
			# input was not listening yet. (The first "left" also picks Battle
			# in the station's menu.)
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
		var made: int = fin.flyers_made
		var left_eyes: int = left.eyes_left if is_instance_valid(left) else 0
		var left_ref: WeakRef = weakref(left)
		var killed: bool = await h.until(func(): return left_ref.get_ref() == null or left_ref.get_ref().dead, 25.0)
		h.up("ui_left")
		h.up("dome1_fire")
		await h.burst("tentacle_dies", 4, 6)
		h.check("and kills it", killed, left.currentHealth if is_instance_valid(left) else -1.0)
		await h.wait(1.5)
		h.check("a dead tentacle's last %d eyes all tear free at once" % left_eyes, left_eyes > 0 and fin.flyers_made == made + left_eyes, [made, left_eyes, fin.flyers_made])

	# ---- a slam hurts the dome
	hp0 = float(Data.of("team1.dome.health"))
	var right = fin.alive.filter(func(m): return is_instance_valid(m) and not m.dead and m.techId == Tentacle.TECH)
	if not right.is_empty():
		right[0].next_slam = 0.1
		await h.wait(0.6)
		await h.shot("slam_telegraph")
		await h.wait(0.7)
		await h.burst("slam", 4, 3)
	h.check("a tentacle's slam damages the dome", float(Data.of("team1.dome.health")) < hp0, [hp0, Data.of("team1.dome.health")])

	# ---- a round only ends when the flyers are dead too
	right[0].hit("laser", 99999.0, 0.0)
	await h.wait(2.5)
	h.check("with both tentacles dead the round goes on: the flyers are left", fin.step == "round1" and fin.flyers_alive() >= 1 and fin.living() == fin.flyers_alive(), [fin.step, fin.living()])
	await _kill_all(h, fin)
	var lull: bool = await h.until(func(): return fin.step == "lull", 6.0)
	h.check("then the ground starts to crack again", lull, fin.step)

	# ---- round 2, round 3 with the great eye
	var r2: bool = await h.until(func(): return fin.step == "round2", 8.0)
	await h.wait(1.6)
	await h.shot("round2")
	h.check("round 2: three tentacles", r2 and fin.living() == 3, fin.living())
	await _kill_all(h, fin)
	var r3: bool = await h.until(func(): return fin.step == "round3", 12.0)
	await h.burst("great_eye_rising", 8, 6)
	await h.wait(1.2)
	await h.shot("round3")
	var eye = fin.great
	h.check("round 3: three tentacles and the great eye", r3 and fin.living() == 4 and is_instance_valid(eye), fin.living())
	h.check("the great eye has %d health" % Boss.FINALE_EYE_HP, eye.maxHealth == Boss.FINALE_EYE_HP)
	h.check("it hangs straight above the dome", absf(eye.global_position.x - dome.global_position.x) < 16.0 and eye.global_position.y < dome.global_position.y - 100.0, eye.global_position - dome.global_position)
	h.check("its stalk is drawn behind the dome, and only the eye is a target", eye.stalk.z_index < dome.z_index and not eye.stalk.z_as_relative and eye.get_node("HitboxDefault").shape is CircleShape2D, eye.stalk.z_index)
	for m in fin.alive:
		if is_instance_valid(m) and not m.dead and m != eye:
			m.next_slam = 99.0
			m.pop_t = -9999.0

	# ---- the pound
	hp0 = float(Data.of("team1.dome.health"))
	eye.attacks_done = 0
	eye.next_slam = 0.05
	await h.until(func(): return eye.slam_t >= 0.6, 3.0)
	await h.shot("pound_telegraph")
	await h.until(func(): return eye.slams == 1, 3.0)
	await h.burst("pound", 3, 3)
	h.check("the great eye pounds the dome", eye.slams == 1 and float(Data.of("team1.dome.health")) < hp0, [hp0, Data.of("team1.dome.health")])
	await h.until(func(): return eye.slam_t < 0.0, 3.0)

	# ---- the gaze: it burns the dome unless it is hurt enough while charging
	eye.attacks_done = 1
	eye.next_slam = 0.05
	await h.until(func(): return eye.gaze_t >= 0.0, 3.0)
	await h.wait(1.5)
	await h.shot("gaze_charging")
	hp0 = float(Data.of("team1.dome.health"))
	await h.until(func(): return eye.gazes_fired == 1, 4.0)
	await h.burst("gaze_fires", 3, 6)
	h.check("left alone, the gaze burns the dome", eye.gazes_fired == 1 and float(Data.of("team1.dome.health")) < hp0, [hp0, Data.of("team1.dome.health")])
	await h.until(func(): return eye.gaze_t < 0.0, 3.0)
	eye.attacks_done = 1
	eye.next_slam = 0.05
	await h.until(func(): return eye.gaze_t >= 0.0, 3.0)
	await h.wait(1.0)
	eye.hit("laser", eye.maxHealth * Boss.FINALE_GAZE_BREAK * 0.6, 0.0)
	await h.wait(0.3)
	await h.shot("gaze_half_broken")
	h.check("some damage is not enough: it keeps charging", eye.gaze_t >= 0.0 and eye.gaze_broken_share() > 0.5 and eye.gaze_broken_share() < 1.0, eye.gaze_broken_share())
	eye.hit("laser", eye.maxHealth * Boss.FINALE_GAZE_BREAK * 0.5, 0.0)
	await h.wait(0.3)
	await h.shot("gaze_broken_flinch")
	hp0 = float(Data.of("team1.dome.health"))
	eye.next_slam = 99.0
	await h.wait(2.5)
	h.check("enough damage while it charges makes it flinch and lose the shot", eye.gazes_broken == 1 and eye.gazes_fired == 1 and float(Data.of("team1.dome.health")) == hp0, [eye.gazes_broken, eye.gazes_fired])

	# ---- fury
	h.note("fury", {"battle seconds": snappedf(fin.fight_t, 0.1), "waits are now this share of the listed times": snappedf(fin.fury, 0.01)})
	h.check("the longer the battle, the faster they strike", fin.fury < 1.0 and fin.alive.all(func(m): return not is_instance_valid(m) or m.dead or m.fury == fin.fury), fin.fury)

	# ---- beaten, the great eye closes and waits for the rest to die
	eye.hit("laser", 99999.0, 0.0)
	await h.wait(1.5)
	await h.shot("great_eye_closed")
	h.check("beaten, the great eye closes but stays up", is_instance_valid(eye) and eye.dead and not eye.is_in_group("monster") and eye.fall_t < 0.0 and eye.global_position.y < dome.global_position.y - 100.0)
	h.check("the round goes on while anything else lives", fin.step == "round3" and fin.living() == 3, [fin.step, fin.living()])
	hp0 = float(Data.of("team1.dome.health"))
	await h.wait(2.0)
	h.check("a closed eye does nothing to the dome", float(Data.of("team1.dome.health")) == hp0 and eye.slam_t < 0.0 and eye.gaze_t < 0.0)
	await _kill_all(h, fin)

	# ---- then it sways and falls beside the dome
	var falling: bool = await h.until(func(): return fin.step == "fall", 6.0)
	h.check("with everything else dead, the great eye starts to go", falling and eye.fall_t >= 0.0, fin.step)
	h.check("the battle is over for the dome", Data.of("team1.monsters.wavepresent") == false)
	await h.burst("great_eye_sways", 6, 18)
	await h.until(func(): return eye.fall_t >= eye.FALL_SWAY, 4.0)
	await h.burst("great_eye_falls", 10, 6)
	var down: bool = await h.until(func(): return eye.fallen, 4.0)
	await h.burst("great_eye_crash", 4, 5)
	var off: Vector2 = eye.global_position - dome.global_position
	h.note("the fall", {"side": fin.fall_side, "lands at (from the dome)": off})
	h.check("it crashes to the ground on one side of the dome", down and off.x * fin.fall_side > 110.0 and off.y > -40.0, off)

	# ---- the monsters come, from that side only
	var came: bool = await h.until(func(): return fin.step == "allies", 8.0)
	h.check("then the surface monsters arrive", came and fin.allies.size() >= 4, fin.allies.size())
	var dx: float = dome.global_position.x
	var walkers: Array = fin.allies.filter(func(a): return not a["flies"])
	var fliers: Array = fin.allies.filter(func(a): return a["flies"])
	h.check("the ground monsters all come from the side the eye fell to, and stop short of the dome",
		walkers.size() >= 3 and walkers.all(func(a): return (a["from"].x - dx) * fin.fall_side > 150.0 and (a["stand"].x - dx) * fin.fall_side > 60.0),
		walkers.map(func(a): return [a["from"].x - dx, a["stand"].x - dx]))
	h.check("the flyers come from above or from that side",
		fliers.size() >= 2 and fliers.any(func(a): return a["from"].y < a["stand"].y - 200.0) and fliers.all(func(a): return (a["from"].x - dx) * fin.fall_side > 60.0),
		fliers.map(func(a): return a["from"] - dome.global_position))
	await h.wait(1.5)
	await h.shot("monsters_arriving")
	var crossed: bool = false
	for i in 40:
		await h.wait(0.1)
		for a: Dictionary in fin.allies:
			if is_instance_valid(a["node"]) and (a["node"].global_position.x - dx) * fin.fall_side < 50.0:
				crossed = true
	h.check("nobody crosses the dome", not crossed)
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
	# Since #368 the saved ending waits for a keeper to board the ship by the dome.
	var Ship = load("res://mods-unpacked/flantor-StoryMode/endgame/ship.gd")
	var home: bool = await h.until(func(): return Ship.phase() == "home", 12.0)
	h.check("the battle won: the ship by the dome is the way home", home, Ship.phase())
	await h.wait(1.0)
	await h.shot("ship_home")
	h.check("a keeper boards it", Level.mode.board_ship(h.keeper().playerId))
	var saved: bool = await h.until(func(): return ed.playing == "saved", 16.0)
	await h.wait(2.0)
	await h.shot("saved_ending")
	h.check("then the saved ending plays", saved and _Director.current() == "won", [ed.playing, _Director.current()])
