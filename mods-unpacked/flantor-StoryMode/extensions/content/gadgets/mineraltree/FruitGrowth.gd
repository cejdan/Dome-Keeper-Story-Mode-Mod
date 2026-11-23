extends "res://content/gadgets/mineraltree/FruitGrowth.gd"

# A Story Mode mineral fruit for the Mineral Tree (#55, #328): it hangs and
# grows like an iron fruit and drops its mineral. Iron fruit in Story Mode
# shows the mod's grey iron, the drop it falls as there.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const Assets = preload("res://mods-unpacked/flantor-StoryMode/util/assets.gd")
static var _Assets = Assets  # calls go through this: lazy_preload makes const-preload calls slow
const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
static var _Minerals = Minerals  # calls go through this: lazy_preload makes const-preload calls slow


func setType(type: String):
	if type == CONST.IRON and _Story.is_story():
		super(type)
		$Sprite2D.texture = _Assets.tex(Story.MOD_DIR + "art/minerals/drop_iron.png")
		return
	if not _Minerals.is_mod_mineral(type):
		super(type)
		return
	super(CONST.IRON)
	self.type = type
	$Sprite2D.texture = _Assets.tex(Story.MOD_DIR + "art/minerals/drop_%s.png" % type)
