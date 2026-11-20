extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 97: the saved ending through its hook. Calls Level.mode.horror_defeated()
# (what the future boss fight will call; normal play never reaches it), then
# captures each narration card and the end screen "The Planet Is Saved". The
# run is a win.

const Endings = preload("res://mods-unpacked/cejdan-StoryMode/data/endings.gd")


func boot() -> Dictionary:
	return {"seed": 12345, "beats": true}


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	var ed = Level.mode.get_node_or_null("StoryEndings")
	h.check("the hook exists", Level.mode.has_method("horror_defeated"))
	Level.mode.horror_defeated()
	await h.until(func(): return ed.last_step == "cards", 10.0)
	var seen: Array = []
	var t_end: float = h.now() + 40.0
	while h.now() < t_end and ed.last_step == "cards":
		var box = h.beat_box()
		if box != null and box.get("cards") != null and box.current_card() != "" and not seen.has(box.current_card()):
			await h.wait(1.2)
			seen.append(box.current_card())
			await h.shot("card_%d" % seen.size())
		await h.wait(0.2)
	h.check("every narration card shows", seen == Endings.SAVED_CARDS, seen)
	await h.until(func(): return Level.stage.endingPanel != null, 15.0)
	await h.wait(3.0)
	var panel = Level.stage.endingPanel
	var title: String = panel.titleLabel.text if panel != null else ""
	await h.shot("end_screen")
	h.check("the end screen reads \"%s\"" % Endings.SAVED_TITLE, title == Endings.SAVED_TITLE, title)
	h.check("the run is recorded as won", GameWorld.won)
	h.check("calling the hook again does nothing", Level.mode.horror_defeated() == false)
