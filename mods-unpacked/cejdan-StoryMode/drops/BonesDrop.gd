extends "res://content/drop/Drop.gd"

# Miner bones (#94), carried home like a mineral piece. The dome's shredder
# takes them as iron (StoryDropTrigger); they pay `value` dollars, set by
# Map.destroyTile from the biome they were found in (data/bones.gd), and keep
# it through a save and reload. Selling them opens that biome's data log.

const Assets = preload("res://mods-unpacked/cejdan-StoryMode/util/assets.gd")
const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")

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
		ModLoaderLog.info("Miner bones from B%d sold for $%d" % [biome + 1, value], "cejdan-StoryMode")
		# The miner's pad comes home with the bones: its log opens now, once per run.
		StoryBeats.fire("log_b%d" % (biome + 1))


func serialize() -> Dictionary:
	var d: Dictionary = super()
	d["story.value"] = value
	d["story.biome"] = biome
	return d


func deserialize(data: Dictionary):
	super(data)
	value = int(data.get("story.value", 0))
	biome = int(data.get("story.biome", 0))
