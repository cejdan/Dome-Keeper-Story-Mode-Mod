extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #230 gap probe, host half: starts Velle's chamber fight with the dev command
# (the host's keeper in the chamber), lets it run, and reports what the host's
# boss did. Pair: t230_mp_boss_probe_client.

const TIMEOUT := 420


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if not await host_start(h):
		return
	var boss = Level.mode.get_node_or_null("StoryBoss")
	h.check("boss director on the host", boss != null)
	if boss == null:
		return
	boss._dev_boss("fight")
	await h.wait(1.0)
	var ch: Rect2i = Level.map.tileData.get_meta("story_boss_chamber")
	share("chamber", [ch.position.x, ch.position.y, ch.size.x, ch.size.y])
	var hearts0 = Data.ofOr("team1.story.hearts", null)
	for i in 8:
		await h.wait(3.0)
		h.note("host t%d" % i, {"state": boss.state(), "velle": boss.velle != null, "hearts": Data.ofOr("team1.story.hearts", null), "keepers": keeper_rows(h)})
		if i % 3 == 0:
			await h.shot("host_fight_%d" % i)
	h.note("host hearts", [hearts0, Data.ofOr("team1.story.hearts", null)])
	await host_wait_clients_left(h)
