extends "res://content/gadgets/mineraltree/FruitGrowth.gd"

# A gold fruit for Story Mode's Mineral Tree (#55): it hangs and grows like an
# iron fruit and drops gold.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
const Assets = preload("res://mods-unpacked/flantor-StoryMode/util/assets.gd")
static var _Assets = Assets  # calls go through this: lazy_preload makes const-preload calls slow


func setType(type: String):
	if type != "gold":
		super(type)
		return
	super(CONST.IRON)
	self.type = "gold"
	$Sprite2D.texture = _Assets.tex(Story.MOD_DIR + "art/minerals/drop_gold.png")
