extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 96: the doom ending. Buys Retire Rich with the shop open, as a player
# does, and captures every step: the horror's thanks (each page), the monsters'
# last words over the dome at the translation stage (0 here; t96_doom_stage3
# runs it at 3), each narration card, and the end screen "The Planet Is Lost".
# The run is a win.

const Endings = preload("res://mods-unpacked/cejdan-StoryMode/data/endings.gd")
const Runes = preload("res://mods-unpacked/cejdan-StoryMode/pleas/runes.gd")
const PleaData = preload("res://mods-unpacked/cejdan-StoryMode/data/pleas.gd")


func boot() -> Dictionary:
	return {"seed": 12345, "beats": true}


func stage() -> int:
	return 0


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	Runes.set_stage(stage())
	var ed = Level.mode.get_node_or_null("StoryEndings")
	h.check("the ending director is in the run", ed != null)
	h.set_inv("money", 1000000)
	# A player buys it from inside the shop, so the shop is open (and its input
	# processor live) when the ending starts.
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	await h.shot("shop_open_stage%d" % stage())
	var ok: bool = await h.buy("storyretirerich")
	h.check("Retire Rich bought", ok)
	# The horror's thanks: one beat, three pages.
	var id: String = await h.read_beat("thanks", 8.0)
	h.check("the horror thanks the keeper (doom_thanks)", id == "doom_thanks", id)
	# The monsters' last words, one at a time over the dome.
	await h.until(func(): return ed.last_step == "last_words", 5.0)
	var lines: Array = []
	for i in Endings.DOOM_LAST_WORDS.size():
		await h.wait(1.4)
		var shown = h.get_tree().get_nodes_in_group("story-plea")
		var texts: Array = shown.map(func(n): return n.get_child(0).get_parsed_text())
		lines.append(texts)
		await h.shot("last_words_%d_stage%d" % [i + 1, stage()])
		await h.wait(2.0)
	h.note("last words on screen", lines)
	var first: String = str(lines[0].back()) if lines.size() > 0 and lines[0].size() > 0 else ""
	h.check("last words show at stage %d" % stage(), first == Runes.render(Endings.DOOM_LAST_WORDS[0], stage()) or Runes.decode(first).to_lower() == PleaData.plain(Endings.DOOM_LAST_WORDS[0]).to_lower(), first)
	if stage() == 0:
		h.check("at stage 0 they are all runes", Runes.decode(first) != first and not first.contains("enough"), first)
	# The planet's end, card by card.
	await h.until(func(): return ed.last_step == "cards", 10.0)
	var seen: Array = []
	var box = null
	var t_end: float = h.now() + 40.0
	while h.now() < t_end and ed.last_step == "cards":
		box = h.beat_box()
		if box != null and box.get("cards") != null and box.current_card() != "" and not seen.has(box.current_card()):
			await h.wait(1.2)
			seen.append(box.current_card())
			await h.shot("card_%d" % seen.size())
		await h.wait(0.2)
	h.check("every narration card shows", seen == Endings.DOOM_CARDS, seen)
	# The end screen.
	await h.until(func(): return Level.stage.endingPanel != null, 15.0)
	await h.wait(3.0)
	var panel = Level.stage.endingPanel
	var title: String = panel.titleLabel.text if panel != null else ""
	await h.shot("end_screen")
	h.check("the end screen reads \"%s\"" % Endings.DOOM_TITLE, title == Endings.DOOM_TITLE, title)
	h.check("the run is recorded as won", GameWorld.won)
