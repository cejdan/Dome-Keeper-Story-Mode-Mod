extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 303: the shop's top section, "Leave the Planet", offers Call for
# Evacuation for free beside Fill Quota. Buying it opens Halcyon's refusal in
# the log box with the company header, once; the run goes on, no money moves,
# the entry shows as bought, and Fill Quota is still on offer at $1M.

const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const LogData = preload("res://mods-unpacked/cejdan-StoryMode/data/logs.gd")

const EVAC := "team1.storyevacuate"
const QUOTA := "team1.storyretirerich"


func boot() -> Dictionary:
	return {"seed": 12345, "beats": true}


func run(h) -> void:
	h.disable_waves()
	await h.wait(1.0)
	h.check("the section reads Leave the Planet", tr("upgrades.storywin.title") == "Leave the Planet", tr("upgrades.storywin.title"))
	h.check("Call for Evacuation is on offer", GameWorld.upgrades.has(EVAC) and not GameWorld.boughtUpgrades.has(EVAC), GameWorld.upgrades.get(EVAC, {}))
	h.check("it is free", int(GameWorld.upgrades.get(EVAC, {}).get("cost", {}).get("money", -1)) == 0, GameWorld.upgrades.get(EVAC, {}).get("cost", {}))
	h.check("its text is the user's", tr("upgrades.storyevacuate.title") == "Call for Evacuation" and tr("upgrades.storyevacuate.desc") == "Escape with your life intact. Use only in dire circumstances.", [tr("upgrades.storyevacuate.title"), tr("upgrades.storyevacuate.desc")])
	h.check("its icon loads", load("res://content/icons/storyevacuate.png") != null)

	h.set_inv("money", 500)
	var money0: int = int(Data.ofOr("team1.inventory.money", 0))
	var opened: Array = []
	StoryBeats.instance().beat_opened.connect(func(id): opened.append(id))
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	await h.shot("shop_before")

	h.check("buying it goes through with $500", await h.buy("storyevacuate"))
	await h.until(func(): return StoryBeats.is_open(), 4.0)
	# The shop pauses the game and a beat waits for it, so an open reply means
	# the shop closed itself.
	h.check("the shop closes and the reply opens at once", StoryBeats.is_open())
	var box = h.beat_box()
	var header: String = ""
	if box != null:
		var labels: Array = box.find_children("*", "Label", true, false)
		header = labels[0].text if not labels.is_empty() else ""
	var id: String = await h.read_beat("refusal", 3.0)
	h.check("Halcyon's refusal opens", id == LogData.EVACUATION, id)
	h.check("in the log box with the company header", header.begins_with("HALCYON MINERALS"), header)
	await h.wait(1.0)
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	await h.shot("shop_after")

	h.check("the entry shows as bought", GameWorld.boughtUpgrades.has(EVAC), EVAC)
	h.check("no money moved", int(Data.ofOr("team1.inventory.money", 0)) == money0, [money0, Data.ofOr("team1.inventory.money", 0)])
	h.check("the run goes on", not GameWorld.won and not GameWorld.lost and str(Data.ofOr("game.over", "")) == "", Data.ofOr("game.over", ""))
	h.check("Fill Quota is still on offer at $1M", GameWorld.upgrades.has(QUOTA) and not GameWorld.boughtUpgrades.has(QUOTA) and int(GameWorld.upgrades[QUOTA].get("cost", {}).get("money", 0)) == 1000000, GameWorld.upgrades.get(QUOTA, {}).get("cost", {}))
	h.check("the refusal plays once", not StoryBeats.fire(LogData.EVACUATION))
	await h.wait(2.0)
	h.check("nothing else opened", opened == [LogData.EVACUATION], opened)
