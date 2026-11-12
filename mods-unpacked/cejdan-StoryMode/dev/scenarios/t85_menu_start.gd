extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Starts a Story Mode run the way a player does: loadout screen, pick Story
# Mode, start run. Every other scenario boots straight into a run.


func boot() -> Dictionary:
	return {"loadout": true}


func run(h) -> void:
	await h.wait(3.0)
	var stage = Level.stage
	GameWorld.figuredOutMovementInLoadout = true
	stage.updateBlockVisibility(true)
	await h.wait(1.0)
	var choice = null
	for c in stage.find_child("GameModeContainers").get_children():
		if not c is Label and c.id == "storymode":
			choice = c
	h.check("story choice exists", choice != null)
	h.note("before pick", {"mode": Level.loadout.modeId, "enabled": choice.enabled if choice and "enabled" in choice else null})
	h.keeper().teleport(choice.getGlobalPosition() + Vector2(0, 60))
	await h.wait(1.5)
	# The keeper's own hit on the choice, as a player's use input does.
	choice.useHit(h.keeper())
	await h.wait(2.0)
	h.check("pick took", Level.loadout.modeId == "storymode", Level.loadout.modeId)
	h.note("loadout before start", {"mode": Level.loadout.modeId, "config": Level.loadout.modeConfig})
	await h.shot("story_selected")
	stage._on_StartRunChoice_select()
	await h.until(func(): return Level.stage != null and str(Level.stage.get_script().resource_path).contains("LevelStage"), 90.0)
	await h.wait(6.0)
	await h.shot("run_started")
	h.note("run", {"mode": Level.loadout.modeId, "stage": str(Level.stage.get_script().resource_path), "money": Data.of("team1.inventory.money") if Data.has("team1.inventory.money") else null, "iron": Data.of("team1.inventory.iron")})
	h.check("run is story mode", Level.loadout.modeId == "storymode", Level.loadout.modeId)
	h.check("story money tracked", Data.has("team1.inventory.money"))
