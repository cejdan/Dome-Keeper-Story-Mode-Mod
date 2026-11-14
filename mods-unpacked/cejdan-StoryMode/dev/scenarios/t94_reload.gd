extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 94, part two: run t94_bones first. Loads its save (slot 13) in a fresh
# process: no log plays again, and the bones left in the mine keep their value.

const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")


func boot() -> Dictionary:
	return {"load": 13, "beats": true}


func run(h) -> void:
	await h.until(func(): return not SaveGame.currentLoadingSavegame, 20.0)
	await h.wait(1.0)
	h.disable_waves()
	var ok: bool = true
	for b in range(1, 9):
		ok = ok and not StoryBeats.fire("log_b%d" % b)
	h.check("no log plays again after the reload", ok)
	await h.wait(1.0)
	h.check("nothing opened", not StoryBeats.is_open())
	var vals: Array = []
	for d in Level.drops.find_children("*", "", true, false):
		if d.get("type") == "minerbones":
			vals.append(d.value)
	h.check("the bones left in the mine keep their value ($4,242)", vals.has(4242), vals)
