extends "res://content/hud/inventory/Inventory.gd"

# In Story Mode iron is a mineral sold for dollars, not a stock to spend, so the
# resource counters show only water and cobalt. Vanilla modes are unchanged.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow


func init():
	super.init()
	if _Story.is_story():
		var grid: Node = get_node_or_null("GridContainer")
		if grid != null:
			grid.get_node("TextureRect1").visible = false
			%LabelIron.visible = false
		element_size.y = 4


func updateSize():
	if _Story.is_story():
		cache[0] = 0
	super.updateSize()
