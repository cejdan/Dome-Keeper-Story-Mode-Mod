extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Tickets 163 and 172: the boss music. Logs which layers of the mod's score
# are audible in each stage of the boss sequence (fight phases 1-3, chase, finale),
# that the mining music stays silent meanwhile, and that everything fades when
# the sequence ends. Whether it fits is for a human ear.

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const TIMEOUT := 300


func boot() -> Dictionary:
	# The last chain already broken (#366): the lair seal lets the keeper in.
	return {"seed": 12345, "free": true}


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
	var boss = _Director.instance()
	var m = boss.music
	h.check("no boss music before the fight", m.playing().is_empty(), m.playing())
	# Mining music on, to see it step aside.
	Audio.updateTrackList()
	Audio.startMusic(0)
	await h.wait(1.0)
	h.check("the mining music is playing first", Audio.isMusicPlaying())
	await h.teleport_tile(ch.position + Vector2i(3, 2))
	await h.until(func(): return _Director.current() == "fight", 8.0)
	var velle = boss.velle
	velle.attack_enabled = false
	velle.spawn_bombs = false
	boss.health.invulnerable = 9999.0
	await h.wait(4.0)
	h.note("phase 1", m.playing())
	h.check("phase 1: the fight's first layer alone", m.playing().size() == 1 and _files(m)[0] == "boss_fight_1.ogg", m.playing())
	h.check("the mining music has stepped aside", not Audio.isMusicPlaying())
	velle.phase = 1
	await h.wait(3.0)
	h.note("phase 2", m.playing())
	h.check("phase 2: layer 2 joins", m.playing().size() == 2, m.playing())
	h.check("the score loaded (no missing files)", m.cues["fight"].all(func(p): return p.stream != null), [])
	velle.phase = 2
	await h.wait(3.0)
	h.note("phase 3", m.playing())
	h.check("phase 3: all three layers, full", m.playing().size() == 3 and m.playing().all(func(e): return e["db"] >= -0.5), m.playing())
	var pos: Array = m.cues["fight"].map(func(p): return p.get_playback_position())
	h.check("the three layers are in step", absf(pos[0] - pos[1]) < 0.08 and absf(pos[0] - pos[2]) < 0.08, pos)
	# The chase.
	velle.hp = 0.1
	velle.state = "open"
	velle.lid = 1.0
	_Director.explosion_at(velle.to_global(velle.eye_pos()), "bomb")
	await h.until(func(): return _Director.current() == "chase", 10.0)
	await h.wait(4.0)
	h.note("chase", m.playing())
	h.check("the chase: the chase layers", m.playing().size() >= 1 and _files(m).all(func(f): return f.begins_with("boss_chase")), m.playing())
	# Home: the finale.
	await h.dig_room(Vector2i(-1, 1), Vector2i(1, 9))
	await h.teleport_tile(Vector2i(0, 3))
	h.down("ui_up")
	await h.until(func(): return _Director.current() == "finale", 20.0)
	h.up("ui_up")
	var fin = boss.finale
	# A breath of silence first (#196): the chase music fades out.
	await h.wait(3.0)
	h.note("finale breath", m.playing())
	h.check("the finale opens with a breath of silence", fin.step == "breath" and m.playing().is_empty(), [fin.step, m.playing()])
	await h.until(func(): return fin.step == "rumble", 8.0)
	await h.wait(2.0)
	h.note("finale intro", m.playing())
	h.check("then the bell intro alone", _files(m) == ["boss_finale_intro.ogg"], m.playing())
	await h.until(func(): return fin.step == "round1", 14.0)
	await h.wait(1.0)
	h.note("finale", m.playing())
	h.check("then both finale layers, full", m.cues["finale"].all(func(p): return p.playing and p.volume_db >= -0.5), m.playing())
	# The end: it all fades.
	for round in 2:
		await h.wait(2.0)
		for mon in fin.alive:
			if is_instance_valid(mon) and not mon.dead:
				mon.hit("laser", 99999.0, 0.0)
		await h.until(func(): return fin.step in ["round2", "allies"] and fin.t > 1.6, 12.0)
	await h.until(func(): return _Director.current() == "won", 40.0)
	await h.wait(4.0)
	h.check("when the horror is defeated the boss music fades out", m.playing().is_empty(), m.playing())
