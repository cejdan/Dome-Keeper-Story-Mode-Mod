extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 91: monster pleas during real waves. One wave per plea stage (deepest
# biome B1, B4, B7, the ocean): screenshots of the arrival line over the fight
# and a fight line, last words when the wave is killed, a distant cry at the top
# of the screen while the keeper is down the mine. The log shows the monsters
# and the wave clock running the whole time a plea is up.

const PleaData = preload("res://mods-unpacked/cejdan-StoryMode/data/pleas.gd")

const DEPTHS := {"A": 0, "B": 3, "C": 6, "D": 8}


func boot() -> Dictionary:
	return {"seed": 12345}


func _director():
	return load("res://mods-unpacked/cejdan-StoryMode/pleas/plea_director.gd").instance()


func _monster_xs(h) -> Array:
	var xs: Array = []
	for m in h.get_tree().get_nodes_in_group("team1-monster"):
		xs.append(snappedf(m.global_position.x, 0.1))
	return xs


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	var pd = _director()
	h.check("the pleas director is in the run", pd != null)
	pd.death_chance = 1.0
	Data.apply("team1.dome.maxHealth", 1000000)
	Data.apply("team1.dome.health", 1000000)
	h.enable_waves()
	GameWorld.runStarted = true
	var mm = Level.monstersByTeamId["team1"]
	for st: String in ["A", "B", "C", "D"]:
		Data.apply("team1.story.deepest", DEPTHS[st])
		h.check("stage %s for deepest %d" % [st, DEPTHS[st]], pd.stage() == st)
		var n0: int = pd.shown.size()
		Data.apply("team1.monsters.wavecooldown", 2)
		var came: bool = await h.until(func(): return Data.of("team1.monsters.wavepresent"), 40.0)
		h.check("stage %s: a wave arrives" % st, came)
		await h.until(func(): return pd.shown.size() > n0, 3.0)
		var arrive: Dictionary = pd.shown[n0] if pd.shown.size() > n0 else {}
		h.check("stage %s: the arrival line comes from pool %s/arrive" % [st, st], arrive.get("kind", "") == "arrive" and PleaData.pool(st, "arrive").has(arrive.get("line", "")), arrive)
		# While the line is up: monsters move, the wave clock runs, nothing paused.
		var t0: float = mm.waveTime
		var xs0: Array = _monster_xs(h)
		await h.wait(2.5)
		await h.shot("%s_arrive" % st)
		var xs1: Array = _monster_xs(h)
		h.check("stage %s: the fight runs while the plea is up (wave time, monsters moving, not paused)" % st,
				mm.waveTime > t0 + 2.0 and xs0 != xs1 and not GameWorld.paused and h.get_tree().get_nodes_in_group("story-plea").size() > 0,
				{"waveTime": [t0, mm.waveTime], "monsters": [xs0.size(), xs1.size()]})
		# The first fight line comes 7 s in.
		await h.until(func(): return pd.shown.size() > n0 + 1, 10.0)
		await h.wait(0.6)
		var fight: Dictionary = pd.shown[n0 + 1] if pd.shown.size() > n0 + 1 else {}
		h.check("stage %s: a fight line from pool %s/fight" % [st, st], fight.get("kind", "") == "fight" and PleaData.pool(st, "fight").has(fight.get("line", "")), fight)
		await h.shot("%s_fight" % st)
		# Kill the wave: last words where a monster falls.
		var nd: int = pd.shown.size()
		mm.instantlyKillWave()
		await h.wait(0.5)
		await h.shot("%s_death" % st)
		var deaths: Array = pd.shown.slice(nd).filter(func(e): return e["kind"] == "death")
		h.check("stage %s: last words when a monster dies" % st, deaths.size() >= 1 and PleaData.pool(st, "death").has(deaths[0]["line"]), deaths)
		await h.until(func(): return not Data.of("team1.monsters.wavepresent"), 60.0)
		await h.wait(4.0)

	# Down the mine during a wave: the wave line shows at the top of the screen.
	await h.dig_room(Vector2i(-2, 30), Vector2i(2, 33))
	await h.teleport_tile(Vector2i(0, 33))
	await h.wait(1.0)
	var n1: int = pd.shown.size()
	Data.apply("team1.monsters.wavecooldown", 2)
	await h.until(func(): return pd.shown.size() > n1, 40.0)
	await h.wait(0.8)
	await h.shot("distant_cry")
	h.check("away from the dome, the arrival line is a distant cry on screen", pd.shown.size() > n1 and pd.shown[n1]["where"] == "screen", pd.shown.slice(n1))
	mm.instantlyKillWave()
	h.note("all pleas", pd.shown)
