extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 123: a new Story Mode run opens with the keeper's own company log,
# Halcyon's welcome memo, a moment after the keeper can move. It opens once,
# in the log box with the company header, and never gives the keeper's number.
# Saves to slot 17 with the welcome taken back out of the played list, for
# t123_reload (a loaded run must not show it, even then).

const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const LogData = preload("res://mods-unpacked/cejdan-StoryMode/data/logs.gd")


func boot() -> Dictionary:
	return {"seed": 12345, "welcome": true}


func run(h) -> void:
	var t0: float = h.now()
	var opened: Array = []
	StoryBeats.instance().beat_opened.connect(func(id): opened.append([id, h.now() - t0]))
	await h.until(func(): return StoryBeats.is_open(), 6.0)
	var box = h.beat_box()
	var header: String = ""
	if box != null:
		var labels: Array = box.find_children("*", "Label", true, false)
		header = labels[0].text if not labels.is_empty() else ""
	var id: String = await h.read_beat("welcome", 3.0)
	h.check("a new run opens the welcome log", id == LogData.WELCOME, id)
	h.check("it opens about a second after the keeper can move (0.8 to 3 s)", not opened.is_empty() and opened[0][1] >= 0.8 and opened[0][1] <= 3.0, opened)
	h.check("the box shows the company header, not a salvaged log", header.begins_with("HALCYON EXTRACTION"), header)
	var entry: Dictionary = LogData.by_id(LogData.WELCOME)
	var text: String = " ".join(PackedStringArray(entry.get("lines", []))) + entry.get("title", "") + entry.get("header", "")
	h.check("the welcome never gives the keeper's number", not text.contains("9"), text)
	h.check("it plays once", not StoryBeats.fire(LogData.WELCOME))
	await h.wait(3.0)
	h.check("nothing else opened", opened.size() == 1, opened)
	# For t123_reload: a save that hasn't played the welcome (as an old save).
	var played: Array = Array(str(Data.ofOr("team1.story.beatsplayed", "")).split(",", false))
	played.erase(LogData.WELCOME)
	Data.apply("team1.story.beatsplayed", ",".join(PackedStringArray(played)))
	await SaveGame.saveGame("singleplayer", 17, true)
	await h.wait(1.0)
	h.note("saved slot 17")
