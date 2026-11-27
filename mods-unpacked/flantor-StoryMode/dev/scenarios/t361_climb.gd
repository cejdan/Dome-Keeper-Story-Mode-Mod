extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 361: keepers on the chamber's living stone, with Velle switched off.
# Boots the Beastmaster by default; `-Extra "--keeper=keeper3"` runs the
# Infiltrator.
#   keeper4: hangs from the stalactite over the eye (claws on it, doesn't fall);
#            climbs from a stump up onto a climbing stalactite, and from a wall
#            step up onto another.
#   keeper3: stands on a stump top and a wall step top without sliding off, and
#            walks across the step top.
# Bursts of each for the look.

const TIMEOUT := 300
const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow


func boot() -> Dictionary:
	return {"seed": 12345, "boss": false, "keeper": "keeper4"}


var stone
var ch: Rect2i


func _body(name: String):
	for b in stone.bodies:
		if b.name == name:
			return b
	return null


func _top_of(name: String) -> Vector2:
	# The body's highest point, arena-local.
	var i: int = stone.bodies.find(_body(name))
	var best := Vector2(0, INF)
	for p: Vector2 in stone.polygons[i]:
		if p.y < best.y:
			best = p
	return best


func _tip_of(name: String) -> Vector2:
	var i: int = stone.bodies.find(_body(name))
	var best := Vector2(0, -INF)
	for p: Vector2 in stone.polygons[i]:
		if p.y > best.y:
			best = p
	return best


func _put(h, local: Vector2) -> void:
	var k = h.keeper()
	k.teleport(stone.to_global(local))
	if "velocity" in k:
		k.velocity = Vector2.ZERO
	h.snap_camera(k)
	await h.frames(3)


func _local(h) -> Vector2:
	return stone.to_local(h.keeper().global_position)


func run(h) -> void:
	h.disable_waves()
	# The gear of a keeper who got this far (Heat Shielding IV: no heat recall).
	load("res://mods-unpacked/flantor-StoryMode/dev/boss_dev.gd").give_gear()
	stone = Level.map.get_node_or_null("StoryChamberStone")
	if not h.check("the chamber stone is built", stone != null):
		return
	ch = Level.map.tileData.get_meta("story_boss_chamber")
	var area: Array = []
	for y in range(ch.position.y - 2, ch.end.y + 2):
		for x in range(ch.position.x - 3, ch.end.x + 3):
			area.append(Vector2i(x, y))
	await h.reveal(area)
	await h.teleport_tile(ch.position + Vector2i(4, ch.size.y - 1))
	await h.wait(1.5)
	var kid: String = _Story.user_arg("keeper", "keeper4")
	h.note("keeper " + kid)
	match kid:
		"keeper4":
			await _beastmaster(h)
		"keeper3":
			await _infiltrator(h)
		_:
			h.note("no check for " + kid)


func _claw_on(h, names: Array) -> String:
	var tents = h.keeper().get_node("Tentacles")
	for t in tents.tentacles:
		if t.is_grounded() and is_instance_valid(t.attachedTile) and String(t.attachedTile.name) in names:
			return String(t.attachedTile.name)
	return ""


func _beastmaster(h) -> void:
	var stals: Array = []
	for b in stone.bodies:
		if String(b.name).begins_with("stalactite"):
			stals.append(String(b.name))

	# ---- hanging from the stalactite over the eye
	var tip: Vector2 = _tip_of("stalactite_5")
	await _put(h, tip + Vector2(0, 16))
	var held: bool = await h.until(func(): return _claw_on(h, ["stalactite_5"]) != "", 4.0)
	await h.wait(2.0)
	var p: Vector2 = _local(h)
	h.note("hanging", {"tip": tip, "keeper": p})
	h.check("the Beastmaster grips the stalactite over the eye", held)
	h.check("and hangs from it (doesn't fall)", p.y < tip.y + 70.0, p)
	await h.burst("bm_hang", 10, 4)

	# ---- from a stump up onto a climbing stalactite
	for leg: Array in [["stump_left", Vector2(1, -1), "stump"], ["step_left", Vector2(0.4, -1), "step"]]:
		var top: Vector2 = _top_of(leg[0])
		await _put(h, Vector2(top.x if leg[0] != "step_left" else 20.0, top.y - 14.0))
		await h.wait(1.0)
		var start: Vector2 = _local(h)
		var dir: Vector2 = leg[1]
		h.down("ui_up")
		if dir.x > 0.5:
			h.down("ui_right")
		var reached: String = ""
		var min_y: float = start.y
		var t0: float = h.now()
		while h.now() - t0 < 8.0:
			await h.frames(1)
			min_y = minf(min_y, _local(h).y)
			reached = _claw_on(h, stals)
			if reached != "":
				break
		h.up("ui_up")
		h.up("ui_right")
		await h.wait(1.0)
		var end: Vector2 = _local(h)
		h.note("climb from the " + leg[2], {"start": start, "highest": min_y, "end": end, "reached": reached})
		h.check("from the %s top the Beastmaster gets a claw on a stalactite" % leg[2], reached != "", {"start": start, "highest": min_y})
		await h.shot("bm_from_" + leg[2])


func _infiltrator(h) -> void:
	for name in ["stump_left", "step_left", "stump_right"]:
		var top: Vector2 = _top_of(name)
		var at := Vector2(top.x if name != "step_left" else 16.0, top.y - 16.0)
		await _put(h, at)
		await h.wait(2.5)
		var p: Vector2 = _local(h)
		h.note("standing on " + name, {"top": top, "keeper": p})
		h.check("the Infiltrator stands on the %s's top" % name, absf(p.y - (top.y - 10.0)) < 14.0 and absf(p.x - at.x) < 20.0, p)
	# Walk off the tall step's top: a short walk stays up there, a longer one
	# drops onto the lower step, not to the floor (the steps work as stairs).
	await _put(h, Vector2(10.0, _top_of("step_left").y - 16.0))
	await h.wait(1.0)
	await h.hold("ui_right", 0.15)
	await h.wait(0.3)
	var short: Vector2 = _local(h)
	await h.hold("ui_right", 0.5)
	await h.wait(1.0)
	var low: Vector2 = _local(h)
	h.note("walk on the step", {"short": short, "on": low})
	h.check("a short walk along the tall step stays on its top", short.y < 170.0, short)
	h.check("walking off it lands on the lower step, not the floor", low.y > 185.0 and low.y < 215.0, low)
	await h.shot("inf_on_step")
