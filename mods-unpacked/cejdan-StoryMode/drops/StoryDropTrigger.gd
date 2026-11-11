extends "res://content/shared/drops/DropEnterTrigger.gd"

# The dome shredder asks each drop that enters it "are you iron / water / cobalt?".
# A Story Mode mineral answers yes to the iron question, so the shredder takes it
# without the shredder script being touched (its subclasses extend it by class
# name, which a script extension breaks). The piece keeps its own type, so it is
# credited as that mineral.


func getDeliverableDrop(type: String):
	var p = get_parent()
	if type == "iron" and not p.absorbed and not p.independent:
		return p
	return super(type)
