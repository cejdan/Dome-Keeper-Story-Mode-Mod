extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 361 (design): clean shots of Velle's chamber in phase 1, with the
# world-to-screen transform logged, as backdrops for the living-flesh block
# concepts. No checks beyond "the fight started".

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const TIMEOUT := 180
const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story


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
	var z: float = float(_Story.user_arg("zoom")) if _Story.user_arg("zoom") != "" else 0.0
	h.note("cam", {"zoom": [cam.zoom.x, cam.zoom.y], "class": cam.get_class()})
	for i in 3:
		cam.position = centre
		if z > 0.0:
			cam.zoom = cam.zoom * z if i == 0 else cam.zoom
		await h.frames(1)
	var ct: Transform2D = h.get_viewport().get_canvas_transform()
	var tl: Vector2 = Level.map.getTilePos(Vector2(ch.position)) - Vector2(12, 12)
	h.note("geometry", {
		"chamber": [ch.position.x, ch.position.y, ch.size.x, ch.size.y],
		"arena_tl_world": [tl.x, tl.y],
		"canvas_scale": [ct.x.x, ct.y.y],
		"canvas_origin": [ct.origin.x, ct.origin.y],
		"arena_tl_screen": [(ct * tl).x, (ct * tl).y],
		"arena_br_screen": [(ct * (tl + Vector2(ch.size) * 24.0)).x, (ct * (tl + Vector2(ch.size) * 24.0)).y],
		"viewport": [h.get_viewport().get_visible_rect().size.x, h.get_viewport().get_visible_rect().size.y],
		"eye_screen": [(ct * velle.to_global(velle.eye_pos())).x, (ct * velle.to_global(velle.eye_pos())).y],
		"keeper_screen": [(ct * k.global_position).x, (ct * k.global_position).y],
	})
	await h.shot("chamber")
	await h.burst("chamber_anim", 16, 4)
