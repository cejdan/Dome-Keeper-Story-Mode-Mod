extends "res://content/dome/Dome.gd"

# Story Mode drops are delivered where the vanilla type they stand in for
# goes (drops/delivery.gd): minerals and miner bones to the shredder, a
# translator to the relic socket. Taking a dome station sends every carried
# drop to this target (Keeper.enterStation); without one a drop is let go of
# and falls down the shaft, unpickable (#327).

const Delivery = preload("res://mods-unpacked/flantor-StoryMode/drops/delivery.gd")
static var _Delivery = Delivery  # calls go through this: lazy_preload makes const-preload calls slow


func getDropTarget(dropType: String):
	return super(_Delivery.as_vanilla(dropType))
