extends "res://content/caves/treecave/Iron.gd"

# The Iron Tree cave's fruit grows gold in Story Mode (#55). The regrow timer
# is vanilla's. Vanilla modes keep iron.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const Assets = preload("res://mods-unpacked/flantor-StoryMode/util/assets.gd")
static var _Assets = Assets  # calls go through this: lazy_preload makes const-preload calls slow

const GOLD := "gold"


func _ready():
	super()
	if _Story.is_story():
		$Sprite2D.texture = _Assets.tex(Story.MOD_DIR + "art/minerals/drop_gold.png")


func registerHit(playerId: String):
	if not _Story.is_story():
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
