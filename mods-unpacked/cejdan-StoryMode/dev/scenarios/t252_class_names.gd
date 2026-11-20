extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# #252, #256: no script loses a class_name to the script extensions
# (extensions/installer.gd says why it would).
#
# 1. Rescans the project: every script that names an extended class_name in a
#    type (extends, typed var / param / return, is, as, Array[...]) must be in
#    Installer.NAMED_BY, every scene using an extended script in SCENES, and
#    an extension naming another extended class must install before it.
# 2. Loads every one of them: each must already be cached (compiled before the
#    install) and compile; DeviceSelectionMap and (vanilla) Dome3 must sit on
#    vanilla's Map and Dome, the bases our extensions extend. A late compile would log
#    its error inside the scenario window, which log_scan fails.
# 3. Shows the mechanism live: a script compiled now gets `x is CaveBomb`
#    true for a plain Node; this one (compiled at boot) gets it right.
#
# `-Extra "--noclasshold"` runs it without the hold, for the before picture.

const Installer = preload("res://mods-unpacked/cejdan-StoryMode/extensions/installer.gd")
const TIMEOUT := 240

var _names: Dictionary = {}  # class_name -> vanilla path


func boot() -> Dictionary:
	return {"seed": 12345}


func _walk(dir: String, ext: Array, out: Array) -> void:
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var f: String = d.get_next()
	while f != "":
		var p: String = dir.path_join(f)
		if d.current_is_dir():
			if not f.begins_with("."):
				_walk(p, ext, out)
		elif f.get_extension() in ext:
			out.append(p)
		f = d.get_next()
	d.list_dir_end()


# Class names `src` uses in a type position, comments and strings left out.
func _named(src: String, re: RegEx, strings: RegEx) -> Array:
	var hits: Dictionary = {}
	for line: String in src.split("\n"):
		var s: String = strings.sub(line, "\"\"", true)
		var hash: int = s.find("#")
		if hash >= 0:
			s = s.substr(0, hash)
		for m: RegExMatch in re.search_all(s):
			hits[m.get_string(2)] = true
	return hits.keys()


func run(h) -> void:
	# The extended scripts and their class_names.
	var paths: Dictionary = {}
	for k in ModLoaderStore.saved_scripts.keys():
		paths[str(k)] = true
	for rel: String in Installer.EXTENSIONS:
		h.check("installed " + rel, paths.has("res://" + rel))
	for c: Dictionary in ProjectSettings.get_global_class_list():
		if paths.has(str(c.path)):
			_names[str(c["class"])] = str(c.path)
	h.note("extended class_names", _names)

	# 1. Rescan.
	var re := RegEx.new()
	re.compile("(\\bextends\\s+|\\bis\\s+|\\bas\\s+|:\\s*|->\\s*|\\[\\s*)(%s)\\b" % "|".join(_names.keys()))
	var strings := RegEx.new()
	strings.compile("\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'")
	var scripts: Array = []
	_walk("res://", ["gd"], scripts)
	var users: Dictionary = {}
	for p: String in scripts:
		var n: Array = _named(FileAccess.get_file_as_string(p), re, strings)
		if not n.is_empty():
			users[p] = n
	h.note("scripts scanned", scripts.size())
	var missing: Array = []
	var ext_dir: String = Installer.EXT
	for p: String in users:
		if p.begins_with(ext_dir) or paths.has(p):
			# An extension compiles as it installs, and so does a copy of its
			# vanilla base: the classes either names (other than its own) must
			# not have been taken over yet.
			var rel: String = p.trim_prefix(ext_dir) if p.begins_with(ext_dir) else p.trim_prefix("res://")
			var mine: int = Installer.EXTENSIONS.find(rel)
			for c: String in users[p]:
				var theirs: int = Installer.EXTENSIONS.find(_names[c].trim_prefix("res://"))
				if theirs != mine:
					h.check("%s installs before %s's extension (%s names it)" % [rel, c, p], mine < theirs, {"mine": mine, "theirs": theirs})
		elif p.contains("/dev/scenarios/"):
			pass  # compiled at boot (Story.scenario_boot)
		elif not Installer.NAMED_BY.has(p):
			missing.append("%s (%s)" % [p, ", ".join(users[p])])
	h.check("NAMED_BY lists every script naming an extended class (%d found)" % users.size(), missing.is_empty(), missing)
	var stale: Array = []
	for p: String in Installer.NAMED_BY:
		if not users.has(p):
			stale.append(p)
	h.check("NAMED_BY has no stale entries", stale.is_empty(), stale)
	var scenes: Array = []
	_walk("res://", ["tscn", "tres"], scenes)
	var scene_missing: Array = []
	for p: String in scenes:
		if p.begins_with("res://mods-unpacked/"):
			continue
		var t: String = FileAccess.get_file_as_string(p)
		for sp: String in paths:
			if t.contains("path=\"%s\"" % sp) and not Installer.SCENES.has(p):
				scene_missing.append(p)
	h.check("SCENES lists every scene using an extended script", scene_missing.is_empty(), scene_missing)

	# 2. Each compiled before the install, and compiles.
	var compiled: Array = []
	var late: Array = []
	var broken: Array = []
	for p: String in Installer.NAMED_BY + paths.keys():
		if not ResourceLoader.exists(p):
			continue
		if not ResourceLoader.has_cached(p):
			late.append(p)
		var s: Script = load(p)
		if s == null or not s.can_instantiate():
			broken.append(p)
		else:
			compiled.append(p)
	h.note("compiled", compiled.size())
	h.check("every listed script was compiled before the install", late.is_empty(), late)
	h.check("every listed script compiles", broken.is_empty(), broken)
	var map_ext: Script = load("res://content/map/Map.gd")
	var dome_ext: Script = load("res://content/dome/Dome.gd")
	var dsm: Script = load("res://stages/deviceselection/DeviceSelectionMap.gd")
	var dome3: Script = load("res://content/dome/dome3/dome3.gd")
	h.check("Map.gd's path holds the extension", map_ext.resource_path == "res://content/map/Map.gd" and map_ext.get_base_script() != null and map_ext.get_base_script().get_global_name() == &"Map")
	h.check("DeviceSelectionMap extends vanilla Map", dsm.can_instantiate() and dsm.get_base_script() == map_ext.get_base_script())
	# dome3.gd's path holds its own extension (the Artillery Dome takes Story
	# Mode minerals too); vanilla dome3.gd under it sits on vanilla Dome.
	var dome3_vanilla: Script = dome3.get_base_script()
	h.check("Dome3 (vanilla, under its extension) extends vanilla Dome", dome3.can_instantiate() and dome3_vanilla != null and dome3_vanilla.get_global_name() == &"Dome3" and dome3_vanilla.get_base_script() == dome_ext.get_base_script())

	# 3. The mechanism, live.
	var probe := Node.new()
	var fresh := GDScript.new()
	fresh.source_code = "extends RefCounted\nfunc t(x) -> bool:\n\treturn x is CaveBomb\n"
	fresh.reload()
	var late_is: bool = fresh.new().t(probe)
	h.note("a script compiled now: plain Node is CaveBomb", late_is)
	h.check("this script (compiled at boot): plain Node is not CaveBomb", not (probe is CaveBomb))
	h.check("this script: the run's map is a Map, its stage a LevelStage", Level.map is Map and Level.stage is LevelStage and not (Level.map is Dome))
	var dome_node = Level.getDome("team1")
	h.check("this script: the run's dome is a Dome running the extension", dome_node is Dome and dome_node.get_script() == dome_ext, str(dome_node.get_script().resource_path) if dome_node else "")
	probe.free()
