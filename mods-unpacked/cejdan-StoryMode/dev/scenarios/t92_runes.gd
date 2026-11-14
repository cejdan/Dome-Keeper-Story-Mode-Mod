extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 92: the same plea at translation stages 0..3 over a real fight, the
# rune cipher decoded back to English, key words English from stage 1.

const Runes = preload("res://mods-unpacked/cejdan-StoryMode/pleas/runes.gd")
const PleaData = preload("res://mods-unpacked/cejdan-StoryMode/data/pleas.gd")

const LINE := "Every hole you make, it *breathes*."
const LINE2 := "*Stop* digging. We give anything."


func boot() -> Dictionary:
	return {"seed": 12345}


func _latin(s: String) -> int:
	var n: int = 0
	for i in s.length():
		var c: int = s.unicode_at(i)
		if (c >= 65 and c <= 90) or (c >= 97 and c <= 122):
			n += 1
	return n


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	var pd = load("res://mods-unpacked/cejdan-StoryMode/pleas/plea_director.gd").instance()
	h.check("the rune font builds", Runes.font() != null)
	# Text-only checks first. The runes have no case: they decode to lower case.
	var r0: String = Runes.render(LINE, 0)
	h.check("stage 0: no Latin letters left", _latin(r0) == 0, r0)
	h.check("stage 0: decoding the runes gives the English back", Runes.decode(r0) == PleaData.plain(LINE).to_lower(), Runes.decode(r0))
	for line: String in [LINE, LINE2]:
		var r1: String = Runes.render(line, 1)
		h.note("stage 1", {"line": line, "shown": r1, "decoded": Runes.decode(r1)})
		var keys: Array = []
		for m in RegEx.create_from_string("\\*([A-Za-z']+)\\*").search_all(line):
			keys.append(m.get_string(1))
		h.check("stage 1: key words %s are English" % [keys], keys.all(func(k): return r1.contains(k)), r1)
	var counts: Array = []
	for s in 4:
		counts.append(_latin(Runes.render(LINE, s)))
	h.check("English grows stage by stage (letters shown in Latin)", counts[0] == 0 and counts[0] < counts[1] and counts[1] < counts[2] and counts[2] < counts[3], counts)
	h.check("stage 3 is all English", Runes.render(LINE, 3) == PleaData.plain(LINE))
	h.check("a line looks the same every time at a stage", Runes.render(LINE, 2) == Runes.render(LINE, 2))

	# The same plea over a real fight at each stage.
	Data.apply("team1.dome.maxHealth", 1000000)
	Data.apply("team1.dome.health", 1000000)
	h.enable_waves()
	GameWorld.runStarted = true
	Data.apply("team1.monsters.wavecooldown", 2)
	await h.until(func(): return Data.of("team1.monsters.wavepresent"), 40.0)
	# Only this test's plea on screen: no fight lines or last words from the wave.
	await h.wait(0.5)
	pd._fights_due.clear()
	pd.death_chance = 0.0
	await h.wait(2.5)
	for s in 4:
		Runes.set_stage(s)
		pd.say("arrive", null, LINE)
		await h.wait(1.2)
		var shown = h.get_tree().get_nodes_in_group("story-plea").filter(func(n): return n.get_meta("line", "") == LINE)
		var label = shown.back().get_child(0) if shown.size() > 0 else null
		var txt: String = label.get_parsed_text() if label else ""
		h.note("on screen at stage %d" % s, {"text": txt, "decoded": Runes.decode(txt)})
		h.check("stage %d on screen decodes to the line" % s, Runes.decode(txt).to_lower() == PleaData.plain(LINE).to_lower(), txt)
		await h.shot("stage%d" % s)
		await h.wait(0.5)
	# A screenshot at 4x of the stage-0 runes, for the record.
	Runes.set_stage(0)
	pd.say("arrive", null, LINE)
	await h.wait(1.0)
	await h.shot("stage0_again")
	Level.monstersByTeamId["team1"].instantlyKillWave()
