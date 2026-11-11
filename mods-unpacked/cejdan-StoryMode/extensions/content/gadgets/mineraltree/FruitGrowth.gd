extends "res://content/gadgets/mineraltree/FruitGrowth.gd"

# A gold fruit for Story Mode's Mineral Tree (#55): it hangs and grows like an
# iron fruit and drops gold.

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const Assets = preload("res://mods-unpacked/cejdan-StoryMode/util/assets.gd")


func setType(type: String):
	if type != "gold":
		super(type)
		return
	super(CONST.IRON)
	self.type = "gold"
	$Sprite2D.texture = Assets.tex(Story.MOD_DIR + "art/minerals/drop_gold.png")
