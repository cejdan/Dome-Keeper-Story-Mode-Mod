extends "res://content/dome/dome3/dome3.gd"

# The Artillery Dome, like every other dome (extensions/content/dome/Dome.gd):
# Story Mode minerals are delivered to the shredder, like iron. Its script
# says `extends Dome` and so sits on vanilla's Dome, not on our extension of
# it (#252; extensions/installer.gd), so it needs its own.

const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")


func getDropTarget(dropType: String):
	if Minerals.is_mod_mineral(dropType):
		return $Shredder
	return super(dropType)
