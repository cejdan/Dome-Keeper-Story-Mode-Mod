extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 162: the lost ending. The keeper runs out of hearts in Velle's
# chamber: the run ends in failure with the fallen cards and the end screen
# "The Planet Is Lost" as a lost run.

const Director = preload("res://mods-unpacked/cejdan-StoryMode/boss/boss_director.gd")
const BossText = preload("res://mods-unpacked/cejdan-StoryMode/data/boss_text.gd")
const Boss = preload("res://mods-unpacked/cejdan-StoryMode/data/boss.gd")
const TIMEOUT := 300


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	var ch: Rect2i = Level.map.tileData.get_meta("story_boss_chamber")
	var area: Array = []
	for y in range(ch.position.y - 3, ch.end.y + 2):
		for x in range(ch.position.x - 2, ch.end.x + 2):
			area.append(Vector2i(x, y))
	await h.reveal(area)
	await h.teleport_tile(ch.position + Vector2i(3, 2))
	await h.until(func(): return Director.current() == "fight", 8.0)
	var boss = Director.instance()
	var velle = boss.velle
	var health = boss.health
	await h.until(func(): return velle.state == "fight", 8.0)
	await h.wait(1.5)
	# Sit on Velle until the hearts run out.
	for i in Boss.HEARTS + 2:
		if health.dead:
			break
		h.keeper().global_position = velle.to_global(velle.base + Vector2(0, -30))
		await h.wait(Boss.HURT_INVULNERABLE + 0.3)
		if i == Boss.HEARTS - 2:
			await h.shot("last_heart")
	h.check("five hits and the keeper is dead", health.dead and health.hearts() == 0, health.hearts())
	h.check("the boss sequence is lost", Director.current() == "lost", Director.current())
	await h.wait(0.6)
	await h.shot("keeper_down")
	h.check("Velle stops attacking", velle.orbs.is_empty() and velle.attacks.is_empty())
	var ed = Level.mode.get_node_or_null("StoryEndings")
	await h.until(func(): return ed.playing == "fallen" and ed.last_step == "cards", 10.0)
	var seen: Array = []
	var t_end: float = h.now() + 60.0
	while h.now() < t_end and ed.last_step == "cards":
		var box = h.beat_box()
		if box != null and box.get("cards") != null and box.current_card() != "" and not seen.has(box.current_card()):
			await h.wait(1.2)
			seen.append(box.current_card())
			await h.shot("card_%d" % seen.size())
		await h.wait(0.2)
	h.check("every fallen card shows", seen == BossText.FALLEN_CARDS, seen)
	await h.until(func(): return Level.stage.endingPanel != null, 20.0)
	await h.wait(3.0)
	var panel = Level.stage.endingPanel
	await h.shot("end_screen")
	h.check("the end screen reads \"%s\"" % BossText.FALLEN_TITLE, panel != null and panel.titleLabel.text == BossText.FALLEN_TITLE, panel.titleLabel.text if panel != null else "")
	h.check("the run is recorded as lost, not won", GameWorld.lost and not GameWorld.won)
