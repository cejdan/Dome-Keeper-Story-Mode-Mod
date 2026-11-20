extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 285: the user's script pass. Plays every beat they rewrote at the
# depth it fires at, shoots every page, and checks the line cues: the first
# gate's "{small} Thank you." and "{smaller shake} ..." come out smaller (and
# shaking), the boss chamber's "{big shake} hungry." bigger and shaking, the
# doom thanks' "{huge shake glitch} feast." biggest, shaking and glitching, and
# no cue's braces reach the screen. The cut beats are gone from the data.
# Second pass (2026-11-19): lava_death_1, the translators and the doom thanks.

const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
const BeatBox = preload("res://mods-unpacked/flantor-StoryMode/beats/BeatBox.gd")
const BeatData = preload("res://mods-unpacked/flantor-StoryMode/data/beats.gd")

# Beat id: the deepest biome index when it fires (3 = B4, 8 = the lava ocean).
const BEATS := {
	"gate_broken": 3,
	"biome_b5": 4,
	"biome_b6": 5,
	"biome_b7": 6,
	"biome_b8": 7,
	"lava_ocean": 8,
	"boss_chamber": 8,
	"lava_death_1": 4,
	"translator_1": 2,
	"translator_2": 4,
	"translator_3": 6,
	"doom_thanks": 8,
}
# Every page types out at the read-along pace, so the run is long.
const TIMEOUT := 900
const CUT := ["biome_b4", "first_gem", "unobtainium_1", "unobtainium_3", "unobtainium_5", "unobtainium_7", "unobtainium_10",
	"lava_death_2", "lava_death_3", "lava_death_4", "lava_death_5"]


func boot() -> Dictionary:
	return {"seed": 12345, "beats": true, "boss": false}


func _sizes(bb: String) -> Array:
	var out: Array = []
	var re: RegEx = RegEx.create_from_string("\\[font_size=(\\d+)\\]")
	for m: RegExMatch in re.search_all(bb):
		out.append(int(m.get_string(1)))
	return out


# Every page of `id` at depth `deepest`: [{"bb": bbcode, "shown": parsed text}].
func _play(h, id: String, deepest: int) -> Array:
	Data.apply("team1.story.deepest", deepest)
	h.check("%s queues" % id, StoryBeats.fire(id))
	await h.until(func(): return h.beat_box() != null, 5.0)
	var box = h.beat_box()
	if id == "biome_b7":
		# Typing out, at the faster pace (centred lines re-centre as they grow).
		await h.wait(0.5)
		await h.burst("%s_typing" % id, 8, 2)
	var pages: Array = []
	var n: int = 1
	while true:
		await h.until(func(): return not box.is_revealing(), 60.0)
		await h.wait(0.6)
		await h.shot("%s_p%d" % [id, n])
		pages.append({"bb": box._text.text, "shown": box._text.get_parsed_text(), "raw": box._pages[box._page], "calm": box._calm})
		if not box.has_next_page():
			break
		await h.press("ui_select")
		await h.wait(0.3)
		n += 1
	await h.burst("%s_last_motion" % id, 10, 4)
	await h.press("ui_select")
	h.check("%s closes after %d pages" % [id, pages.size()], await h.until(func(): return not StoryBeats.is_open(), 4.0))
	await h.wait(0.8)
	return pages


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	await h.dig_room(Vector2i(-3, 6), Vector2i(3, 9))
	await h.teleport_tile(Vector2i(0, 9))
	await h.wait(1.0)
	for id: String in CUT:
		h.check("%s is cut from the data" % id, BeatData.by_id(id).is_empty())
	h.check("cue() reads size, shake and glitch", BeatBox.cue("{smaller shake} Only one.") == {"text": "Only one.", "scale": BeatBox.CUE_SCALES["smaller"], "shake": true, "glitch": false}
			and BeatBox.cue("{huge shake glitch} feast.") == {"text": "feast.", "scale": BeatBox.CUE_SCALES["huge"], "shake": true, "glitch": true}
			and BeatBox.cue("{oops} hi") == {"text": "{oops} hi", "scale": 1.0, "shake": false, "glitch": false} and BeatBox.cue("plain")["scale"] == 1.0)
	for id: String in BEATS:
		var pages: Array = await _play(h, id, BEATS[id])
		var want: int = 1
		for l in BeatData.by_id(id)["lines"]:
			if str(l).strip_edges() == "---":
				want += 1
		h.check("%s: %d pages as written" % [id, want], pages.size() == want, pages.size())
		var braces: Array = pages.filter(func(p): return str(p["shown"]).contains("{") or str(p["shown"]).contains("}"))
		h.check("%s: no cue braces on screen" % id, braces.is_empty(), braces)
		# Violet is the horror's: a page that is all narration wears the calm panel.
		var looks: Array = pages.map(func(p): return p["calm"])
		var want_looks: Array = pages.map(func(p): return Array(str(p["raw"]).split("
")).all(func(l): return BeatBox.is_narration(l)))
		h.check("%s: narration-only pages are calm, the horror's are violet" % id, looks == want_looks, [looks, want_looks])
		h.note(id, pages)
		if id == "gate_broken" and pages.size() == 5:
			var thanks: Array = _sizes(pages[3]["bb"])
			var seal: Array = _sizes(pages[4]["bb"])
			h.note("gate sizes", {"thanks": thanks, "seal": seal})
			# The whisper wrap's size comes first, then the cue's.
			h.check("gate: \"Thank you.\" smaller than the voice", thanks.size() == 2 and thanks[1] < thanks[0], thanks)
			h.check("gate: the last line smaller still, and shaking", seal.size() == 2 and seal[1] < thanks[1] and pages[4]["bb"].contains("[shake "), [seal, pages[4]["bb"]])
		if id == "boss_chamber" and pages.size() == 3:
			var s: Array = _sizes(pages[2]["bb"])
			h.check("boss: \"hungry.\" big and shaking", s.size() == 1 and s[0] > BeatBox.STYLES[4]["size"] and pages[2]["bb"].contains("[shake "), [s, pages[2]["bb"]])
		if id == "doom_thanks" and pages.size() == 5:
			var s: Array = _sizes(pages[4]["bb"])
			var bb: String = pages[4]["bb"]
			h.check("doom thanks: \"feast.\" huge, shaking and glitching", s.size() == 1 and s[0] > BeatBox.STYLES[4]["size"] * 2 and bb.contains("[shake ") and bb.contains("[glitch rate=4"), [s, bb])
	h.snap("end", ["team1.story.beatsplayed"])
