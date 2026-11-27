extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t368_land.gd"

# #368: the ship after the fight (huge map, seed 12345, every chain broken
# quietly: `free`). Velle's body is dead and the final dome battle is on
# (the boss state "finale"): the ship is locked. The tube is folded away,
# the hatch is red, the prompt shows a padlock and the locked line; holding
# the use key buzzes, the keeper says the locked line and nothing boards.
# The final battle won (the director's own finale_done -> "won"): the hatch
# opens (a chime), the tube comes out, and holding the use key at the hatch
# is the way home: the lift-off, then the saved ending's cards (the fourth
# a [DRAFT] in place of the "scheduled pickup") and the end screen "The
# Planet Is Saved". A won run.

const Endings = preload("res://mods-unpacked/flantor-StoryMode/data/endings.gd")
const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")


func boot() -> Dictionary:
	return {"seed": 12345, "free": true}


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	var ok: bool = await h.until(func(): return _Ship.find() != null and h.keeper() != null, 30.0)
	if not h.check("the run has a ship", ok):
		return
	ship = _Ship.find()
	h.disable_waves()
	await h.until(func(): return ship.mode == "dome", 5.0)
	h.check("every chain broken quietly: the ship stands at the dome from the start", ship.mode == "dome" and _EndGame.is_free(), [ship.mode, _EndGame.state()])
	var k = h.keeper()
	var boss = Level.mode.get_node_or_null("StoryBoss")
	# ---- the final dome battle on: locked
	Data.apply(Story.BOSS_STATE, "finale")
	await h.wait(1.0)
	h.check("during the final dome battle the ship is locked", _Ship.phase() == "locked" and _Ship.board_kind() == "", _Ship.phase())
	h.check("its tube folded away", ship.tube_ext < 0.05, ship.tube_ext)
	await go_home(h, k)
	var got: bool = await walk_to_hatch(h, k)
	h.check("the hatch still takes the keeper's focus (to say it's locked)", got and ship._prompt.visible, [str(k.focussedUsable), ship._prompt.visible])
	await h.shot("locked_prompt")
	h.down("ui_select")
	await h.wait(1.8)
	var lines: Array = h.get_tree().get_nodes_in_group("story-ship-line").map(func(n): return n.get_meta("text"))
	await h.shot("locked_line")
	h.up("ui_select")
	h.check("holding the use key: the keeper says the locked line", lines.has(Endings.SHIP_LOCKED), lines)
	h.check("with the denied buzz", int(Sfx.played.get("ship_denied", 0)) >= 1, Sfx.played)
	h.check("and nothing boards", ship.mode == "dome" and not Level.mode.is_ending() and not _Ship.events.any(func(e): return e["what"] == "board_asked"), [ship.mode, _Ship.events])
	h.check("the host refuses it even if asked", not Level.mode.board_ship(k.playerId), Level.mode.is_ending())
	# ---- the final battle won
	boss._finale_done()
	await h.until(func(): return _Director.current() == "won", 3.0)
	var home: bool = await h.until(func(): return _Ship.phase() == "home" and ship.tube_ext > 0.95, 4.0)
	h.check("the battle won: the hatch opens, the tube comes out (the way home)", home and _Ship.board_kind() == "saved", [_Ship.phase(), ship.tube_ext])
	h.check("with a chime", int(Sfx.played.get("ship_ready", 0)) == 1, Sfx.played)
	h.check("and the saved ending waits for a keeper to board", not Level.mode.is_ending() and not GameWorld.won, Level.mode.is_ending())
	await h.wait(2.5)
	h.check("still waiting a few seconds on", not Level.mode.is_ending(), Level.mode.is_ending())
	await h.shot("home_prompt")
	h.down("ui_select")
	var lifting: bool = await h.until(func(): return ship.mode == "lifting", 3.0)
	h.up("ui_select")
	h.check("holding the use key boards: the lift-off", lifting, ship.mode)
	await h.until(func(): return ship._lift_t >= 3.4, 6.0)
	await h.shot("home_liftoff")
	await h.until(func(): return ship.mode == "gone", 8.0)
	var ed = Level.mode.get_node_or_null("StoryEndings")
	await h.until(func(): return ed.last_step == "cards", 6.0)
	var seen: Array = []
	var t_end: float = h.now() + 50.0
	while h.now() < t_end and ed.last_step == "cards":
		var box = h.beat_box()
		if box != null and box.get("cards") != null and box.current_card() != "" and not seen.has(box.current_card()):
			await h.wait(1.0)
			seen.append(box.current_card())
			await h.shot("card_%d" % seen.size())
		await h.wait(0.2)
	h.check("the saved cards, the draft line in place of the scheduled pickup", seen == Endings.SAVED_CARDS and str(seen[3]).begins_with("[DRAFT] "), seen)
	await h.until(func(): return Level.stage.endingPanel != null, 15.0)
	await h.wait(3.0)
	var panel = Level.stage.endingPanel
	await h.shot("end_screen")
	h.check("the end screen reads \"%s\"" % Endings.SAVED_TITLE, panel != null and panel.titleLabel.text == Endings.SAVED_TITLE, panel.titleLabel.text if panel != null else null)
	h.check("the run is won", GameWorld.won, GameWorld.won)
