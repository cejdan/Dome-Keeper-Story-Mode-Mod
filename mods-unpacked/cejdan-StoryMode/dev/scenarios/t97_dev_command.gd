extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 97: the dev command. Boots with `--horror-defeated` (a boot key stands
# in for the `-- --horror-defeated` user arg) and touches nothing: the saved
# ending must start by itself once the keeper can move, and end on "The Planet
# Is Saved".

const Endings = preload("res://mods-unpacked/cejdan-StoryMode/data/endings.gd")


func boot() -> Dictionary:
	return {"seed": 12345, "horror-defeated": true}


func run(h) -> void:
	var ed = Level.mode.get_node_or_null("StoryEndings")
	await h.until(func(): return ed != null and ed.playing == "saved", 30.0)
	h.check("the dev command starts the saved ending", ed != null and ed.playing == "saved")
	await h.until(func(): return Level.stage.endingPanel != null, 60.0)
	await h.wait(3.0)
	var panel = Level.stage.endingPanel
	var title: String = panel.titleLabel.text if panel != null else ""
	await h.shot("end_screen")
	h.check("the end screen reads \"%s\"" % Endings.SAVED_TITLE, title == Endings.SAVED_TITLE, title)
	h.check("the run is recorded as won", GameWorld.won)
