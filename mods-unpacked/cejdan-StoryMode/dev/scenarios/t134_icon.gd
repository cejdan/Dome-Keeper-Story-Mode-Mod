extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 134: the Story Mode icon (the horror's tentacled silhouette) in the
# shop: the Story Mode track's root. Its loadout-screen use is shot by t06_loadout.


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	await h.wait(1.0)
	var icon: Texture2D = load("res://content/icons/storymode.png")
	h.check("the shop icon is a 72 x 72 texture", icon != null and icon.get_size() == Vector2(72, 72), icon.get_size() if icon else null)
	var mode: Texture2D = load("res://content/icons/loadout_storymode.png")
	h.check("the loadout icon is 70 x 40", mode != null and mode.get_size() == Vector2(70, 40), mode.get_size() if mode else null)
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	for i in 14:
		await h.press("ui_down")
		await h.wait(0.2)
	await h.shot("shop_story_track")
	await h.press("ui_cancel")
	await h.wait(1.0)
