extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 137: the narrator. The first beats open with narration ("> " lines),
# styled apart from the horror's voice, and page as the user wrote them:
# B2 and B3 in two pages each, B4 with its new first page. Shoots every page.

const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const BeatBox = preload("res://mods-unpacked/cejdan-StoryMode/beats/BeatBox.gd")

const EXPECT := {
	"biome_b2": 2,
	"biome_b3": 2,
	"biome_b4": 2,
}


func boot() -> Dictionary:
	return {"seed": 12345, "beats": true}


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	for id: String in EXPECT:
		StoryBeats.fire(id)
		await h.until(func(): return h.beat_box() != null, 5.0)
		var box = h.beat_box()
		h.check("%s: %d pages" % [id, EXPECT[id]], box != null and box.page_count() == EXPECT[id], box.page_count() if box else null)
		if box != null:
			var first: String = box._pages[0]
			var narr: bool = BeatBox.is_narration(first.split("\n")[0])
			h.check("%s: opens with narration" % id, narr == (id != "biome_b4"), first)
			# The narrator's lines are drawn in the slanted font, not the horror's effects.
			h.check("%s: narration is italic and not waved" % id, not narr or (box._text.text.contains("[i][color=#c7bfb4]") and not box._text.text.begins_with("[center][wave")), box._text.text)
		var read: String = await h.read_beat(id, 5.0)
		h.check("%s read to the end" % id, read == id, read)
		await h.wait(0.5)
