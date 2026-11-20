extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 28: Story Mode's loadout and its domes. Since #269 it offers every
# dome vanilla offers (it offered only the laser dome before).


func boot() -> Dictionary:
	return {"loadout": true}


func _visible_domes(stage) -> Array:
	var out: Array = []
	for c in stage._DomeContainersTeam1.get_children():
		if not c is Label and c.visible:
			out.append(c.id)
	return out


func run(h) -> void:
	await h.wait(3.0)
	var stage = Level.stage
	GameWorld.figuredOutMovementInLoadout = true
	stage.updateBlockVisibility(true)
	await h.wait(1.0)
	stage.gameModeSelected("relichunt")
	await h.wait(1.5)
	var vanilla: Array = _visible_domes(stage)
	h.note("relic hunt domes", vanilla)
	# A dome swap in vanilla's own mode, for the log: Dome.unlisten drops
	# inventory listeners the loadout dome never added (vanilla, #269).
	stage.domeSelected("dome2", "team1", false)
	await h.wait(1.0)
	stage.domeSelected("dome1", "team1", false)
	await h.wait(1.0)
	h.note("relic hunt dome swap done")
	stage.gameModeSelected("storymode")
	await h.wait(2.0)
	var story: Array = _visible_domes(stage)
	var dblk = stage.find_child("BlockDomeLoadoutTeam1", true, false)
	var xf: Transform2D = dblk.get_global_transform()
	h.keeper().teleport(xf.origin + dblk.size * xf.get_scale() * 0.5)
	await h.wait(1.5)
	await h.shot("story_domes")
	# #269 changed this: Story Mode offered only the laser dome (#28); now it
	# offers every dome vanilla does.
	h.check("Story Mode offers every dome Relic Hunt does (#269)", story == vanilla and story.size() >= 4, story)
	stage.domeSelected("dome3", "team1", false)
	await h.wait(1.0)
	h.check("a dome can be picked in Story Mode", Level.loadout.domes.front().domeId == "dome3", Level.loadout.domes.front().domeId)
	stage.gameModeSelected("relichunt")
	await h.wait(2.0)
	var back: Array = _visible_domes(stage)
	await h.shot("relichunt_domes")
	h.check("Relic Hunt shows every dome again", back.size() > 1 and back == vanilla, back)
