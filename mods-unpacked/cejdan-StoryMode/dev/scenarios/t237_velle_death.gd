extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# #237: the keeper, down to its last heart, is killed by one of Velle's orbs
# while other orbs are still in the air. The hit ends the run (the director
# clears the orbs from inside _update_orbs' loop); the run must go on to the
# lost ending with no script errors and no USER ERRORs from mod code (the
# boss sounds' cleanup timers used to log "Lambda capture at index 0 was
# freed" for every sound that had finished on its own).

const Director = preload("res://mods-unpacked/cejdan-StoryMode/boss/boss_director.gd")
const Boss = preload("res://mods-unpacked/cejdan-StoryMode/data/boss.gd")
const KeeperHealth = preload("res://mods-unpacked/cejdan-StoryMode/boss/keeper_health.gd")
const TIMEOUT := 300

var _cause: String = ""


func boot() -> Dictionary:
	return {"seed": 12345}


# Error lines in this run's godot.log since the scenario began (the engine
# flushes the log on errors). Boot-time noise (missing translations, the
# loader's own complaints) comes before that. Returned with "ERROR" spelled
# "E_RROR", so printing them does not add more.
func _log_errors(h) -> Array:
	var out: Array = []
	var f: FileAccess = FileAccess.open(h.out_dir.path_join("godot.log"), FileAccess.READ)
	if f == null:
		return ["(no godot.log)"]
	var lines: PackedStringArray = f.get_as_text().split("\n")
	var begun: bool = false
	for i in lines.size():
		var l: String = lines[i]
		if l.begins_with("[harness] scenario begin"):
			begun = true
		if not begun or l.begins_with("[harness]") or l.contains("localization_"):
			continue
		if l.contains("SCRIPT ERROR") or l.contains("USER ERROR"):
			var at: String = lines[i + 1].strip_edges() if i + 1 < lines.size() else ""
			out.append((l.strip_edges() + " | " + at).replace("ERROR", "E_RROR"))
	return out


func run(h) -> void:
	h.disable_waves()
	var dev = load("res://mods-unpacked/cejdan-StoryMode/dev/boss_dev.gd")
	dev.give_gear()   # every keeper's gear, Heat Shielding IV too (#265)
	var ch: Rect2i = Level.map.tileData.get_meta("story_boss_chamber")
	var area: Array = []
	for y in range(ch.position.y - 3, ch.end.y + 2):
		for x in range(ch.position.x - 2, ch.end.x + 2):
			area.append(Vector2i(x, y))
	await h.reveal(area)
	await h.teleport_tile(ch.position + Vector2i(3, 2))
	var started: bool = await h.until(func(): return Director.current() == "fight", 8.0)
	h.check("the fight starts", started, Director.current())
	if not started:
		return
	var boss = Director.instance()
	var velle = boss.velle
	var health = boss.health
	health.died.connect(func(cause: String): _cause = cause)
	await h.until(func(): return velle.state == "fight", 8.0)
	# Nothing hits the keeper while the stage is set.
	health.invulnerable = 99999.0
	await h.wait(1.5)
	h.check("no errors before the hit", _log_errors(h).is_empty(), _log_errors(h))
	velle.attack_enabled = false
	velle.spawn_bombs = false
	velle.attacks.clear()
	velle.orbs.clear()
	Data.apply(KeeperHealth.KEY, 1)
	await h.wait(0.3)
	await h.shot("last_heart")
	# Two orbs hanging in the chamber's middle, then the one on the keeper:
	# _update_orbs runs from the end, so the killing orb is index 2 and two
	# more are still to come in the same loop.
	var kp: Vector2 = velle.to_local(h.keeper().global_position)
	var mid: Vector2 = velle.arena.position + Vector2(velle.arena.size.x * 0.5, 18.0)
	h.check("the hanging orbs are far from the keeper", mid.distance_to(kp) > 60.0, [mid, kp])
	velle.orbs.append({"p": mid, "v": Vector2.ZERO, "life": 7.0, "r": 4.0})
	velle.orbs.append({"p": mid + Vector2(14, 0), "v": Vector2.ZERO, "life": 7.0, "r": 4.0})
	velle.orbs.append({"p": kp, "v": Vector2(0, 1), "life": 7.0, "r": 4.0})
	health.invulnerable = 0.0
	var died: bool = await h.until(func(): return health.dead, 3.0)
	h.check("an orb kills the keeper on its last heart", died and _cause == "orb" and health.hearts() == 0, {"dead": health.dead, "cause": _cause, "hearts": health.hearts()})
	h.check("the boss sequence is lost", Director.current() == "lost", Director.current())
	await h.wait(0.6)
	await h.shot("keeper_down")
	h.check("Velle's orbs and attacks are gone", velle.orbs.is_empty() and velle.attacks.is_empty(), [velle.orbs.size(), velle.attacks.size()])
	h.check("no errors from the killing hit", _log_errors(h).is_empty(), _log_errors(h))
	var ed = Level.mode.get_node_or_null("StoryEndings")
	await h.until(func(): return ed != null and ed.playing == "fallen", 10.0)
	h.check("the fallen ending plays", ed != null and ed.playing == "fallen", ed.playing if ed != null else null)
	var panel_up: bool = await h.until(func(): return Level.stage.endingPanel != null, 120.0)
	await h.wait(3.0)
	await h.shot("end_screen")
	h.check("the lost run's end screen shows", panel_up and GameWorld.lost and not GameWorld.won, [panel_up, GameWorld.lost, GameWorld.won])
	await h.wait(2.0)
	var errs: Array = _log_errors(h)
	h.check("zero script errors and USER ERRORs in the whole run", errs.is_empty(), errs)
