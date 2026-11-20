extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #230 (3/3), client half: the finale for a team, as the client sees it. Its
# keeper takes the dome's weapon (the bells start), draws copies of the host's
# tentacles, flyers and great eye, works the laser on a tentacle (the hits
# count on the host), and sees the eye fall, the monsters' thanks and the
# saved ending.
# Pair: t230_mp_boss_finale_host.

const Director = preload("res://mods-unpacked/cejdan-StoryMode/boss/boss_director.gd")
const Boss = preload("res://mods-unpacked/cejdan-StoryMode/data/boss.gd")
const TIMEOUT := 480

var _held: Dictionary = {}


func boot() -> Dictionary:
	return {"netjoin": true}


func _station(node: Node):
	for c in node.get_children():
		if c is DomeStation:
			return c
		var s = _station(c)
		if s != null:
			return s
	return null


func _hold(h, action: String, on: bool) -> void:
	if on and not _held.get(action, false):
		h.down(action)
	elif not on and _held.get(action, false):
		h.up(action)
	_held[action] = on


func _aim_point(m) -> Vector2:
	var box = m.get_node_or_null("HitboxDefault")
	return m.to_global(box.position) if box != null else m.global_position


func _kinds(fin) -> Dictionary:
	var out: Dictionary = {}
	for m in fin.alive:
		if is_instance_valid(m):
			out[m.techId] = int(out.get(m.techId, 0)) + 1
	return out


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	await shared(h, "finale", 120.0)
	var boss = Director.instance()
	var built: bool = await h.until(func(): return Director.current() == "finale" and boss.finale != null and is_instance_valid(boss.finale), 15.0)
	h.check("the client has a puppet finale", built and boss.finale.puppet)
	if not built:
		return
	var fin = boss.finale
	var k = h.keeper()
	h.check("it opens with the breath; the hearts are put away", fin.step == "breath" and not boss.health.visible, [fin.step, boss.health.visible])

	# ---- take the dome's weapon
	var dome = Level.getDome("team1")
	var st = _station(dome)
	h.check("the client's keeper is in the dome, by the station", st != null and k.isInsideDome, keeper_rows(h))
	if st == null:
		return
	st.useHit(k)
	for i in 14:
		await h.wait(0.5)
		if not GameWorld.paused and k.isInsideStation and i > 0:
			break
		await h.press("ui_left")
	await h.wait(0.5)
	var weapons: Array = st.getControlledWeapons()
	h.check("the client's keeper is at the laser", k.isInsideStation and weapons.size() >= 1, {"station": k.isInsideStation, "weapons": weapons.size(), "activity": fin.activity()})
	var bells: bool = await h.until(func(): return fin.step != "breath", 10.0)
	h.check("the bells start for the client too", bells and boss.music.intro_time() >= 0.0, [fin.step, boss.music.playing()])
	if weapons.is_empty():
		return
	var gun = weapons[0]
	var r1 = await shared(h, "round1", 60.0)
	await h.wait(0.5)
	var ids: Array = fin.alive.filter(func(m): return is_instance_valid(m) and m.techId == "storytentacle").map(func(m): return m.UID)
	ids.sort()
	var want: Array = r1.map(func(v): return int(v)) if r1 != null else []
	want.sort()
	h.check("copies of the host's tentacles, with the host's ids", r1 != null and ids == want and fin.alive.all(func(m): return m.puppet), [ids, want])
	var sync = Level.monstersByTeamId["team1"].monsterSynchronizer
	h.check("they are in the monster synchronizer", ids.all(func(u): return sync.monsters.has(u)), sync.monsters.keys())
	await h.shot("client_round1")

	# ---- work the laser on the tentacles until the host says it felt it
	var t0: float = h.now()
	var hurt = null
	var shot_firing: bool = false
	while h.now() - t0 < 40.0:
		await h.frames(2)
		var have = Data.ofOr(DEV_SHARE, "")
		if have is String and have != "" and JSON.parse_string(have).has("hurt"):
			hurt = JSON.parse_string(have)["hurt"]
			break
		var origin: Vector2 = gun.global_position
		var aim: Vector2 = Vector2.UP.rotated(gun.global_rotation)
		var best = null
		var best_a: float = 99.0
		for m in fin.alive:
			if not is_instance_valid(m) or m.dead or m.invulnerable or m.techId != "storytentacle":
				continue
			var a: float = aim.angle_to(_aim_point(m) - origin)
			if absf(a) < absf(best_a):
				best = m
				best_a = a
		if best == null:
			_hold(h, "ui_left", false)
			_hold(h, "ui_right", false)
			_hold(h, "dome1_fire", false)
		else:
			var off: float = absf(best_a) * origin.distance_to(_aim_point(best))
			_hold(h, "ui_right", best_a > 0.0 and off > 4.0)
			_hold(h, "ui_left", best_a < 0.0 and off > 4.0)
			_hold(h, "dome1_fire", off < 14.0)
		if h.now() - t0 > 3.0 and not shot_firing:
			shot_firing = true
			await h.shot("client_firing")
	for a: String in ["ui_left", "ui_right", "dome1_fire"]:
		_hold(h, a, false)
	h.check("the host felt the client's laser", hurt != null, hurt)
	await h.wait(0.6)
	var copies_lower: bool = false
	for e in (hurt if hurt != null else []):
		var m = sync.monsters.get(int(e[0]))
		if m == null or m.dead or m.currentHealth < float(Data.ofOr("storytentacle.health", 0.0)) - 1.0:
			copies_lower = true
	h.check("and its health came back to the client's copy", copies_lower, [hurt, fin.alive.map(func(m): return [m.UID, m.currentHealth] if is_instance_valid(m) else null)])

	# ---- flyers
	var fl = await shared(h, "flyers", 40.0)
	await h.wait(0.3)
	var kinds: Dictionary = _kinds(fin)
	h.check("the dead tentacles' eyes fly on the client too", int(kinds.get("storyeyeflyer", 0)) > 0, [kinds, fl])
	var tents_dead: bool = fin.alive.all(func(m): return not is_instance_valid(m) or m.techId != "storytentacle" or m.dead)
	h.check("the host's dead tentacles are dead on the client", tents_dead, fin.alive.map(func(m): return [m.techId, m.dead] if is_instance_valid(m) else null))
	await h.shot("client_flyers")

	# ---- the great eye
	var g = await shared(h, "great", 120.0)
	await h.wait(0.6)
	h.check("the great eye rises on the client (the host's id)", g != null and fin.great != null and is_instance_valid(fin.great) and fin.great.UID == int(g), [g, fin.great.UID if fin.great != null else null])
	await h.shot("client_great_eye")
	var fell: bool = await h.until(func(): return fin.great != null and is_instance_valid(fin.great) and fin.great.fallen, 90.0)
	h.check("the great eye falls on the client", fell, [fin.step])
	var allies: bool = await h.until(func(): return not fin.allies.is_empty(), 15.0)
	h.check("the monsters come on the client", allies, fin.allies.size())
	await h.wait(2.0)
	await h.shot("client_allies")
	var thanks: bool = await h.until(func(): return not fin.said.is_empty(), 20.0)
	h.check("and thank the keepers there", thanks, fin.said)
	await h.wait(1.0)
	await h.shot("client_thanks")
	var won: bool = await h.until(func(): return Director.current() == "won", 60.0)
	h.check("the client reads `won`", won, Director.current())
	var ending: bool = await h.until(func(): return Level.mode.get("_ending") == true, 10.0)
	h.check("the saved ending plays on the client", ending)
	await h.wait(3.0)
	await h.shot("client_ending")
	var cards: bool = await h.until(func(): return Level.mode.get_node("StoryEndings").cards_shown >= 1, 20.0)
	h.check("the saved ending's cards come to the client", cards)
	await h.wait(2.0)
	await h.shot("client_cards")
	var panel: bool = await h.until(func(): return Level.stage.endingPanel != null, 120.0)
	h.check("end screen on the client, titled saved", panel and GameWorld.won and Level.stage.endingPanel.titleLabel.text == load("res://mods-unpacked/cejdan-StoryMode/data/endings.gd").SAVED_TITLE, [GameWorld.won, Level.stage.endingPanel.titleLabel.text if panel else null])
	await h.wait(2.5)
	await h.shot("client_end_screen")
	await h.wait(4.0)
	h.check("exactly one set of ending cards and one end screen here", Level.mode.get_node("StoryEndings").cards_shown == 1 and Level.mode.end_screens == 1, [Level.mode.get_node("StoryEndings").cards_shown, Level.mode.end_screens])
