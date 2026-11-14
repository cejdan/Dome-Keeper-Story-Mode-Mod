extends "res://content/shared/drops/DropEnterTrigger.gd"

# The dome's relic socket asks "are you a relic?"; a translator says yes, so
# the socket takes it. The drop keeps its own type, so it is credited as
# team1.inventory.translator.


func getDeliverableDrop(type: String):
	var p = get_parent()
	if type == "relic" and not p.absorbed and not p.independent:
		return p
	return super(type)
