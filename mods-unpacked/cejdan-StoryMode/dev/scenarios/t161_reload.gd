extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 161, part two: run t161_chase first. Loads its mid-chase save (slot
# 16) in a fresh process: the chase is still on, the hearts are kept, the
# tentacles come up from below the keeper again, and the waves stay stopped.

const Director = preload("res://mods-unpacked/cejdan-StoryMode/boss/boss_director.gd")
const Boss = preload("res://mods-unpacked/cejdan-StoryMode/data/boss.gd")


func boot() -> Dictionary:
	return {"load": 16}


func run(h) -> void:
	await h.until(func(): return not SaveGame.currentLoadingSavegame, 20.0)
	await h.wait(1.5)
	var boss = Director.instance()
	h.check("the loaded run is still in the chase", Director.current() == "chase", Director.current())
	h.check("the chase resumed", boss.chase != null and is_instance_valid(boss.chase))
	if boss.chase == null:
		return
	h.check("the keeper's hearts survived the reload", boss.health.hearts() >= 1 and boss.health.hearts() <= Boss.HEARTS, boss.health.hearts())
	h.note("hearts", boss.health.hearts())
	h.check("the waves stay stopped", Level.monstersByTeamId.values().all(func(mm): return mm.disabled))
	h.snap_camera()
	var hits0: int = boss.chase.hits
	var caught: bool = await h.until(func(): return boss.chase.hits > hits0, 20.0)
	await h.shot("caught_after_reload")
	h.check("the tentacles come up from below and catch a keeper who waits", caught, [boss.chase.gap, boss.chase.hits])
