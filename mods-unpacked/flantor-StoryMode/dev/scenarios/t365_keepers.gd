extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t365_anchors.gd"

# #365: every keeper breaks chain anchors its own way, by real input: the
# Engineer by default; `-Extra "--keeper=keeper2"` (keeper3, keeper4; the
# Beastmaster only through this dev harness). With the boss gear (what a
# keeper who reached the ocean has), beside two anchors in turn, the lowest
# (deep in the lava, by the floor) and the highest (under the ceiling), it
# digs into each the way t297_keeper2.dig does (the Engineer drills and the
# Beastmaster punches by pushing into it, the Assessor shoots spheres, the
# Infiltrator throws kunai). Checks each breaks, and notes how long it took.
# The Infiltrator can't hang in the air by a high anchor: it hooks the
# anchor itself, hangs from its rope and throws kunai at it (aimed at the
# stone, not just ahead). Every anchor also has rock or the tentacle within a
# climber's reach (the generator's rule, t365_place).

const Keeper2Run = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t297_keeper2.gd")
const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow


func boot() -> Dictionary:
	return {"seed": 12345, "boss": false, "keeper": _Story.user_arg("keeper", "keeper1")}


func run(h) -> void:
	if not await setup(h):
		return
	var k = h.keeper()
	var kid: String = _Story.user_arg("keeper", "keeper1")
	h.check("the keeper is the %s" % kid, k.techId == kid, k.techId)
	await Keeper2Run.close_tutorials(h)
	await reveal_ocean(h)
	var list: Array = anchors.anchors.duplicate()
	list.sort_custom(func(x, y): return x["centre"].y > y["centre"].y)
	var picks: Array = [list[0], list[-1]]
	var times: Array = []
	for i in picks.size():
		var a: Dictionary = picks[i]
		var spot: Dictionary = stand_by(a)
		if not h.check("an open cell beside anchor %d" % a["id"], not spot.is_empty(), a["cell"]):
			continue
		var dir: String = dir_action(spot["dir"])
		await h.teleport_tile(spot["cell"])
		tents.refresh_near()
		cool(h)
		await h.wait(0.4)
		var t0: float = h.now()
		var label: String = "low" if i == 0 else "high"
		await h.shot("%s_by_%s_anchor" % [kid, label])
		while not a["broken"] and h.now() - t0 < 40.0:
			# Back beside it if it drifted off (in the lava, or falling).
			if k.global_position.distance_to(a["centre"]) > (160.0 if kid == "keeper3" else 70.0):
				await h.teleport_tile(spot["cell"])
			if kid == "keeper3":
				await _infiltrator(h, k, a)
			else:
				await Keeper2Run.dig(h, k, dir, 2.0)
			cool(h)
		var secs: float = h.now() - t0
		times.append(snappedf(secs, 0.1))
		await h.wait(0.3)
		await h.shot("%s_broke_%s_anchor" % [kid, label])
		h.check("the %s breaks the %s anchor its own way" % [kid, label], a["broken"] and _EndGame.is_anchor_broken(a["id"]), {"seconds": snappedf(secs, 0.1)})
	h.note("%s: seconds to break the low and the high anchor (boss gear)" % kid, times)
	h.check("two chains broken, the tentacles woke", _EndGame.chains_broken() == 2 and _Ocean.chains_broken() == 2, _EndGame.state())


# Hook the anchor (once), hang from it, and throw kunai at the stone for 2 s.
func _infiltrator(h, k, a: Dictionary) -> void:
	var hooked: bool = is_instance_valid(k.hook) and k.hook.has_hit
	if not hooked:
		k.networkThrowHook((a["centre"] - k.global_position).normalized(), k.global_position)
		await h.until(func(): return is_instance_valid(k.hook) and k.hook.has_hit, 1.0)
	h.aim_mouse(a["centre"], k)
	h.down("keeper3_throw")
	var t0: float = h.now()
	while h.now() - t0 < 2.0 and not a["broken"]:
		await h.wait(0.2)
		h.aim_mouse(a["centre"], k)
	h.up("keeper3_throw")
