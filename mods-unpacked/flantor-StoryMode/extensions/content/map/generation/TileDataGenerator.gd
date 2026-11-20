extends "res://content/map/generation/TileDataGenerator.gd"

# Story Mode map generation. Only maps made from an archetype tagged by the mod
# (`story_map` meta, set in prepareGameMode) are touched.

const StoryGen = preload("res://mods-unpacked/flantor-StoryMode/map/story_gen.gd")
static var _StoryGen = StoryGen  # calls go through this: lazy_preload makes const-preload calls slow


func generate_resources(rand):
	super(rand)
	if a != null and a.has_meta("story_map"):
		_StoryGen.after_resources(self, _mapData, rand)
