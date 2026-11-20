extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #230 gap probe, client half: the client's keeper joins the host in Velle's
# chamber. What does the client see, and can Velle hurt it? Pair:
# t230_mp_boss_probe_host.

const TIMEOUT := 420


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	var ch = await shared(h, "chamber", 90.0)
	h.check("host started the fight", ch != null)
	if ch == null:
		return
	var start := Vector2i(int(ch[0]) + int(ch[2]) - 4, int(ch[1]) + 2)
	await h.teleport_tile(start)
	await h.wait(2.0)
	var boss = Level.mode.get_node_or_null("StoryBoss")
	for i in 7:
		await h.wait(3.0)
		h.note("client t%d" % i, {"boss state (Data)": Data.ofOr("team1.story.boss", ""), "director": boss != null, "velle node": boss != null and boss.velle != null, "boss layer": boss != null and boss.layer != null, "hearts": Data.ofOr("team1.story.hearts", null), "tile": h.keeper_tile(), "heat": Level.map.get_node("StoryLavaField").heat})
		if i % 2 == 0:
			await h.shot("client_fight_%d" % i)
