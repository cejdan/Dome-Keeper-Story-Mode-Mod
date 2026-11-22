extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 320: the map size choice in Story Mode's loadout. Picks Story Mode,
# checks the four sizes are shown and open, picks Small with the size choice's
# own handler and starts the run; the run's map must be a small Story Mode map
# (map meta, and much shallower than the full map's chamber row of ~150).

const TIMEOUT := 300


func boot() -> Dictionary:
	return {"loadout": true}


func run(h) -> void:
	await h.wait(3.0)
	var stage = Level.stage
	GameWorld.figuredOutMovementInLoadout = true
	stage.updateBlockVisibility(true)
	await h.wait(1.0)
	# As a player who has never picked Story Mode: Relic Hunt is on Small.
	GameWorld.lastLoadoutsByMode.erase("storymode")
	stage.gameModeSelected("relichunt")
	await h.wait(1.5)
	stage.mapSizeSelected("regular-small")
	await h.wait(0.5)
	stage.gameModeSelected("storymode")
	await h.wait(2.0)
	var block = stage.find_child("BlockRelicHuntLoadout", true, false)
	var list = block.find_child("MapSizeList", true, false)
	h.check("map size list shown", list.visible and list.is_visible_in_tree())
	var choices: Dictionary = {}
	for c in stage.find_child("MapsizeContainers").get_children():
		if not c is Label:
			choices[c.id] = {"enabled": not c.disabled, "selected": c.selected}
	h.check("four sizes, all open", choices.size() == 4 and choices.values().all(func(v): return v.enabled), choices)
	h.check("Story Mode's own default (Medium), not Relic Hunt's size", Level.loadout.modeConfig.get(CONST.MODE_CONFIG_MAP_ARCHETYPE) == "regular-medium" and choices.get("regular-medium", {}).get("selected", false), Level.loadout.modeConfig)
	var xf: Transform2D = list.get_global_transform()
	h.keeper().teleport(xf.origin + list.size * xf.get_scale() * 0.5)
	await h.wait(1.5)
	await h.shot("story_sizes")
	stage.mapSizeSelected("regular-small")
	await h.wait(1.0)
	await h.shot("story_small_picked")
	h.check("small picked", Level.loadout.modeConfig.get(CONST.MODE_CONFIG_MAP_ARCHETYPE) == "regular-small", Level.loadout.modeConfig)
	# Away to Relic Hunt and back: Story Mode keeps its pick.
	stage.gameModeSelected("relichunt")
	await h.wait(1.5)
	stage.mapSizeSelected("regular-large")
	await h.wait(0.5)
	stage.gameModeSelected("storymode")
	await h.wait(1.5)
	h.check("small kept after a trip to Relic Hunt", Level.loadout.modeConfig.get(CONST.MODE_CONFIG_MAP_ARCHETYPE) == "regular-small", Level.loadout.modeConfig)
	stage.startRun()
	var started: bool = await h.until(func(): return Level.stage is LevelStage and Level.map != null and Level.map.isMapReady(), 180.0)
	h.check("run started", started)
	if not started:
		return
	h.disable_waves()
	h.mute_beats()
	await h.wait(3.0)
	var td = Level.map.tileData
	var chamber: Rect2i = td.get_meta("story_boss_chamber", Rect2i())
	var used: Rect2i = td.get_used_rect()
	h.note("small run map", {"used_rect": used, "chamber": chamber, "size_meta": td.get_meta("story_map_size", "")})
	h.check("small story map", Level.loadout.modeId == "storymode" and td.get_meta("story_map_size", "") == "regular-small" and chamber.size.x > 0 and chamber.position.y < 120, {"chamber": chamber})
	await h.shot("small_run")
	h.map_png("small_run_map")
