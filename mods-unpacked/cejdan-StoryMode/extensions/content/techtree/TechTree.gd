extends "res://content/techtree/TechTree.gd"

# Vanilla scrolls the shop to centre the focused panel's whole track. A track
# taller than the view (Story Mode's own track has eight rows) would keep its
# top and bottom rows out of sight, so for those the view follows the panel.


func technologyFocussed(techPanel):
	super(techPanel)
	var view = get_parent()
	if techPanel == null or techPanel.track == null or techPanel.track.size.y <= view.size.y * 0.9:
		return
	var y: float = techPanel.global_position.y - view.global_position.y + view.scroll_vertical - view.size.y * 0.5 + techPanel.size.y * 0.5
	$Tween.interpolate_property(view, "scroll_vertical", view.scroll_vertical, y, 0.2, Tween.TRANS_QUAD, Tween.EASE_IN_OUT)
	$Tween.start()
