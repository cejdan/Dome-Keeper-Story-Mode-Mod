extends "res://content/hud/inventory/Inventory.gd"

# In Story Mode iron is a mineral sold for dollars, not a stock to spend, so the
# resource counters show only water and cobalt. Vanilla modes are unchanged.

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")


func init():
	super.init()
	if Story.is_story():
		var grid: Node = get_node_or_null("GridContainer")
		if grid != null:
			grid.get_node("TextureRect1").visible = false
			%LabelIron.visible = false
		element_size.y = 4


func updateSize():
	if Story.is_story():
		cache[0] = 0
	super.updateSize()
