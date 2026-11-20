extends RefCounted

# The small picture of a Story Mode piece that a carrier holds (#270): the drone
# yard's drones, the drone cave's Squidley. The drop art is already the size
# of vanilla's *_smol.png (8-9 px). Null for anything else (vanilla's own).

const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
static var _Minerals = Minerals  # calls go through this: lazy_preload makes const-preload calls slow
const Bones = preload("res://mods-unpacked/flantor-StoryMode/data/bones.gd")
const Assets = preload("res://mods-unpacked/flantor-StoryMode/util/assets.gd")
static var _Assets = Assets  # calls go through this: lazy_preload makes const-preload calls slow


static func of(res: String) -> Texture2D:
	if _Minerals.is_mod_mineral(res):
		return _Assets.tex(Minerals.ART + "drop_%s.png" % res)
	if res == Bones.TYPE:
		return _Assets.tex("res://mods-unpacked/flantor-StoryMode/art/items/minerbones.png")
	return null


# After vanilla's setCarriedResource(CONST.PACK) has added one child per packed
# piece (in packedDropContent order, after any it had): Story pieces get art.
static func fix_pack(holder: Node, packed: Array) -> void:
	var kids: Array = holder.get_children()
	var off: int = kids.size() - packed.size()
	for i in packed.size():
		var a: Texture2D = of(str(packed[i][0]))
		if a != null and off + i >= 0:
			kids[off + i].texture = a
