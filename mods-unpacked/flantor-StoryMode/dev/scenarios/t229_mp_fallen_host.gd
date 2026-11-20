extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #229: host half. The team falls to Velle (the boss's lost ending, #162): the
# host's game mode node plays it and sends it to the client, so both see the
# fallen cards once and the "fallen" end screen once. Pair: t229_mp_fallen_client.

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const Awakening = preload("res://mods-unpacked/flantor-StoryMode/beats/awakening.gd")
const BossText = preload("res://mods-unpacked/flantor-StoryMode/data/boss_text.gd")
const TIMEOUT := 360


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if not await host_start(h):
		return
	await h.wait(2.0)
	var boss = _Director.instance()
	h.check("boss director on the host", boss != null)
	if boss == null:
		return
	var dev = load("res://mods-unpacked/flantor-StoryMode/dev/boss_dev.gd")
	dev.give_gear()   # every keeper's gear, Heat Shielding IV too (#265)
	var ch: Rect2i = Level.map.tileData.get_meta("story_boss_chamber")
	var cells: Array = []
	for y in range(ch.position.y - 3, ch.end.y + 2):
		for x in range(ch.position.x - 2, ch.end.x + 2):
			cells.append(Vector2i(x, y))
	await h.reveal(cells)
	Data.apply("team1.story.beatsplayed", str(Data.ofOr("team1.story.beatsplayed", "")) + ",boss_chamber")
	Data.apply(Awakening.AWAKE, true)
	await h.wait(1.0)
	await h.teleport_tile(ch.position + Vector2i(3, 2))
	var started: bool = await h.until(func(): return _Director.current() == "fight", 40.0)
	h.check("the fight starts", started, _Director.current())
	if not started:
		return
	await h.wait(3.0)
	share("fight", true)
	await h.wait(1.0)
	# The team's hearts run out.
	boss._keeper_died("playtest")
	var lost: bool = await h.until(func(): return _Director.current() == "lost" and Level.mode.is_ending(), 10.0)
	h.check("the boss state is `lost` and the lost ending plays on the host", lost, _Director.current())
	var endings = Level.mode.get_node("StoryEndings")
	var cards: bool = await h.until(func(): return endings.cards_shown >= 1, 20.0)
	h.check("the fallen cards on the host", cards and endings.playing == "fallen", endings.playing)
	await h.wait(2.0)
	await h.shot("host_fallen_cards")
	var panel: bool = await h.until(func(): return Level.stage.endingPanel != null, 120.0)
	h.check("the fallen end screen on the host", panel and GameWorld.lost and Level.stage.endingPanel.titleLabel.text == BossText.FALLEN_TITLE, [GameWorld.lost, Level.stage.endingPanel.titleLabel.text if panel else null])
	await h.wait(2.5)
	await h.shot("host_fallen_end")
	await h.wait(4.0)
	h.check("exactly one set of ending cards and one end screen here", endings.cards_shown == 1 and Level.mode.end_screens == 1, [endings.cards_shown, Level.mode.end_screens])
	await host_wait_clients_left(h, 120.0)
