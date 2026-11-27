extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 385: the keeper's hearts in the boss sequence by difficulty (Normal 8,
# Hard 7, Brutal 6, You Asked For It 5) and two hearts shaken loose at each
# phase change. Run once per difficulty: -Extra "--difficulty=-2|-1|0|2".

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const Boss = preload("res://mods-unpacked/flantor-StoryMode/data/boss.gd")
static var _Boss = Boss
const TIMEOUT := 180
const WANT := {-2: 8, -1: 7, 0: 6, 2: 5}


func boot() -> Dictionary:
	# The last chain already broken (#366): the lair seal lets the keeper in.
	return {"seed": 12345, "free": true}


func run(h) -> void:
	h.disable_waves()
	var td = Level.map.tileData
	var ch: Rect2i = td.get_meta("story_boss_chamber")
	var area: Array = []
	for y in range(ch.position.y - 4, ch.end.y + 3):
		for x in range(ch.position.x - 3, ch.end.x + 3):
			area.append(Vector2i(x, y))
	await h.reveal(area)
	await h.teleport_tile(ch.position + Vector2i(5, ch.size.y - 1))
	var boss = _Director.instance()
	var started: bool = await h.until(func(): return _Director.current() == "fight", 8.0)
	h.check("the fight starts", started, _Director.current())
	if not started:
		return
	var velle = boss.velle
	velle.attack_enabled = false
	velle.spawn_bombs = false
	await h.until(func(): return velle.state == "fight", 8.0)
	await h.wait(1.0)
	var diff: int = Level.difficulty("team1")
	var want: int = int(WANT.get(diff, -1))
	h.note("difficulty", {"difficulty": diff, "tier": Boss.TIER_NAMES[_Boss.tier()], "max": _Boss.max_hearts()})
	h.check("starts with %d hearts" % want, boss.health.hearts() == want and _Boss.max_hearts() == want, boss.health.hearts())
	await h.shot("hearts_full")
	# A hit costs one; then Velle's phase changes and shakes two loose.
	boss.health.hurt(velle.global_position, "test")
	await h.wait(0.3)
	h.check("a hit costs one", boss.health.hearts() == want - 1, boss.health.hearts())
	velle._damage_core(velle.hp - Boss.PHASE_AT[0] + 0.5)
	await h.wait(0.8)
	h.check("phase 2 began", velle.phase == 1, velle.phase)
	h.check("two hearts shaken loose", velle.pickups.size() == 2, velle.pickups.size())
	await h.shot("two_hearts")
	# Pick both up: only one fits under the cap.
	var k = h.keeper()
	for p: Dictionary in velle.pickups.duplicate():
		p["t"] = 1.0
		p["v"] = Vector2.ZERO
		for i in 12:
			k.global_position = velle.to_global(p["p"])
			await h.frames(1)
	await h.wait(0.3)
	h.check("one heart left lying (it would overfill)", velle.pickups.size() == 1, velle.pickups.size())
	h.check("hearts topped up to the cap", boss.health.hearts() == want, boss.health.hearts())
