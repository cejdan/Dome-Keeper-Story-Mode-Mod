extends "res://stages/level/GadgetChoiceInputProcessor.gd"

# Vanilla's gadget choice, for a Story Mode shop slot: the player opened it on
# purpose, so Cancel closes it without buying (offers are kept for next time).


func buttonEvent(event) -> bool:
	if justPressed(event, "ui_cancel") and popup.animationDone:
		Audio.sound("gui_cancel")
		desintegrate()
		return true
	return super(event)
