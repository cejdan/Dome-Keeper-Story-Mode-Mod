extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 6: Story Mode shows in the loadout screen and can be selected.


func boot() -> Dictionary:
	return {"loadout": true}


func run(h) -> void:
	await h.wait(3.0)
	var stage = Level.stage
	# A fresh profile hides the loadout until the player has moved; skip that.
	GameWorld.figuredOutMovementInLoadout = true
	stage.updateBlockVisibility(true)
	await h.wait(2.0)
	await h.shot("loadout_open")
	var ids: Array = []
	var story_choice = null
	for c in stage.find_child("GameModeContainers").get_children():
		if not c is Label:
			ids.append(c.id)
			if c.id == "storymode":
				story_choice = c
	if story_choice != null:
		# Put the keeper (and so the camera) next to the Story Mode choice.
		h.note("story choice at", story_choice.getGlobalPosition())
		h.keeper().teleport(story_choice.getGlobalPosition() + Vector2(0, 60))
		await h.wait(1.5)
		await h.shot("gamemodes")
	h.check("story mode listed", ids.has("storymode"), ids)
	stage.gameModeSelected("storymode")
	await h.wait(2.0)
	h.check("story mode selected", Level.loadout.modeId == "storymode", Level.loadout.modeId)
	await h.shot("storymode_selected")
	var blk = stage.find_child("BlockRelicHuntLoadout", true, false)
	var xf: Transform2D = blk.get_global_transform()
	h.note("story block rect", {"pos": xf.origin, "scale": xf.get_scale(), "size": blk.size})
	h.keeper().teleport(xf.origin + blk.size * xf.get_scale() * 0.5)
	await h.wait(1.5)
	await h.shot("storymode_difficulty_block")
	var dblk = stage.find_child("BlockDomeLoadoutTeam1", true, false)
	xf = dblk.get_global_transform()
	h.keeper().teleport(xf.origin + dblk.size * xf.get_scale() * 0.5)
	await h.wait(1.5)
	await h.shot("storymode_dome_block")
	var kc = stage.find_child("KeeperContainers")
	xf = kc.get_global_transform()
	h.keeper().teleport(xf.origin + kc.size * xf.get_scale() * 0.5)
	await h.wait(1.5)
	await h.shot("storymode_keepers")
	var block = stage.find_child("BlockRelicHuntLoadout", true, false)
	h.check("difficulty block visible", block.visible)
	h.check("map size hidden", not block.find_child("MapSizeList", true, false).visible)
	h.note("loadout", {"dome": Level.loadout.domes.front().domeId, "keepers": Level.loadout.keepers.map(func(k): return k.keeperId), "config": Level.loadout.modeConfig})
	stage.gameModeSelected("relichunt")
	await h.wait(2.0)
	h.check("relic hunt map size back", block.find_child("MapSizeList", true, false).visible)
	await h.shot("relichunt_selected")
