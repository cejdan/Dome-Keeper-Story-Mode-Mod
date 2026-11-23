extends "res://content/dome/dome3/dome3.gd"

# The Artillery Dome, like every other dome (extensions/content/dome/Dome.gd):
# Story Mode drops are delivered where the vanilla type they stand in for goes
# (drops/delivery.gd). Its script says `extends Dome` and so sits on vanilla's
# Dome, not on our extension of it (#252; extensions/installer.gd), so it needs
# its own.

const Delivery = preload("res://mods-unpacked/flantor-StoryMode/drops/delivery.gd")
static var _Delivery = Delivery  # calls go through this: lazy_preload makes const-preload calls slow


func getDropTarget(dropType: String):
	return super(_Delivery.as_vanilla(dropType))
