extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #229: client half. The host's team falls to Velle: the lost ending reaches
# this client from the host's game mode node, once (cards, then the "fallen"
# end screen). Pair: t229_mp_fallen_host.

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const BossText = preload("res://mods-unpacked/flantor-StoryMode/data/boss_text.gd")
const TIMEOUT := 360


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	h.check("the host's fight is on", await shared(h, "fight", 150.0) != null)
	var lost: bool = await h.until(func(): return _Director.current() == "lost", 20.0)
	h.check("the client reads `lost`", lost, _Director.current())
	var ending: bool = await h.until(func(): return Level.mode.is_ending(), 10.0)
	h.check("the lost ending starts on the client", ending)
	var endings = Level.mode.get_node("StoryEndings")
	var cards: bool = await h.until(func(): return endings.cards_shown >= 1, 20.0)
	h.check("the fallen cards come to the client", cards)
	await h.wait(2.0)
	await h.shot("client_fallen_cards")
	var panel: bool = await h.until(func(): return Level.stage.endingPanel != null, 120.0)
	h.check("the fallen end screen on the client", panel and GameWorld.lost and Level.stage.endingPanel.titleLabel.text == BossText.FALLEN_TITLE, [GameWorld.lost, Level.stage.endingPanel.titleLabel.text if panel else null])
	await h.wait(2.5)
	await h.shot("client_fallen_end")
	await h.wait(4.0)
	h.check("exactly one set of ending cards and one end screen here", endings.cards_shown == 1 and Level.mode.end_screens == 1, [endings.cards_shown, Level.mode.end_screens])
