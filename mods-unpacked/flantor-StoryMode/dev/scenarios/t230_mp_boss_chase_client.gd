extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #230 (2/3), client half: the chase for a team, as the client sees it. Its
# keeper waits in Velle's chamber; it draws the host's tentacles (a puppet
# chase), sees them turn on its keeper and grab it, hears the chase, and
# follows the team into the finale once its keeper is home too.
# Pair: t230_mp_boss_chase_host.

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
const Boss = preload("res://mods-unpacked/flantor-StoryMode/data/boss.gd")
const Sfx = preload("res://mods-unpacked/flantor-StoryMode/boss/sfx.gd")
const TIMEOUT := 420


func boot() -> Dictionary:
	return {"netjoin": true}


func _facts(chase) -> Dictionary:
	return {"trail": chase.trail.size(), "length": chase.trail_length(), "heads": chase.heads.duplicate(), "target": str(chase.target.playerId) if chase.target != null else "",
		"hits": chase.hits, "wait": chase.wait, "t": chase.time, "running": chase.running}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var c = await shared(h, "chamber", 120.0)
	var spot = await shared(h, "spot", 10.0)
	h.check("the host started the chase", c != null and spot != null)
	if c == null or spot == null:
		return
	var ch := Rect2i(int(c[0]), int(c[1]), int(c[2]), int(c[3]))
	var boss = Director.instance()
	var reads: bool = await h.until(func(): return Director.current() == "chase", 15.0)
	h.check("the boss state reads `chase` on the client", reads, Director.current())
	var built: bool = await h.until(func(): return boss.chase != null and is_instance_valid(boss.chase) and boss.chase.puppet, 10.0)
	h.check("the client has a puppet chase", built)
	if not built:
		return
	var chase = boss.chase
	var health = boss.health
	await h.teleport_tile(Vector2i(int(spot[0]), int(spot[1])))
	var mid: Vector2 = Vector2(ch.get_center())
	h.note("chamber cell on the client", {"res": Level.map.tileData.get_resourcev(mid), "visible": Level.map.visibleTileCoords.get(mid, "no")})
	h.check("the recall is jammed for the client in the chase", Director.jams_recall())

	# ---- the same tentacles as the host's
	var l1 = await shared(h, "look1", 40.0)
	await h.wait(0.3)
	h.check("the tentacles set off on the client too", float(chase.heads[0]) > 10.0, _facts(chase))
	h.check("the trail matches the host's (within 2 points)", l1 != null and absi(chase.trail.size() - int(l1["trail"])) <= 2 and absf(chase.trail_length() - float(l1["length"])) < 30.0, [l1, _facts(chase)])
	h.check("the hunted keeper matches (the host's)", l1 != null and _facts(chase)["target"] == l1["target"], [l1, _facts(chase)])
	await h.shot("client_tentacles_out")
	h.check("the chase music plays on the client", boss.music.mode == "chase" and boss.music.playing().size() > 0, boss.music.playing())

	# ---- they turn on this keeper
	var turned = await shared(h, "turned", 30.0)
	var mine: bool = await h.until(func(): return chase.target == h.keeper(), 3.0)
	h.check("the client sees them turn on its keeper", turned != null and mine, [turned, _facts(chase)])
	var p0: Vector2 = h.keeper().global_position
	var seen_hit: bool = await h.until(func(): return health.invulnerable > 0.0, 30.0)
	var thrown: float = 0.0
	for i in 12:
		await h.frames(1)
		thrown = maxf(thrown, h.keeper().global_position.distance_to(p0))
	h.check("the grab reaches the client's keeper (it blinks, thrown)", seen_hit and thrown > 4.0, {"safe": health.invulnerable, "thrown": thrown})
	await h.shot("client_grabbed")
	var g = await shared(h, "grabbed", 20.0)
	var lower: bool = await h.until(func(): return health.hearts() < Boss.HEARTS, 3.0)
	h.check("the team's hearts read lower on the client", lower and g != null and health.hearts() == int(g["hearts"]), [health.hearts(), g])
	h.check("the tentacles' grab sounds on the client", int(Sfx.played.get("whip", 0)) > 0, Sfx.played)
	await h.wait(1.5)
	await h.shot("client_tentacles_close")

	# ---- home
	await shared(h, "go_home", 60.0)
	await h.teleport_tile(Vector2i(0, -3))
	var over: bool = await h.until(func(): return Director.current() == "finale", 20.0)
	h.check("home too: the client follows the team into the finale", over, Director.current())
	await h.wait(0.5)
	h.check("the client's tentacles stop", not chase.running, _facts(chase))
	var done = await shared(h, "done", 30.0)
	h.note("host at the end", done)
	h.note("client at the end", _facts(chase))
	h.note("client sounds", Sfx.played)
	await h.shot("client_home")
