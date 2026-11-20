extends RefCounted

# Shared Story Mode facts. Scripts preload this file and call its static helpers,
# so "is this run Story Mode?" has one answer everywhere.

const MODE_ID := "storymode"
const LOG := "flantor-StoryMode"
const MOD_DIR := "res://mods-unpacked/flantor-StoryMode/"
# Older lava code looks for this flag in the loadout's modeConfig.
const MODE_FLAG := "flantor-storymode"
# Map-data meta holding the run's level seed, so a load can restore it (#116).
const SEED_META := "story_seed"
# The boss sequence's step (boss/boss_director.gd).
const BOSS_STATE := "team1.story.boss"


static func is_story() -> bool:
	return Level.loadout != null and Level.loadout.modeId == MODE_ID


static func user_arg(name: String, default: String = "") -> String:
	# `-- --name=value` gives "value"; a bare `--name` gives "true".
	for a: String in OS.get_cmdline_user_args():
		if a == "--" + name:
			return "true"
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
	# A playtest scenario's boot() dictionary stands in for missing args.
	if name != "scenario":
		var b: Dictionary = scenario_boot()
		if b.has(name):
			return str(b[name]).to_lower() if b[name] is bool else str(b[name])
	return default


static var _boot = null


static func scenario_boot() -> Dictionary:
	if _boot == null:
		_boot = {}
		var sc: String = user_arg("scenario")
		var path: String = MOD_DIR + "dev/scenarios/" + sc + ".gd"
		if sc != "" and OS.has_feature("editor") and ResourceLoader.exists(path):
			_boot = load(path).new().boot()
	return _boot


static func has_user_arg(name: String) -> bool:
	var v: String = user_arg(name, "")
	return v != "" and v != "false"


# True through the boss sequence (the chamber fight, the chase and the surface
# finale; boss/boss_director.gd keeps the state). Text holds off meanwhile.
static func boss_active() -> bool:
	return str(Data.ofOr(BOSS_STATE, "")) in ["fight", "chase", "finale"]


# This instance's first keeper, or null while it has none (between stages, or
# while a save loads). Vanilla's Keepers.first() reads index 0 and logs a script
# error when the list is empty, so `Keepers.first() == null` never guards (#249).
static func local_keeper():
	return Keepers.local.keepers[0] if not Keepers.local.keepers.is_empty() else null


# local_keeper()'s playerId, "player1" while there is none.
static func local_pid() -> String:
	var k = local_keeper()
	return str(k.playerId) if k != null and is_instance_valid(k) else "player1"


# Every keeper this instance plays (#231): one per device in splitscreen, one
# in single player and on each online instance (a host with two local players
# has two). Per-keeper systems (heat, toxin, recall, the HUD over a keeper)
# loop over these; the team's side stays with the host.
static func local_keepers() -> Array:
	return Keepers.local.keepers.filter(func(k): return k != null and is_instance_valid(k))


# The world rect player `pid`'s view shows, grown by `grow` px; an empty rect
# without a camera (headless, between stages).
static func view_rect(pid: String, grow: float = 0.0) -> Rect2:
	if Level.viewports == null or not is_instance_valid(Level.viewports):
		return Rect2()
	var cam = Level.viewports.getPlayerCam(pid)
	if cam == null or not is_instance_valid(cam) or not cam.is_inside_tree():
		return Rect2()
	var vs: Vector2 = cam.get_viewport_rect().size / cam.zoom
	return Rect2(cam.get_screen_center_position() - vs / 2.0, vs).grow(grow)


# The world rects the local keepers' split views show (#231).
static func view_rects(grow: float = 0.0) -> Array:
	var out: Array = []
	for k in local_keepers():
		var r: Rect2 = view_rect(k.playerId, grow)
		if r.has_area():
			out.append(r)
	return out


# True when any local keeper's view shows `world_pos` (or there are no views).
static func on_any_view(world_pos: Vector2, grow: float = 0.0) -> bool:
	var rects: Array = view_rects(grow)
	if rects.is_empty():
		return true
	for r: Rect2 in rects:
		if r.has_point(world_pos):
			return true
	return false
