extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 28: Story Mode's loadout offers only the laser dome; vanilla modes keep
# every dome.


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
	stage.gameModeSelected("storymode")
	await h.wait(2.0)
	var story: Array = _visible_domes(stage)
	var dblk = stage.find_child("BlockDomeLoadoutTeam1", true, false)
	var xf: Transform2D = dblk.get_global_transform()
	h.keeper().teleport(xf.origin + dblk.size * xf.get_scale() * 0.5)
	await h.wait(1.5)
	await h.shot("story_domes")
	h.check("Story Mode offers only the laser dome", story == ["dome1"], story)
	h.check("and the loadout's dome is the laser dome", Level.loadout.domes.front().domeId == "dome1", Level.loadout.domes.front().domeId)
	stage.gameModeSelected("relichunt")
	await h.wait(2.0)
	var back: Array = _visible_domes(stage)
	await h.shot("relichunt_domes")
	h.check("Relic Hunt shows every dome again", back.size() > 1 and back == vanilla, back)
