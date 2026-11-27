extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 381: the tentacle tips Velle can be hurt through glow; a popped tip
# loses its glow. Shots of the chamber in phase 1 and phase 3, a close-up of
# one tip, and the chamber after a tip pops.

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const TIMEOUT := 180


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	var td = Level.map.tileData
	var ch: Rect2i = td.get_meta("story_boss_chamber")
	var area: Array = []
	for y in range(ch.position.y - 4, ch.end.y + 3):
		for x in range(ch.position.x - 3, ch.end.x + 3):
			area.append(Vector2i(x, y))
	await h.reveal(area)
	await h.teleport_tile(ch.position + Vector2i(3, ch.size.y - 1))
	var boss = _Director.instance()
	var started: bool = await h.until(func(): return _Director.current() == "fight", 8.0)
	h.check("the fight starts", started, _Director.current())
	if not started:
		return
	var velle = boss.velle
	velle.attack_enabled = false
	velle.spawn_bombs = false
	await h.until(func(): return velle.state == "fight", 8.0)
	await h.wait(2.0)
	var k = h.keeper()
	var cam = Level.viewports.getPlayerCam(k.playerId)
	var centre: Vector2 = Level.map.getTilePos(Vector2(ch.position) + Vector2(ch.size) * 0.5) - Vector2(12, 12)
	for i in 3:
		cam.position = centre
		await h.frames(1)
	h.check("phase 1 has living tips", velle.alive_stalks() >= 2, velle.alive_stalks())
	await h.shot("phase1")
	await h.burst("phase1_pulse", 6, 6)
	# Close on the first tip.
	var tip: Vector2 = velle.to_global(velle.stalks[0]["pos"])
	var z0: Vector2 = cam.zoom
	for i in 3:
		cam.position = tip
		cam.zoom = z0 * 2.5
		await h.frames(1)
	await h.shot("tip_close")
	cam.zoom = z0
	for i in 3:
		cam.position = centre
		await h.frames(1)
	# Pop it: its glow goes with it.
	velle._pop_stalk(velle.stalks[0])
	await h.wait(1.2)
	h.check("a tip popped", velle.alive_stalks() == velle.stalks.size() - 1, velle.alive_stalks())
	await h.shot("one_popped")
	# Phase 3: five tips.
	velle.phase = 2
	velle._grow_stalks()
	await h.wait(1.5)
	for i in 3:
		cam.position = centre
		await h.frames(1)
	# (Phase 3 grows 4 or 5 tips, by difficulty.)
	h.check("phase 3's tips all grew back", velle.alive_stalks() == velle.stalks.size() and velle.stalks.size() >= 4, velle.alive_stalks())
	await h.shot("phase3")
