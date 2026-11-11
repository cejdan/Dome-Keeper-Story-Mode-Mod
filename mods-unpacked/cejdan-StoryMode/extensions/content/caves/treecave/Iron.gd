extends "res://content/caves/treecave/Iron.gd"

# The Iron Tree cave's fruit grows gold in Story Mode (#55). The regrow timer
# is vanilla's. Vanilla modes keep iron.

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const Assets = preload("res://mods-unpacked/cejdan-StoryMode/util/assets.gd")

const GOLD := "gold"


func _ready():
	super()
	if Story.is_story():
		$Sprite2D.texture = Assets.tex(Story.MOD_DIR + "art/minerals/drop_gold.png")


func registerHit(playerId: String):
	if not Story.is_story():
		super(playerId)
		return
	if taken:
		return
	taken = true
	visible = false
	var teamId = Keepers.getKeeper(playerId).teamId
	if multiplayer.is_server():
		Level.drops.network_spawn({
			"type": GOLD,
			"position": $Sprite2D.global_position,
			"carriers": [playerId],
			"team": teamId,
		})
		regrowCooldown = GameWorld.getTimeBetweenWaves(teamId) * Data.stabilizedRandomFloat(0.2, 2.1, "ironcave", 2)
