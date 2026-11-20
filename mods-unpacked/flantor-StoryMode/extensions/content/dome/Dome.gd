extends "res://content/dome/Dome.gd"

# Story Mode minerals are delivered to the shredder, like iron.

const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
static var _Minerals = Minerals  # calls go through this: lazy_preload makes const-preload calls slow


func getDropTarget(dropType: String):
	if _Minerals.is_mod_mineral(dropType):
		return $Shredder
	return super(dropType)
