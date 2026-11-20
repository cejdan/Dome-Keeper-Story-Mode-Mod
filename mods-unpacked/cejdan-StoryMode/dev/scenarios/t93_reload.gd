extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 93, part two: run t93_translators first. Loads its save (slot 12) in a
# fresh process: the translation stage is still 3, and the chambers are still
# the translator chambers, spent.

const Runes = preload("res://mods-unpacked/cejdan-StoryMode/pleas/runes.gd")


func boot() -> Dictionary:
	return {"load": 12, "beats": true}


func run(h) -> void:
	await h.until(func(): return not SaveGame.currentLoadingSavegame, 20.0)
	await h.wait(1.0)
	h.disable_waves()
	h.check("translation stage survives the reload", Runes.stage() == 3, Runes.stage())
	var chambers: Array = []
	for c in Level.map.find_children("*", "", true, false):
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("TranslatorChamber.gd"):
			chambers.append(c)
	h.check("3 translator chambers come back", chambers.size() == 3, chambers.size())
	h.check("all spent", chambers.all(func(c): return c.currentState == c.State.EMPTY), chambers.map(func(c): return c.currentState))
	var pd = load("res://mods-unpacked/cejdan-StoryMode/pleas/plea_director.gd").instance()
	pd.say("arrive", null, "Every hole you make, it *breathes*.", 5.0)
	await h.wait(1.2)
	await h.shot("plea_after_reload")
