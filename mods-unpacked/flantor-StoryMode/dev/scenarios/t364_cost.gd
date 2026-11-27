extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t347_meter.gd"

# #364: the frame cost of the ocean's tentacles, with the #347 frame meter
# (t347_meter.gd: vsync off, frame / process / physics / render times per
# step). On the real generated map:
#   - at the surface (the tentacles far away: only their clock runs);
#   - in the ocean's air band by the left tip, both tentacles on screen, at
#     10 chains (the fastest swing), then the same spot with the tentacles'
#     node switched off and hidden (the reference), then at 0 chains;
#   - dropped onto the swinging tip at 10 chains (the keeper bumping off it).
# Also each step's time inside the rigs' pose (map/tentacle_rig.gd pose_us).
# Checks: on screen they add under 0.5 ms a frame on average over the
# switched-off reference; far away they pose nothing.

const Ocean = preload("res://mods-unpacked/flantor-StoryMode/map/ocean_tentacles.gd")
static var _Ocean = Ocean  # calls go through this: lazy_preload makes const-preload calls slow
const TIMEOUT := 300
const MAX_ADDED_MS := 0.5

var _tents
var _pose_prev: int = 0
var _pose: Dictionary = {}     # step -> [us per frame]


func boot() -> Dictionary:
	return {"seed": 12345}


func _pose_us() -> int:
	var t: int = 0
	if _tents != null and is_instance_valid(_tents):
		for r in _tents.rigs:
			t += r.pose_us
	return t


func _on_pose_frame() -> void:
	var now: int = _pose_us()
	if step != "" and not GameWorld.paused:
		if not _pose.has(step):
			_pose[step] = []
		_pose[step].append((now - _pose_prev) / 1000.0)
	_pose_prev = now


func run(h) -> void:
	h.disable_waves()
	_tents = _Ocean.find()
	if not h.check("the ocean tentacles are built", _tents != null):
		return
	load("res://mods-unpacked/flantor-StoryMode/dev/boss_dev.gd").give_gear()
	meter_start(h)
	h.get_tree().process_frame.connect(_on_pose_frame)
	await h.wait(1.0)
	_Ocean.set_chains_broken(10)
	for r in _tents.rigs:
		r.snap_to_target()
	var poses0: int = _tents.rigs[0].poses
	await measure(h, "surface (tentacles far)", 5.0)
	h.check("far from the ocean, the tentacles pose nothing", _tents.rigs[0].poses == poses0 and not _tents.near, _tents.rigs[0].poses - poses0)
	await h.shot("surface")
	var cells: Array = []
	for p: Dictionary in _tents.places:
		for y in range(int(p["tip_row"]) - 3, int(p["base_row"]) + 1):
			for dx in range(-10, 11):
				cells.append(Vector2i(int(p["x"]) + dx, y))
	await h.reveal(cells)
	# Between the two tips in the air band: both on screen.
	var a: Vector2 = _tents.rigs[0].pad_top_now()
	var b: Vector2 = _tents.rigs[1].pad_top_now()
	var k = h.keeper()
	k.teleport((a + b) * 0.5 + Vector2(0, -20))
	_tents.refresh_near()
	h.snap_camera(k)
	await h.wait(1.5)
	await h.shot("ocean_both_tips")
	# Off and on twice, each after a settle, so a hitch at a step's start
	# (the reveal, the camera) doesn't count as the tentacles' cost.
	for i in 2:
		_tents.process_mode = Node.PROCESS_MODE_DISABLED
		_tents.visible = false
		await h.wait(1.0)
		await measure(h, "ocean, tentacles off %d" % (i + 1), 5.0)
		_tents.process_mode = Node.PROCESS_MODE_INHERIT
		_tents.visible = true
		await h.wait(1.0)
		await measure(h, "ocean, 10 chains %d" % (i + 1), 5.0)
	_Ocean.set_chains_broken(0)
	for r in _tents.rigs:
		r.snap_to_target()
	await h.wait(0.5)
	await measure(h, "ocean, 0 chains", 6.0)
	_Ocean.set_chains_broken(10)
	for r in _tents.rigs:
		r.snap_to_target()
	k.teleport(_tents.rigs[0].pad_top_now() + Vector2(0, -14))
	_tents.refresh_near()
	h.snap_camera(k)
	await measure(h, "on the tip, 10 chains", 6.0)
	await h.shot("on_tip")
	meter_stop()
	h.get_tree().process_frame.disconnect(_on_pose_frame)
	var rep: Dictionary = report(h)
	var pose: Dictionary = {}
	for st in _pose:
		pose[st] = stats(_pose[st])
	h.note("pose ms per frame (both rigs)", pose)
	var on: float = (avg(rep, "ocean, 10 chains 1") + avg(rep, "ocean, 10 chains 2")) * 0.5
	var off: float = (avg(rep, "ocean, tentacles off 1") + avg(rep, "ocean, tentacles off 2")) * 0.5
	var phys_on: float = (avg(rep, "ocean, 10 chains 1", "physics ms") + avg(rep, "ocean, 10 chains 2", "physics ms")) * 0.5
	var phys_off: float = (avg(rep, "ocean, tentacles off 1", "physics ms") + avg(rep, "ocean, tentacles off 2", "physics ms")) * 0.5
	h.note("tentacles on screen at 10 chains: frame %.3f ms vs %.3f off (+%.3f); physics step %.3f vs %.3f (+%.3f)" % [on, off, on - off, phys_on, phys_off, phys_on - phys_off])
	h.check("on screen they add under %.1f ms a frame (average)" % MAX_ADDED_MS, on > 0.0 and off > 0.0 and on - off < MAX_ADDED_MS, [on, off])
