extends RefCounted

# Shared Story Mode facts. Scripts preload this file and call its static helpers,
# so "is this run Story Mode?" has one answer everywhere.

const MODE_ID := "storymode"
const LOG := "cejdan-StoryMode"
const MOD_DIR := "res://mods-unpacked/cejdan-StoryMode/"
# Older lava code looks for this flag in the loadout's modeConfig.
const MODE_FLAG := "cejdan-storymode"
# Map-data meta holding the run's level seed, so a load can restore it (#116).
const SEED_META := "story_seed"


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
