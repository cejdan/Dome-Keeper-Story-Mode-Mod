extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 163: the boss music. Logs which of the game's layered tracks are
# audible in each stage of the boss sequence (fight phases 1-3, chase, finale),
# that the mining music stays silent meanwhile, and that everything fades when
# the sequence ends. Whether it fits is for a human ear.

const Director = preload("res://mods-unpacked/cejdan-StoryMode/boss/boss_director.gd")
const TIMEOUT := 300


func boot() -> Dictionary:
	return {"seed": 12345}


func _files(m) -> Array:
	return m.playing().map(func(e): return e["file"])


func run(h) -> void:
	h.disable_waves()
	var ch: Rect2i = Level.map.tileData.get_meta("story_boss_chamber")
	var area: Array = []
	for y in range(ch.position.y - 3, ch.end.y + 2):
		for x in range(ch.position.x - 2, ch.end.x + 2):
			area.append(Vector2i(x, y))
	await h.reveal(area)
	var boss = Director.instance()
	var m = boss.music
	h.check("no boss music before the fight", m.playing().is_empty(), m.playing())
	# Mining music on, to see it step aside.
	Audio.updateTrackList()
	Audio.startMusic(0)
	await h.wait(1.0)
	h.check("the mining music is playing first", Audio.isMusicPlaying())
	await h.teleport_tile(ch.position + Vector2i(3, 2))
	await h.until(func(): return Director.current() == "fight", 8.0)
	var velle = boss.velle
	velle.attack_enabled = false
	velle.spawn_bombs = false
	boss.health.invulnerable = 9999.0
	await h.wait(4.0)
	h.note("phase 1", m.playing())
	h.check("phase 1: final-wave layer 1 alone", m.playing().size() == 1 and "1" in _files(m)[0], m.playing())
	h.check("the mining music has stepped aside", not Audio.isMusicPlaying())
	velle.phase = 1
	await h.wait(3.0)
	h.note("phase 2", m.playing())
	h.check("phase 2: layer 2 joins", m.playing().size() == 2, m.playing())
	velle.phase = 2
	await h.wait(3.0)
	h.note("phase 3", m.playing())
	h.check("phase 3: both layers full and faster", m.playing().all(func(e): return e["db"] >= -0.5 and e["pitch"] > 1.0), m.playing())
	var p0: float = m.players[0].get_playback_position()
	var p1: float = m.players[1].get_playback_position()
	h.check("the two layers are in step", absf(p0 - p1) < 0.08, [p0, p1])
	# The chase.
	velle.hp = 0.1
	velle.state = "open"
	velle.lid = 1.0
	Director.explosion_at(velle.to_global(velle.eye_pos()), "bomb")
	await h.until(func(): return Director.current() == "chase", 10.0)
	await h.wait(4.0)
	h.note("chase", m.playing())
	h.check("the chase: the relic-retrieval layers", m.playing().size() >= 1 and _files(m).all(func(f): return "elic" in f), m.playing())
	# Home: the finale.
	await h.dig_room(Vector2i(-1, 1), Vector2i(1, 9))
	await h.teleport_tile(Vector2i(0, 3))
	h.down("ui_up")
	await h.until(func(): return Director.current() == "finale", 20.0)
	h.up("ui_up")
	await h.wait(4.0)
	h.note("finale", m.playing())
	h.check("the finale: both final-wave layers", m.playing().size() == 2 and _files(m).all(func(f): return not ("elic" in f)), m.playing())
	h.note("music set", m.set_id)
	# The end: it all fades.
	var fin = boss.finale
	await h.until(func(): return fin.step == "round1", 6.0)
	for round in 2:
		await h.wait(2.0)
		for mon in fin.alive:
			if is_instance_valid(mon) and not mon.dead:
				mon.hit("laser", 99999.0, 0.0)
		await h.until(func(): return fin.step in ["round2", "allies"] and fin.t > 1.6, 12.0)
	await h.until(func(): return Director.current() == "won", 40.0)
	await h.wait(4.0)
	h.check("when the horror is defeated the boss music fades out", m.playing().is_empty(), m.playing())
