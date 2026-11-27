extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 382: Velle's eyes in the chamber. Red cave eyes on the body and in
# the walls (where the lasers fire from), little great eyes on the tentacle
# tips. Shots: the chamber, two wall lasers, a wall eye, the body (and a
# burst of it), a tip, and the body in the hit flash.

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const TIMEOUT := 240


func boot() -> Dictionary:
	# The last chain already broken (#366): the lair seal lets the keeper in.
	return {"seed": 12345, "free": true}


func _aim(h, cam, at: Vector2, zoom: Vector2) -> void:
	for i in 3:
		cam.position = at
		cam.zoom = zoom
		await h.frames(1)


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
	# Phase 2: more wall eyes open, three tips.
	velle.phase = 1
	velle._wall_open = 1.0
	velle._grow_stalks()
	await h.wait(2.0)
	var k = h.keeper()
	var cam = Level.viewports.getPlayerCam(k.playerId)
	var z0: Vector2 = cam.zoom
	var centre: Vector2 = Level.map.getTilePos(Vector2(ch.position) + Vector2(ch.size) * 0.5) - Vector2(12, 12)
	var body: Vector2 = velle.to_global(velle.base + Vector2(0, -30))
	await _aim(h, cam, centre, z0)
	await h.shot("chamber")
	# Two wall lasers, clear of the keeper: the eyes they come from.
	var mid: Vector2 = velle.arena.get_center()
	velle._wall_ray(mid + Vector2(0, -30), true, 0.0)
	velle._wall_ray(mid + Vector2(70, 0), false, -0.2)
	await h.burst("laser", 10, 8)
	await h.wait(0.6)
	var wall_eye: Vector2 = velle.to_global(velle.arena.position + Vector2(5, velle.arena.size.y * 0.3))
	await _aim(h, cam, wall_eye + Vector2(60, 0), z0 * 2.6)
	await h.shot("wall")
	await _aim(h, cam, body, z0 * 2.6)
	await h.shot("body")
	await h.burst("body_anim", 12, 5)
	await _aim(h, cam, body, z0 * 2.6)
	velle._hit_flash = 0.3
	await h.burst("body_hit", 3, 2)
	var tip: Vector2 = velle.to_global(velle.stalks[0]["pos"])
	await _aim(h, cam, tip, z0 * 2.6)
	await h.shot("tip")
	h.check("the body has 4 eyes", velle.BODY_EYES.size() == 4, velle.BODY_EYES.size())
