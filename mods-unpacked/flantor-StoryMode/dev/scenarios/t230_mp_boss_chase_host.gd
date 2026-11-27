extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #230 (2/3), host half: the chase for a team. Starts at the chase with the
# dev command (`_dev_boss("chase")`): the tentacles hunt the keeper nearest
# their lead tip (the host's), turn on the client's when the host's flies off,
# grab it (a heart from the team), keep hunting while the host's keeper is home
# and the client's is not, and the chase ends when both are home.
# Pair: t230_mp_boss_chase_client.

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const Boss = preload("res://mods-unpacked/flantor-StoryMode/data/boss.gd")
const TIMEOUT := 420


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func _client_keeper(h):
	for k in Keepers.getAll():
		if k.peerId != h.multiplayer.get_unique_id():
			return k
	return null


func _facts(chase) -> Dictionary:
	return {"trail": chase.trail.size(), "length": chase.trail_length(), "heads": chase.heads.duplicate(), "target": str(chase.target.playerId) if chase.target != null else "",
		"turns": chase.turns, "hits": chase.hits, "wait": chase.wait, "t": chase.time}


func run(h) -> void:
	if not await host_start(h):
		return
	var boss = _Director.instance()
	var ck = _client_keeper(h)
	var me = h.keeper()
	h.check("boss director and a client keeper on the host", boss != null and ck != null, keeper_rows(h))
	if boss == null or ck == null:
		return
	GameWorld.serverAddUpgrade(ck.playerId + ".suitblaster", "team1")
	var hit_ids: Array = []
	var ch: Rect2i = Level.map.tileData.get_meta("story_boss_chamber")

	# ---- the chase, by the dev command (it drills the shaft home too)
	boss._dev_boss("chase")
	var started: bool = await h.until(func(): return _Director.current() == "chase" and boss.chase != null, 10.0)
	h.check("`--boss=chase` starts the chase on the host", started, _Director.current())
	if not started:
		return
	var chase = boss.chase
	boss.health.hit.connect(func(k, _push): hit_ids.append(k.playerId))
	# This test is about the client's keeper: the host's is never hurt.
	boss.health.set_safe(me, 99999.0)
	# The host's keeper right by the tentacles' way out; the client's in a
	# top corner of the chamber, further off.
	await h.teleport_tile(Vector2i(ch.get_center()) + Vector2i(0, 1))
	share("chamber", [ch.position.x, ch.position.y, ch.size.x, ch.size.y])
	share("spot", [ch.position.x + 2, ch.position.y + 2])
	var client_in: bool = await h.until(func(): return ch.has_point(Level.map.getTileCoord(ck.global_position)), 30.0)
	h.check("the client's keeper is in the chamber", client_in, keeper_rows(h))
	await h.wait(0.5)
	h.check("the tentacles hunt the keeper nearest them: the host's", chase.target == me, _facts(chase))
	await h.until(func(): return chase.wait <= 0.0 and float(chase.heads[0]) > 30.0, 8.0)
	await h.shot("host_tentacles_out")
	share("look1", _facts(chase))
	# The client compares its copy with this a moment later: hold still.
	await h.wait(2.5)

	# ---- the host's keeper flies off up the shaft: they turn on the client's
	var path: Array = boss.dev_path
	await h.teleport_tile(path[maxi(0, path.size() - 12)])
	var turned: bool = await h.until(func(): return chase.target == ck, 10.0)
	h.check("with the host's keeper far off, they turn on the client's", turned and chase.turns >= 1, _facts(chase))
	share("turned", _facts(chase))

	# ---- the client's keeper waits: it is grabbed
	var grabbed: bool = await h.until(func(): return hit_ids.has(ck.playerId), 30.0)
	h.check("a tentacle grabs the client's keeper: a heart from the team", grabbed and boss.health.hearts() < Boss.max_hearts(), {"hits": hit_ids, "hearts": boss.health.hearts(), "chase": _facts(chase)})
	h.check("the host's keeper, far off, was not hit", not hit_ids.has(me.playerId), hit_ids)
	await h.shot("host_client_grabbed")
	share("grabbed", {"hearts": boss.health.hearts(), "chase": _facts(chase)})
	boss.health.set_safe(ck, 99999.0)
	await h.wait(2.0)

	# ---- the host's keeper gets home first: the chase goes on
	await h.teleport_tile(Vector2i(0, -3))
	await h.wait(3.0)
	h.check("the host's keeper is home", me.isInsideDome, keeper_rows(h))
	h.check("with the client's keeper still out, the chase goes on", _Director.current() == "chase" and chase.target == ck, [_Director.current(), _facts(chase)])
	await h.shot("host_home_waiting")

	# ---- the client's keeper gets home: the chase is over
	share("go_home", true)
	var over: bool = await h.until(func(): return _Director.current() == "finale", 30.0)
	h.check("with every keeper home, the chase is over: the finale", over, {"state": _Director.current(), "keepers": keeper_rows(h)})
	h.check("the tentacles stop", not chase.running, chase.running)
	share("done", {"state": _Director.current(), "hearts": boss.health.hearts(), "chase": _facts(chase)})
	h.note("chase", _facts(chase))
	await h.wait(1.0)
	await h.shot("host_finale")
	await host_wait_clients_left(h)
