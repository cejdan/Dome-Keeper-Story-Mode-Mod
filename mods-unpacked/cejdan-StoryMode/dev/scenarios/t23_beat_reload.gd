extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 23, part two: run t23_beat_box first. This loads its save (slot 11) in
# a fresh process. The beat that was open when it saved (translator_1) opens
# again; the beats closed before the save never play again.

const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const CD := "team1.monsters.wavecooldown"


func boot() -> Dictionary:
	return {"load": 11}


func run(h) -> void:
	await h.until(func(): return not SaveGame.currentLoadingSavegame, 20.0)
	h.check("a Story Mode run came back from the save", Level.loadout != null and Level.loadout.modeId == "storymode")
	h.enable_waves()
	h.snap("loaded", ["team1.story.beatsqueued", "team1.story.beatsplayed"])
	var played: Array = Array(str(Data.ofOr("team1.story.beatsplayed", "")).split(",", false))
	h.check("the played beats came back", played == ["first_gem", "biome_b2", "gate_broken"], played)
	var opened: bool = await h.until(func(): return StoryBeats.is_open(), 10.0)
	h.check("the beat open at save time opens again", opened and StoryBeats.instance().open_id == "translator_1")
	await h.wait(0.5)
	await h.shot("reloaded_beat")
	var s: Array = []
	for i in 12:
		s.append(snappedf(float(Data.of(CD)), 0.001))
		await h.wait(0.25)
	h.check("wavecooldown holds still while it is open after the reload", s.min() == s.max(), s)
	await h.wait(2.0)
	for i in 3:
		if StoryBeats.is_open():
			await h.press("ui_select")
			await h.wait(0.8)
	h.check("it closes", await h.until(func(): return not StoryBeats.is_open(), 5.0))
	var after: Array = []
	for i in 8:
		after.append(snappedf(float(Data.of(CD)), 0.001))
		await h.wait(0.25)
	h.check("the countdown runs after it closes", after[0] > after[-1], after)
	for id: String in ["first_gem", "biome_b2", "gate_broken", "translator_1"]:
		h.check("%s doesn't play again after the reload" % id, not StoryBeats.fire(id))
	h.check("trigger(biome:B2) queues nothing after the reload", StoryBeats.trigger("biome:B2") == 0)
	await h.wait(1.0)
	h.check("nothing opened", not StoryBeats.is_open())
	h.check("an unplayed beat still plays", StoryBeats.fire("lava_death"))
	h.check("lava_death opens", await h.until(func(): return StoryBeats.instance().open_id == "lava_death", 5.0))
	await h.wait(1.0)
	await h.shot("new_beat_after_reload")
	for i in 3:
		if StoryBeats.is_open():
			await h.press("ui_select")
			await h.wait(0.8)
	await h.until(func(): return not StoryBeats.is_open(), 5.0)
	h.snap("end", ["team1.story.beatsqueued", "team1.story.beatsplayed"])
