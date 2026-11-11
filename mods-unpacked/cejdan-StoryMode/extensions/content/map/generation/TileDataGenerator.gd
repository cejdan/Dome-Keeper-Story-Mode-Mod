extends "res://content/map/generation/TileDataGenerator.gd"

# Story Mode map generation. Only maps made from an archetype tagged by the mod
# (`story_map` meta, set in prepareGameMode) are touched.

const StoryGen = preload("res://mods-unpacked/cejdan-StoryMode/map/story_gen.gd")


func generate_resources(rand):
	super(rand)
	if a != null and a.has_meta("story_map"):
		StoryGen.after_resources(self, _mapData, rand)
