extends "res://content/drop/Drop.gd"

# Miner bones (#94), carried home like a mineral piece. The dome's shredder
# takes them as iron (drops/delivery.gd, StoryDropTrigger.gd), and so does the
# teleporter's suction (#319); they pay
# `value` dollars, set by Map.destroyTile from the biome they were found in
# (data/bones.gd), and keep it through a save and reload. Selling them opens
# that biome's data log.

const Assets = preload("res://mods-unpacked/flantor-StoryMode/util/assets.gd")
static var _Assets = Assets  # calls go through this: lazy_preload makes const-preload calls slow
const Delivery = preload("res://mods-unpacked/flantor-StoryMode/drops/delivery.gd")
static var _Delivery = Delivery  # calls go through this: lazy_preload makes const-preload calls slow
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
static var _StoryBeats = StoryBeats  # calls go through this: lazy_preload makes const-preload calls slow
const SalePops = preload("res://mods-unpacked/flantor-StoryMode/hud/sale_pops.gd")
static var _SalePops = SalePops  # calls go through this: lazy_preload makes const-preload calls slow

# Seconds the bones' "+$X" pop stays readable before their log opens.
const LOG_AFTER_POP := 1.1

var value: int = 0
var biome: int = 0


func _ready():
	var tex: Texture2D = _Assets.tex("res://mods-unpacked/flantor-StoryMode/art/items/minerbones.png")
	if tex != null:
		$Sprite2D.texture = tex
	var trigger: Node = get_node_or_null("DropEnterTrigger")
	if trigger != null:
		trigger.set_script(load("res://mods-unpacked/flantor-StoryMode/drops/StoryDropTrigger.gd"))
	super._ready()


func shred(teamId: String):
	var was: bool = absorbed
	super(teamId)
	if not was:
		_sold(teamId)


# Vanilla also takes a drop by shrinking it, counted the way shred counts it:
# the teleporter's suction (#319), and the crushers of domes whose shredder
# shrinks what it takes (dome3's Shredder3, dome4's Shredder4). Bones taken
# that way are sold the same.
func shrink(teamId: String):
	var was: bool = absorbed
	super(teamId)
	if not was:
		_sold(teamId)


func _sold(teamId: String) -> void:
	if multiplayer.is_server() and teamId != "" and value > 0:
		Data.changeByInt(teamId + ".inventory.money", value)
		var pop_in: float = _SalePops.pop(value, SalePops.BONES)
		ModLoaderLog.info("Miner bones from B%d sold for $%d" % [biome + 1, value], "flantor-StoryMode")
		# The miner's pad comes home with the bones: its log opens once per run,
		# after the bones' pop has been on screen long enough to read (#136).
		if _StoryBeats.fire("log_b%d" % (biome + 1)):
			_StoryBeats.hold(pop_in + LOG_AFTER_POP)


func serialize() -> Dictionary:
	var d: Dictionary = super()
	d["story.value"] = value
	d["story.biome"] = biome
	return d


func deserialize(data: Dictionary):
	super(data)
	value = int(data.get("story.value", 0))
	biome = int(data.get("story.biome", 0))


# Vanilla's stuck check misses a drop wedged against a frozen body (#327).
func processIndependantStuckResolver(delta):
	_Delivery.resolve_stuck(self, delta)
