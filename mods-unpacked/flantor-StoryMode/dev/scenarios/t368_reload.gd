extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t368_land.gd"

# #368: after a reload the ship is simply at the dome, and boarding it before
# the fight is the escape: the doom ending. Loads slot 68 (t368_land: the
# last chain broken, nobody in the lair) in a fresh process. The ship stands
# at the dome from the start (no sink, no rise, no live moment). The keeper
# walks to the hatch by real input: a tap of the use key only nudges the
# prompt; holding it boards. The lift-off plays (the keeper through the tube,
# the nose shuts, the engines, the climb; shots), then the doom ending: the
# horror's thanks (doom_thanks), the monsters' last words, the cards, the end
# screen "The Planet Is Lost". A won run. Fill Quota is still in the shop,
# out of reach.

const Endings = preload("res://mods-unpacked/flantor-StoryMode/data/endings.gd")


func boot() -> Dictionary:
	return {"load": LAND_SLOT, "beats": true}


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	var ok: bool = await h.until(func(): return _Ship.find() != null and h.keeper() != null, 30.0)
	if not h.check("the loaded run has a ship", ok):
		return
	ship = _Ship.find()
	h.disable_waves()
	await h.until(func(): return ship.mode == "dome", 5.0)
	var k = h.keeper()
	var whats: Array = _Ship.events.map(func(e): return e["what"])
	h.check("after the load it is simply at the dome (no sink, no rise, nothing live)", ship.mode == "dome" and not whats.has("rise") and not whats.has("free_live")
		and _Ship.events.filter(func(e): return e["what"] == "landed").all(func(e): return e["live"] == false), _Ship.events)
	h.check("the end-game state came back: free, nobody in the lair", _EndGame.is_free() and not _EndGame.is_lair_entered(), _EndGame.state())
	h.check("and the ocean's coil is gone", not ship.ocean.visible and ship._sink_t < 0.0, ship.ocean.visible)
	var entry: Dictionary = GameWorld.upgrades.get("team1.storyretirerich", {})
	h.check("Fill Quota is still in the shop, at $25,000,000", int(entry.get("cost", {}).get("money", 0)) == 25000000, entry.get("cost", {}))
	# The save was made with beats muted (t368_land): the doom ending's own
	# beat is unplayed in a real run.
	var played: Array = Array(str(Data.ofOr("team1.story.beatsplayed", "")).split(",", false))
	played.erase("doom_thanks")
	Data.apply("team1.story.beatsplayed", ",".join(PackedStringArray(played)))
	await go_home(h, k)
	_check_at_dome(h, k)
	var got: bool = await walk_to_hatch(h, k)
	h.check("the keeper walks to the hatch: focus and prompt", got and ship._prompt.visible, [str(k.focussedUsable), k.global_position - dome().global_position])
	await h.shot("prompt")
	# A tap only nudges.
	await h.press("ui_select")
	await h.wait(0.6)
	h.check("a tap of the use key doesn't board (the prompt nudges)", ship.mode == "dome" and not Level.mode.is_ending(), ship.mode)
	# Hold to board.
	h.down("ui_select")
	await h.wait(0.7)
	await h.shot("holding")
	var lifting: bool = await h.until(func(): return ship.mode == "lifting", 3.0)
	h.up("ui_select")
	h.check("holding the use key boards: the lift-off starts and play stops", lifting and Level.mode.is_ending(), [ship.mode, Level.mode.is_ending()])
	h.check("boarding asked once, by this keeper", _Ship.events.filter(func(e): return e["what"] == "board_asked").size() == 1, _Ship.events)
	for st in [[0.45, "liftoff_walk"], [1.3, "liftoff_shut"], [2.3, "liftoff_engines"], [3.6, "liftoff_rising"], [4.6, "liftoff_climb"], [5.6, "liftoff_away"]]:
		await h.until(func(): return ship._lift_t >= float(st[0]) or ship.mode == "gone", 8.0)
		await h.shot(str(st[1]))
	var gone: bool = await h.until(func(): return ship.mode == "gone", 8.0)
	h.check("the ship climbs out of sight", gone and not ship.carrier.visible, ship.mode)
	h.check("the keeper went aboard (faded out)", k.modulate.a < 0.05, k.modulate.a)
	h.check("with its sounds", int(Sfx.played.get("ship_door_close", 0)) >= 1 and int(Sfx.played.get("ship_liftoff", 0)) == 1, Sfx.played)
	# The doom ending.
	var ed = Level.mode.get_node_or_null("StoryEndings")
	var id: String = await h.read_beat("thanks", 10.0)
	h.check("the horror thanks the keeper (doom_thanks)", id == "doom_thanks", id)
	await h.until(func(): return ed.last_step == "last_words", 6.0)
	await h.wait(1.4)
	await h.shot("last_words")
	await h.until(func(): return ed.last_step == "cards", 15.0)
	var seen: Array = []
	var t_end: float = h.now() + 40.0
	while h.now() < t_end and ed.last_step == "cards":
		var box = h.beat_box()
		if box != null and box.get("cards") != null and box.current_card() != "" and not seen.has(box.current_card()):
			await h.wait(1.0)
			seen.append(box.current_card())
			await h.shot("card_%d" % seen.size())
		await h.wait(0.2)
	h.check("the doom cards", seen == Endings.DOOM_CARDS, seen)
	await h.until(func(): return Level.stage.endingPanel != null, 15.0)
	await h.wait(3.0)
	var panel = Level.stage.endingPanel
	await h.shot("end_screen")
	h.check("the end screen reads \"%s\"" % Endings.DOOM_TITLE, panel != null and panel.titleLabel.text == Endings.DOOM_TITLE, panel.titleLabel.text if panel != null else null)
	h.check("the run is won", GameWorld.won and Data.ofOr("game.over", "") == "won", {"won": GameWorld.won, "game.over": Data.ofOr("game.over", "")})
	h.check("one ending, one end screen", Level.mode.end_screens == 1 and ed.cards_shown == 1, [Level.mode.end_screens, ed.cards_shown])
