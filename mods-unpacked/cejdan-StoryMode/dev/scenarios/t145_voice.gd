extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 145: the horror's voice grows with depth. B2's "Hello digger." is a
# whisper: small white text, smaller than the narration, faintly wavy. The
# same beat replayed after deeper biomes gets bigger and takes on its tier's
# colour, full style from B5 on. Then B3 and B4 at their own depths.

const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const BeatBox = preload("res://mods-unpacked/cejdan-StoryMode/beats/BeatBox.gd")


func boot() -> Dictionary:
	return {"seed": 12345, "beats": true}


func _font_size(box) -> int:
	var t: String = box._text.text
	var i: int = t.find("[font_size=")
	if i < 0:
		return -1
	return int(t.substr(i + 11, t.find("]", i) - i - 11))


# Fires `id` with the deepest biome index set to `deepest`, reads it to the end
# (a shot per page), and returns [volume, horror size on the last page, text].
func _play(h, id: String, deepest: int, label: String) -> Array:
	Data.apply("team1.story.deepest", deepest)
	Data.apply("team1.story.beatsplayed", "")
	StoryBeats.fire(id)
	await h.until(func(): return h.beat_box() != null, 5.0)
	var box = h.beat_box()
	var out: Array = [box.volume, -1, ""]
	# The horror's line is on the last page; turn to it, then let read_beat shoot it.
	while box.has_next_page():
		await h.until(func(): return not box.is_revealing(), 12.0)
		await h.wait(0.4)
		await h.shot("%s_narration" % label)
		await h.press("ui_select")
		await h.wait(0.4)
	out[1] = _font_size(box)
	out[2] = box._text.text
	await h.read_beat(label, 5.0)
	await h.wait(0.4)
	return out


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	var narr_size: int = int(BeatBox.STYLES[1]["size"] * BeatBox.NARRATOR_SCALE)
	var sizes: Array = []
	for d in [1, 2, 3, 4]:
		var r: Array = await _play(h, "biome_b2", d, "b2_at_B%d" % (d + 1))
		sizes.append(r[1])
		h.note("biome_b2 after B%d" % (d + 1), {"volume": r[0], "size": r[1], "text": r[2]})
		if d == 1:
			h.check("B2: a whisper (volume 0)", r[0] == 0.0, r[0])
			h.check("B2: \"Hello digger.\" smaller than the narration (%d px)" % narr_size, r[1] > 0 and r[1] < narr_size, r[1])
			h.check("B2: white and faintly wavy", r[2].contains("[color=#f6f4ff]") and r[2].contains("[wave amp=9.0"), r[2])
		if d == 4:
			h.check("from B5 on: the tier's full style", r[0] == 1.0 and r[2].contains(BeatBox.STYLES[1]["open"] + "Hello digger."), r[2])
	h.check("the voice grows with each biome", sizes[0] < sizes[1] and sizes[1] < sizes[2], sizes)
	var b3: Array = await _play(h, "biome_b3", 2, "b3_natural")
	var b4: Array = await _play(h, "biome_b4", 3, "b4_natural")
	h.note("natural depths", {"b3": b3.slice(0, 2), "b4": b4.slice(0, 2)})
	h.check("B3 louder than B2's whisper, B4 louder still", b3[1] > 20 and b4[1] > b3[1], [b3[1], b4[1]])
	var b5: Array = await _play(h, "biome_b5", 4, "b5_natural")
	h.check("B5: full violet", b5[0] == 1.0 and b5[2].contains("[wave amp=14 freq=1.4"), b5[2])
	h.snap("end", [])
