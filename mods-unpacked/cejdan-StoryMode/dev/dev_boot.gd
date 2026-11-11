extends Node

# Dev boot switches (editor binary only). Vanilla dev mode always boots a
# hard-coded Versus run; these user args (after `--`) boot something else:
#   --story              a Story Mode run (same as --mode=storymode)
#   --mode=<id>          a run in that game mode (e.g. relichunt, for vanilla checks)
#   --loadout            the loadout screen
#   --seed=<n>           fixed map seed
#   --gadget=<id>        primary gadget (default shield)
#   --difficulty=<n>     -2, -1, 0 or 2
#   --world=<worldN>     fixed world; --palette=<name> fixed palette
#   --mapsize=<id>       vanilla archetype for vanilla modes (default regular-medium)
# A playtest scenario's boot() dictionary can give the same keys.
#
# How: Game.gd cannot be script-extended safely (loading it early enough breaks
# the parsing of other vanilla scripts). Instead this node puts a DomeEditorConf
# in the resource cache at the path Game._ready() reads, asking for a play mode
# that does not exist. Vanilla then starts no stage at all, and this node starts
# the wanted one on the next frame. No vanilla file is touched.

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")

var _conf: Resource
var _mode_id: String = ""
var _done: bool = false


static func wanted() -> bool:
	if not OS.has_feature("editor"):
		return false
	for n: String in ["story", "scenario", "mode", "loadout"]:
		if Story.has_user_arg(n):
			return true
	return false


func _ready() -> void:
	_mode_id = Story.user_arg("mode", "")
	if _mode_id == "" and not Story.has_user_arg("loadout"):
		_mode_id = Story.MODE_ID
	_conf = load("res://addons/dome_editor_ext/dome_editor_conf.gd").new()
	_conf.custom_play_pressed = true
	_conf.play_mode = 99
	_conf.take_over_path(Const.EDITOR_CONF_PATH)


func _process(_delta: float) -> void:
	if _done or get_tree().current_scene == null:
		return
	_done = true
	set_process(false)
	if _mode_id == "":
		StageManager.startStage("stages/loadout/multiplayerloadout")
	else:
		_start_run(_mode_id)


func _start_run(mode_id: String) -> void:
	print("RUNNING IN DEV MODE (Story Mode dev boot: " + mode_id + ")")
	if Story.has_user_arg("seed"):
		Level.setSeed(int(Story.user_arg("seed")))
	var loadout: Loadout = Loadout.default()
	var ld1: LoadoutDome = LoadoutDome.new()
	ld1.primaryGadgetId = Story.user_arg("gadget", "shield")
	ld1.domeId = Story.user_arg("dome", "dome1")
	ld1.teamId = "team1"
	ld1.petId = ""
	ld1.additionalGadgets = []
	loadout.domes = [ld1]
	loadout.modeId = mode_id
	loadout.modeConfig = {CONST.MODE_CONFIG_MAP_ARCHETYPE: Story.user_arg("mapsize", CONST.MAP_MEDIUM)}
	var diff: int = int(Story.user_arg("difficulty", "0"))
	loadout.difficultyByTeamId = {"team1": diff, "map": diff}
	loadout.worldId = Story.user_arg("world", "")
	loadout.palette = Story.user_arg("palette", "")
	var lk1: LoadoutKeeper = LoadoutKeeper.new()
	lk1.playerId = "player1"
	lk1.teamId = "team1"
	lk1.keeperId = Story.user_arg("keeper", "keeper1")
	lk1.skinId = "skin0"
	lk1.deviceId = 0
	lk1.peerId = 1
	lk1.tutorialsActive = false
	loadout.keepers = [lk1]
	Lobby.simple_add(lk1.deviceId)
	var member = Lobby.get_member_by_player_id(lk1.playerId)
	member.keeper_id = Utils.encode_tech_id(lk1.keeperId)
	Lobby.send_lobby_update()
	var startData: LevelStartData = LevelStartData.new()
	startData.loadout = loadout
	StageManager.startStage("stages/landing/landing", [startData])
