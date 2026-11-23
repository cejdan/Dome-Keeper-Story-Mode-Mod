extends "res://content/shared/drops/DropEnterTrigger.gd"

# The dome's areas ask each drop that enters them for a vanilla type: the
# shredder "are you iron / water / sand / pack?", the relic socket "are you a
# relic?". A Story Mode drop answers yes to the type it is delivered as
# (drops/delivery.gd: minerals and miner bones as iron, a translator as a
# relic), so the dome takes it without its scripts being touched (the
# shredders' subclasses extend them by class name, which a script extension
# breaks). The piece keeps its own type, so it is credited as itself.

const Delivery = preload("res://mods-unpacked/flantor-StoryMode/drops/delivery.gd")
static var _Delivery = Delivery  # calls go through this: lazy_preload makes const-preload calls slow


func getDeliverableDrop(type: String):
	var p = get_parent()
	if type == _Delivery.as_vanilla(p.type) and not p.absorbed and not p.independent:
		return p
	return super(type)
