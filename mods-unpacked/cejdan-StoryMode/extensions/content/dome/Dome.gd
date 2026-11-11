extends "res://content/dome/Dome.gd"

# Story Mode minerals are delivered to the shredder, like iron.

const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")


func getDropTarget(dropType: String):
	if Minerals.is_mod_mineral(dropType):
		return $Shredder
	return super(dropType)
