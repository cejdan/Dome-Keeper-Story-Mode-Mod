extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 382 (design): Velle's small eyes in each prototype style, for the
# user to compare. Per style: the chamber, the body close up, a tentacle tip
# close up and a short burst. `--styles=a,b` picks which (default all four).

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const Pix = preload("res://mods-unpacked/flantor-StoryMode/boss/pix.gd")
static var _Pix = Pix
const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story
const TIMEOUT := 240


func boot() -> Dictionary:
	return {"seed": 12345}


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
	var styles: PackedStringArray = _Story.user_arg("styles", "swirl,cave,socket,velle,mix").split(",")
	for st in styles:
		_Pix.set_eye_style(st)
		h.check("style " + st, _Pix.eye_style() == st, _Pix.eye_style())
		await _aim(h, cam, centre, z0)
		await h.shot(st + "_chamber")
		# Two wall lasers, clear of the keeper: the eyes they come from.
		var mid: Vector2 = velle.arena.get_center()
		velle._wall_ray(mid + Vector2(0, -30), true, 0.0)
		velle._wall_ray(mid + Vector2(70, 0), false, -0.2)
		await h.burst(st + "_laser", 10, 8)
		await h.wait(0.6)
		# A wall eye close up.
		var wall_eye: Vector2 = velle.to_global(velle.arena.position + Vector2(5, velle.arena.size.y * 0.3))
		await _aim(h, cam, wall_eye + Vector2(60, 0), z0 * 2.6)
		await h.shot(st + "_wall")
		await _aim(h, cam, body, z0 * 2.6)
		await h.shot(st + "_body")
		await h.burst(st + "_body_anim", 12, 5)
		var tip: Vector2 = velle.to_global(velle.stalks[0]["pos"])
		await _aim(h, cam, tip, z0 * 2.6)
		await h.shot(st + "_tip")
	_Pix.set_eye_style("swirl")
