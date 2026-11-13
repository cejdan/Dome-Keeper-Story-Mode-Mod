extends "res://content/drop/Drop.gd"

# Miner bones (#94), carried home like a mineral piece. The dome's shredder
# takes them as iron (StoryDropTrigger); they pay `value` dollars, set by
# Map.destroyTile from the biome they were found in (data/bones.gd), and keep
# it through a save and reload. Selling them opens that biome's data log.

const Assets = preload("res://mods-unpacked/cejdan-StoryMode/util/assets.gd")
const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const SalePops = preload("res://mods-unpacked/cejdan-StoryMode/hud/sale_pops.gd")

# Seconds the bones' "+$X" pop stays readable before their log opens.
const LOG_AFTER_POP := 1.1

var value: int = 0
var biome: int = 0


func _ready():
	var tex: Texture2D = Assets.tex("res://mods-unpacked/cejdan-StoryMode/art/items/minerbones.png")
	if tex != null:
		$Sprite2D.texture = tex
	var trigger: Node = get_node_or_null("DropEnterTrigger")
	if trigger != null:
		trigger.set_script(load("res://mods-unpacked/cejdan-StoryMode/drops/StoryDropTrigger.gd"))
	super._ready()


func shred(teamId: String):
	var was: bool = absorbed
	super(teamId)
	if not was and multiplayer.is_server() and value > 0:
		Data.changeByInt(teamId + ".inventory.money", value)
		var pop_in: float = SalePops.pop(value, SalePops.BONES)
		ModLoaderLog.info("Miner bones from B%d sold for $%d" % [biome + 1, value], "cejdan-StoryMode")
		# The miner's pad comes home with the bones: its log opens once per run,
		# after the bones' pop has been on screen long enough to read (#136).
		if StoryBeats.fire("log_b%d" % (biome + 1)):
			StoryBeats.hold(pop_in + LOG_AFTER_POP)


func serialize() -> Dictionary:
	var d: Dictionary = super()
	d["story.value"] = value
	d["story.biome"] = biome
	return d


func deserialize(data: Dictionary):
	super(data)
	value = int(data.get("story.value", 0))
	biome = int(data.get("story.biome", 0))
