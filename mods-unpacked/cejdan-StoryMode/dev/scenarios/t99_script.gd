extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 99: the game's story text is the approved script. Parses
# docs/story/script.md and checks every horror beat (id, tier, lines), plea
# pool, data log (title, lines), ending card, last word and end-screen title in
# data/{beats,pleas,logs,endings}.gd matches it exactly, nothing is missing on
# either side, and no data line looks like placeholder text.

const BeatData = preload("res://mods-unpacked/cejdan-StoryMode/data/beats.gd")
const PleaData = preload("res://mods-unpacked/cejdan-StoryMode/data/pleas.gd")
const LogData = preload("res://mods-unpacked/cejdan-StoryMode/data/logs.gd")
const Endings = preload("res://mods-unpacked/cejdan-StoryMode/data/endings.gd")

const SCRIPT := "res://docs/story/script.md"
# Beats whose script section has another name.
const BEAT_SECTION := {"doom_thanks": "horror_thanks"}
const PLACEHOLDER := "(?i)\\b(todo|tbd|fixme|placeholder|lorem|ipsum|xxx)\\b|\\[[^\\]]*\\]|<[^>]*>"


func boot() -> Dictionary:
	return {"seed": 12345}


# The script as {"## part": {"### section": {"tier": n, "lines": [...],
# "sub": {"#### kind": [...]}}}}, plus top-level "Key: value" lines.
func _parse(text: String) -> Dictionary:
	var parts: Dictionary = {}
	var keys: Dictionary = {}
	var part: String = ""
	var sec: Dictionary = {}
	var sub: String = ""
	var re_sec: RegEx = RegEx.create_from_string("^### (\\S+)(?: \\(tier (\\d)\\))?")
	for raw: String in text.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("## "):
			part = line.substr(3)
			parts[part] = {}
			sec = {}
			continue
		if line.begins_with("### "):
			var m: RegExMatch = re_sec.search(line)
			sec = {"tier": int(m.get_string(2)) if m.get_string(2) != "" else 0, "lines": [], "sub": {}}
			parts[part][m.get_string(1) if part != "Pleas" else line.substr(4, 7)] = sec
			sub = ""
			continue
		if line.begins_with("#### "):
			sub = line.substr(5)
			sec["sub"][sub] = []
			continue
		if line == "" or sec.is_empty():
			if line.contains(": ") and part.ends_with("titles"):
				keys[line.get_slice(": ", 0)] = line.substr(line.find(": ") + 2)
			continue
		var item: String = line.substr(2) if line.begins_with("- ") else line
		if sub != "":
			sec["sub"][sub].append(item)
		else:
			sec["lines"].append(item)
	parts["keys"] = keys
	return parts


func _diff(want: Array, got: Array) -> Array:
	var out: Array = []
	for i in maxi(want.size(), got.size()):
		var w = want[i] if i < want.size() else "<missing>"
		var g = got[i] if i < got.size() else "<missing>"
		if w != g:
			out.append({"line": i + 1, "script": w, "data": g})
	return out


func run(h) -> void:
	var f: FileAccess = FileAccess.open(SCRIPT, FileAccess.READ)
	h.check("the script is readable at " + SCRIPT, f != null)
	if f == null:
		return
	var s: Dictionary = _parse(f.get_as_text())
	var beats_md: Dictionary = s.get("Story beats", {})
	var doom_md: Dictionary = s.get("Doom ending", {})
	var saved_md: Dictionary = s.get("Saved ending", {})
	var all_lines: Array = []

	# Beats: every data beat has its script section, word for word, same tier.
	var bad: Array = []
	var seen: Dictionary = {}
	for b: Dictionary in BeatData.BEATS:
		var id: String = b["id"]
		var name: String = BEAT_SECTION.get(id, id)
		var sec: Dictionary = beats_md.get(name, doom_md.get(name, {}))
		seen[name] = true
		all_lines.append_array(b["lines"])
		if sec.is_empty():
			bad.append({"beat": id, "problem": "not in the script"})
			continue
		var d: Array = _diff(sec["lines"], b["lines"])
		if not d.is_empty():
			bad.append({"beat": id, "lines": d})
		if sec["tier"] != 0 and sec["tier"] != int(b["tier"]):
			bad.append({"beat": id, "tier": [sec["tier"], b["tier"]]})
	for name: String in beats_md:
		if not seen.has(name):
			bad.append({"beat": name, "problem": "in the script, not in data/beats.gd"})
	h.check("%d beats match the script (lines and tiers), none missing" % BeatData.BEATS.size(), bad.is_empty(), bad)
	# The doom thanks, as pages, also live in data/endings.gd.
	var pages: Array = []
	for p in Endings.DOOM_THANKS:
		if not pages.is_empty():
			pages.append("---")
		pages.append_array(p)
	h.check("Endings.DOOM_THANKS matches the script's horror_thanks", _diff(doom_md.get("horror_thanks", {}).get("lines", []), pages).is_empty(), _diff(doom_md.get("horror_thanks", {}).get("lines", []), pages))

	# Pleas: 4 stages x 3 kinds, each pool line for line.
	bad = []
	var pleas_md: Dictionary = s.get("Pleas", {})
	var n_pleas: int = 0
	for st: String in ["A", "B", "C", "D"]:
		var sec: Dictionary = pleas_md.get("Stage " + st, {})
		for kind: String in ["arrive", "fight", "death"]:
			var want: Array = sec.get("sub", {}).get(kind, [])
			var got: Array = PleaData.pool(st, kind)
			n_pleas += got.size()
			all_lines.append_array(got)
			if want.is_empty() or not _diff(want, got).is_empty():
				bad.append({"pool": st + "/" + kind, "lines": _diff(want, got)})
		for kind: String in sec.get("sub", {}):
			if not ["arrive", "fight", "death"].has(kind):
				bad.append({"pool": st + "/" + kind, "problem": "in the script, not in data/pleas.gd"})
	h.check("12 plea pools (%d lines) match the script" % n_pleas, bad.is_empty() and PleaData.STAGES.size() == 4 and pleas_md.size() == 4, bad)

	# Data logs: title and body.
	bad = []
	var logs_md: Dictionary = s.get("Data logs", {})
	for l: Dictionary in LogData.LOGS:
		var sec: Dictionary = logs_md.get(l["id"], {})
		all_lines.append(l["title"])
		all_lines.append_array(l["lines"])
		if sec.is_empty():
			bad.append({"log": l["id"], "problem": "not in the script"})
			continue
		var want: Array = sec["lines"].duplicate()
		var title: String = str(want.pop_front()) if not want.is_empty() else ""
		if title != "Title: " + l["title"]:
			bad.append({"log": l["id"], "title": [title, l["title"]]})
		if not _diff(want, l["lines"]).is_empty():
			bad.append({"log": l["id"], "lines": _diff(want, l["lines"])})
	h.check("%d data logs match the script (titles and lines), none missing" % LogData.LOGS.size(), bad.is_empty() and logs_md.size() == LogData.LOGS.size(), bad)

	# Endings: cards, last words, end-screen titles.
	h.check("doom cards match planet_end", _diff(doom_md.get("planet_end", {}).get("lines", []), Endings.DOOM_CARDS).is_empty(), _diff(doom_md.get("planet_end", {}).get("lines", []), Endings.DOOM_CARDS))
	h.check("monsters' last words match monsters_last", _diff(doom_md.get("monsters_last", {}).get("lines", []), Endings.DOOM_LAST_WORDS).is_empty(), _diff(doom_md.get("monsters_last", {}).get("lines", []), Endings.DOOM_LAST_WORDS))
	h.check("saved cards match saved", _diff(saved_md.get("saved", {}).get("lines", []), Endings.SAVED_CARDS).is_empty(), _diff(saved_md.get("saved", {}).get("lines", []), Endings.SAVED_CARDS))
	# The boss sequence's draft text (#162).
	var BossText = load("res://mods-unpacked/cejdan-StoryMode/data/boss_text.gd")
	var boss_md: Dictionary = s.get("Boss", {})
	h.check("the monsters' thanks match monsters_thanks", _diff(boss_md.get("monsters_thanks", {}).get("lines", []), BossText.THANKS).is_empty(), _diff(boss_md.get("monsters_thanks", {}).get("lines", []), BossText.THANKS))
	h.check("the lost ending's cards match fallen", _diff(boss_md.get("fallen", {}).get("lines", []), BossText.FALLEN_CARDS).is_empty(), _diff(boss_md.get("fallen", {}).get("lines", []), BossText.FALLEN_CARDS))
	all_lines.append_array(BossText.THANKS + BossText.FALLEN_CARDS)
	var keys: Dictionary = s.get("keys", {})
	var titles: Dictionary = {"Doom title": Endings.DOOM_TITLE, "Doom subtitle": Endings.DOOM_SUBTITLE, "Saved title": Endings.SAVED_TITLE, "Saved subtitle": Endings.SAVED_SUBTITLE,
		"Fallen title": BossText.FALLEN_TITLE, "Fallen subtitle": BossText.FALLEN_SUBTITLE}
	bad = []
	for k: String in titles:
		if keys.get(k, "<missing>") != titles[k]:
			bad.append({k: [keys.get(k, "<missing>"), titles[k]]})
	h.check("end-screen titles and subtitles match", bad.is_empty(), bad)
	all_lines.append_array(Endings.DOOM_CARDS + Endings.DOOM_LAST_WORDS + Endings.SAVED_CARDS + titles.values())

	# No placeholder text anywhere in the story data.
	var re: RegEx = RegEx.create_from_string(PLACEHOLDER)
	var odd: Array = all_lines.filter(func(l): return re.search(str(l)) != null or str(l).strip_edges() == "")
	h.check("no placeholder text in %d story lines" % all_lines.size(), odd.is_empty(), odd)
	# The parser itself found the whole script (guards against a check that
	# passes because it read nothing).
	h.check("the script parse found 24 story beats, 3 doom sections, 4 plea stages, 9 logs (8 miners' and the keeper's welcome)", beats_md.size() == 24 and doom_md.size() == 3 and pleas_md.size() == 4 and logs_md.size() == 9, {"beats": beats_md.size(), "doom": doom_md.keys(), "pleas": pleas_md.keys(), "logs": logs_md.size()})
