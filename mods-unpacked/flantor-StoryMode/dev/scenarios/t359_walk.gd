extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #359: the Infiltrator walks both ways along the platform tentacle. Pieces cut
# as plain rects left a small ledge at each joint, and walking toward the base
# (left, the thicker end) stopped dead at the first one. Holds each way for a
# second at wake 0 and 4 and checks the keeper is still moving in the last half
# second (before the fix: under 1 px). A plain-floor walk is noted to compare.
const TIMEOUT := 120


func boot() -> Dictionary:
	return {"seed": 12345, "tentacles": true, "keeper": "keeper3"}


func run(h) -> void:
	var test = h.get_tree().root.find_child("DevTentacleTest", true, false)
	await h.until(func(): return test.room != Rect2i() and test.rigs.size() == 2, 20.0)
	await h.wait(1.5)
	var plat = test.rigs[0]
	var k = h.keeper()
	k.teleport(Level.map.getTilePos(Vector2(test.room.position.x + 12, test.room.end.y - 1)))
	await h.wait(0.6)
	for dir in ["ui_left", "ui_right"]:
		var fx: float = k.global_position.x
		h.down(dir)
		for f in 60:
			await h.get_tree().physics_frame
		h.up(dir)
		await h.frames(2)
		h.note("floor %s: moved %.1f, on_floor %s" % [dir, k.global_position.x - fx, k.is_on_floor()])
	for wake in [0, 4]:
		test.set_wake(wake)
		await h.wait(4.0)
		for dir in ["ui_left", "ui_right"]:
			var seg = plat.segments[6 if dir == "ui_left" else 2]
			k.teleport(seg.global_position + Vector2(0, -seg.width * 0.5 - 14.0))
			h.snap_camera(k)
			await h.wait(0.6)
			var x0: float = k.global_position.x
			var xs: Array = []
			h.down(dir)
			for f in 60:
				await h.get_tree().physics_frame
				xs.append(snappedf(k.global_position.x, 0.1))
			h.up(dir)
			await h.frames(2)
			h.note("wake %d %s: start %.1f, end %.1f, moved %.1f" % [wake, dir, x0, k.global_position.x, k.global_position.x - x0], xs.slice(0, 60, 6))
			var late: float = absf(float(xs[59]) - float(xs[29]))
			h.check("wake %d: walking %s on the tentacle keeps going (over 5 px in the last half second)" % [wake, dir.trim_prefix("ui_")], late > 5.0, late)
			await h.shot("walk_w%d_%s" % [wake, dir])
