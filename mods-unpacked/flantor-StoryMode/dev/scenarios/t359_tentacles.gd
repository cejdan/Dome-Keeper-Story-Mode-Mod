extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #359: the tentacle test room (dev/dev_tentacle_test.gd). Boots `--tentacles`
# with keeper1 by default; `-Extra "--keeper=keeper3"` (or keeper2 / keeper4)
# runs it with another keeper. Checks that the room is built and the keeper is
# in it, and that the tentacles barely move at wake 0 and swing hard at wake 4.
# Then, by keeper:
#   keeper3: set on top of the platform tentacle, it rides it (stays on top,
#            moves with it); a hook thrown into a segment from the floor stays
#            on the same spot of the segment as it moves (the grip fix);
#   keeper4: hung under the platform tentacle, its claws plant on segments and
#            stay on the same spot of the segment as it moves (the grip fix);
#            the keeper is carried along, not left floating.
# Bursts of each for the user to judge the look.

const TIMEOUT := 240
const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow


func boot() -> Dictionary:
	return {"seed": 12345, "tentacles": true, "keeper": "keeper1"}


func run(h) -> void:
	var test = h.get_tree().root.find_child("DevTentacleTest", true, false)
	if not h.check("the test node is there", test != null):
		return
	var built: bool = await h.until(func(): return test.room != Rect2i() and test.rigs.size() == 2, 20.0)
	if not h.check("the room and both tentacles are built", built, {"room": test.room}):
		return
	await h.wait(1.5)
	var k = h.keeper()
	var kid: String = _Story.user_arg("keeper", "keeper1")
	var kt: Vector2i = h.keeper_tile()
	h.check("the keeper (%s) is in the room" % kid, test.room.has_point(kt), {"tile": kt, "room": test.room})
	var plat = test.rigs[0]
	var wall = test.rigs[1]
	h.check("the platform tentacle has 10 segments, the wall 12", plat.segments.size() == 10 and wall.segments.size() == 12)
	h.note("where things are", {"keeper": k.global_position, "plat base": plat.segments[0].global_position, "plat tip": plat.segments.back().global_position,
		"wall base": wall.segments[0].global_position, "wall tip": wall.segments.back().global_position, "seg visible": plat.segments[0].is_visible_in_tree()})
	await h.wait(3.0)
	var lava_in_room: int = 0
	var lava = Level.map.get_node_or_null("StoryLavaField")
	if lava != null:
		for c in lava.mass:
			if test.room.has_point(Vector2i(c)):
				lava_in_room += 1
	h.check("no lava runs into the room", lava_in_room == 0, lava_in_room)

	# Wake 0: alive but held down. Wake 4: free.
	var calm: float = await _tip_swing(h, plat, 9.0)
	await h.shot("wake0")
	test.set_wake(4)
	await h.wait(5.0)   # the swing eases in
	var wild: float = await _tip_swing(h, plat, 9.0)
	await h.shot("wake4")
	h.note("tip swing (px): wake 0 %.1f, wake 4 %.1f" % [calm, wild])
	h.check("wake 0 barely moves the tip (under 1.5 tiles)", calm > 1.0 and calm < 36.0, calm)
	h.check("wake 4 swings the tip several tiles (over 6)", wild > 144.0, wild)
	await h.burst("wake4_room", 12, 6)

	match kid:
		"keeper3":
			await _ride(h, test, plat)
			await _hook(h, test, plat)
		"keeper4":
			await _grip(h, test, plat)
		_:
			h.note("no movement check for " + kid + "; the bursts are for the user")
	test.set_wake(2)
	await h.wait(4.0)
	await h.burst("wake2_room", 12, 6)


# Peak-to-peak movement of the platform tip over `sec` seconds.
func _tip_swing(h, rig, sec: float) -> float:
	var tip = rig.segments.back()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var t: float = 0.0
	while t < sec:
		var p: Vector2 = tip.global_position
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		await h.frames(1)
		t += h.get_physics_process_delta_time()
	return (hi - lo).length()


# Infiltrator: put it on top of segment 4 at wake 2 and see it ride.
func _ride(h, test, plat) -> void:
	test.set_wake(2)
	await h.wait(4.0)
	var k = h.keeper()
	var seg = plat.segments[4]
	k.teleport(seg.global_position + Vector2(0, -seg.width * 0.5 - 14.0))
	h.snap_camera(k)
	await h.wait(0.5)
	var on_top: int = 0
	var ys: Array = []
	var frames: int = 0
	var start: Vector2 = k.global_position
	while frames < 180:
		await h.frames(1)
		frames += 1
		var s = plat.segments[4]
		var rel: Vector2 = s.global_transform.affine_inverse() * k.global_position
		if absf(rel.x) < 48.0 and rel.y < 0.0 and rel.y > -40.0:
			on_top += 1
		ys.append(k.global_position.y)
	await h.burst("keeper3_riding", 12, 4)
	var span: float = ys.max() - ys.min()
	h.note("keeper3 on the platform: %d/180 frames on top, height span %.1f px" % [on_top, span])
	h.check("the Infiltrator stays on the platform (most frames)", on_top > 140, on_top)
	h.check("the Infiltrator moves with it (rises and falls)", span > 4.0, span)


# Beastmaster: under segment 5, its claws plant on segments and keep their
# spot on the segment while it swings.
func _grip(h, test, plat) -> void:
	test.set_wake(2)
	await h.wait(4.0)
	var k = h.keeper()
	var seg = plat.segments[5]
	k.teleport(seg.global_position + Vector2(0, seg.width * 0.5 + 18.0))
	h.snap_camera(k)
	var tents = k.get_node("Tentacles")
	var segs: Dictionary = {}
	for s in plat.segments:
		segs[s] = true
	var planted: bool = await h.until(func():
		for t in tents.tentacles:
			if t.is_grounded() and segs.has(t.attachedTile):
				return true
		return false, 5.0)
	if not h.check("a claw plants on a tentacle segment", planted):
		await h.shot("keeper4_no_grip")
		return
	await h.wait(0.5)
	# Track each claw on a segment: its offset in the segment's frame must hold.
	var drift: float = 0.0
	var samples: int = 0
	var slipped: int = 0
	var kpos: Array = []
	var last: Dictionary = {}
	for f in 180:
		await h.frames(1)
		kpos.append(k.global_position)
		for t in tents.tentacles:
			if not t.is_grounded() or not is_instance_valid(t.attachedTile) or not segs.has(t.attachedTile):
				last.erase(t)
				continue
			var local: Vector2 = t.attachedTile.global_transform.affine_inverse() * t.attachmentPoint
			if last.has(t) and last[t].seg == t.attachedTile:
				# Over 4 px is the claw re-planting, not drift. Without the
				# grip fix a held claw drifts by the segment's own motion
				# each frame (1-3 px at wake 2).
				var d: float = (local - last[t].local).length()
				if d <= 4.0:
					drift = maxf(drift, d)
					samples += 1
					if d > 0.05:
						slipped += 1
			last[t] = {"seg": t.attachedTile, "local": local}
	await h.burst("keeper4_gripping", 12, 4)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector2 in kpos:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var moved: float = (hi - lo).length()
	h.note("keeper4: %d claw-frames on segments, %d moved on the segment (max %.2f px), keeper moved %.1f px" % [samples, slipped, drift, moved])
	h.check("claws on segments were tracked", samples > 60, samples)
	# A claw re-planting a pixel or two away shows as a one-frame jump; a claw
	# that does not follow the segment would move every frame.
	h.check("a claw keeps its spot on the segment (moves on under 5% of frames)", slipped * 20 < samples, {"slipped": slipped, "of": samples, "max": drift})
	h.check("the Beastmaster is carried along (moves over 4 px)", moved > 4.0, moved)


# Infiltrator: from the floor, throw the hook up into segment 6 (the way the
# secondary button does, aimed by code) and see it hold its spot on the segment.
func _hook(h, test, plat) -> void:
	var k = h.keeper()
	var seg = plat.segments[6]
	k.teleport(Level.map.getTilePos(Vector2(test.room.position.x + 13, test.room.end.y - 1)))
	h.snap_camera(k)
	await h.wait(1.0)
	var segs: Dictionary = {}
	for s in plat.segments:
		segs[s] = true
	k.networkThrowHook((seg.global_position - k.global_position).normalized(), k.global_position)
	var hit: bool = await h.until(func(): return k.hook != null and is_instance_valid(k.hook) and k.hook.has_hit, 3.0)
	var on_seg: bool = hit and is_instance_valid(k.hook.attached_target) and segs.has(k.hook.attached_target)
	if not h.check("the hook sticks in a tentacle segment", on_seg, {"hit": hit}):
		await h.shot("keeper3_hook_missed")
		return
	var target = k.hook.attached_target
	var drift: float = 0.0
	var moved: float = 0.0
	var start: Vector2 = k.hook.global_position
	var last: Vector2 = target.global_transform.affine_inverse() * k.hook.global_position
	var n: int = 0
	for f in 90:
		await h.frames(1)
		if k.hook == null or not is_instance_valid(k.hook) or k.hook.attached_target != target:
			break
		var local: Vector2 = target.global_transform.affine_inverse() * k.hook.global_position
		drift = maxf(drift, (local - last).length())
		last = local
		moved = maxf(moved, k.hook.global_position.distance_to(start))
		n += 1
	await h.burst("keeper3_hooked", 10, 3)
	h.note("keeper3 hook: %d frames on the segment, drift %.2f px, hook moved %.1f px" % [n, drift, moved])
	h.check("the hook held for a while (30+ frames)", n >= 30, n)
	h.check("the hook keeps its spot on the segment (drift under 1 px)", drift < 1.0, drift)
	h.check("the hook moves with the segment (over 2 px)", moved > 2.0, moved)
