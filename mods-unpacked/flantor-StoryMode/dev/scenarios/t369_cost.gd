extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t369_rise.gd"

# #369: the frame cost of the rising lava, shallow against deep (the #347
# meter: dev/scenarios/t347_meter.gd, vsync off). Huge map, seed 12345, the
# route of t369_rise dug. The same view each time: the keeper in a shaft with
# the lava's surface rising past it, measured for 4 s:
#   before   the same spot in shaft A with no flood yet (the reference)
#   shallow  the line just over the ocean's ceiling, in shaft A
#   deep     the line near the top of the mine, in shaft C: 130 rows of the
#            mine flooded under it
#   inside   a view full of implied lava (the keeper deep under the line, in
#            shaft B), the shader's worst case
# Each window's frame, process, physics, render and the lava field's own tick
# and draw; the stored cells and the band. The rise moves on through each
# window (its cost included).

const Meter = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t347_meter.gd")
const WINDOW := 4.0
const TIMEOUT := 420


func _measure(h, meter, label: String) -> void:
	meter.step = label
	await h.wait(WINDOW)
	meter.step = ""


func run(h) -> void:
	if not await setup(h):
		return
	var k = h.keeper()
	await dig_route(h)
	var meter = Meter.new()
	meter.meter_start(h)
	var gas = Level.map.get_node_or_null("StoryGasField")
	if gas != null:
		gas.freeze_toxin = true
	# Before: shaft A, no flood.
	await place(h, k, Vector2i(3, ceiling - 9))
	await h.wait(1.0)
	await _measure(h, meter, "before (no flood)")
	await h.shot("before")
	var cells0: int = lava.mass.size()
	# Shallow: the line comes up past the same spot.
	rise.dev_start(float(ceiling) - 2.0)
	await h.wait(1.0)
	await wait_until_below(h, k, 5.0, 30.0)
	var st_shallow: Dictionary = lava.flood_stats()
	await _measure(h, meter, "shallow (line over the ocean)")
	await h.shot("shallow")
	# Deep: the line jumps to shaft C, 130 rows up.
	await place(h, k, Vector2i(0, 36))
	rise.dev_set_row(44.0)
	await h.wait(1.0)
	await wait_until_below(h, k, 5.0, 30.0)
	var st_deep: Dictionary = lava.flood_stats()
	await _measure(h, meter, "deep (line near the top)")
	await h.shot("deep")
	# Inside: a view full of implied lava, deep under the line.
	k.teleport(Level.map.getTilePos(Vector2(11, 75)))
	h.snap_camera(k)
	await h.wait(1.0)
	await _measure(h, meter, "inside the implied lava")
	await h.shot("inside")
	meter.meter_stop()
	var rep: Dictionary = meter.report(h, "t369 cost")
	h.note("stored lava cells", {"before": cells0, "shallow": st_shallow, "deep": st_deep})
	var f := func(st: String, key: String) -> float:
		return float(rep.get(st, {}).get(key, {}).get("avg", 0.0))
	var keys := ["frame ms", "process ms", "physics ms", "lava phys ms", "lava draw ms", "lava glow ms", "render gpu ms", "draw calls"]
	var table: Dictionary = {}
	for st in rep:
		var row: Dictionary = {}
		for kk in keys:
			row[kk] = f.call(st, kk)
		table[st] = row
	h.note("cost table (averages)", table)
	var sh: float = f.call("shallow (line over the ocean)", "lava phys ms") + f.call("shallow (line over the ocean)", "lava draw ms") + f.call("shallow (line over the ocean)", "lava glow ms")
	var dp: float = f.call("deep (line near the top)", "lava phys ms") + f.call("deep (line near the top)", "lava draw ms") + f.call("deep (line near the top)", "lava glow ms")
	h.check("the lava's own cost deep is about the same as shallow (%.2f vs %.2f ms)" % [dp, sh], dp <= sh + 0.3, [sh, dp])
	var fs: float = f.call("shallow (line over the ocean)", "frame ms")
	var fd: float = f.call("deep (line near the top)", "frame ms")
	h.check("the frame deep is about the same as shallow (%.2f vs %.2f ms)" % [fd, fs], fd <= fs * 1.15 + 0.3, [fs, fd])
	h.check("the stored cells deep are no more than shallow", st_deep["mass_cells"] <= st_shallow["mass_cells"] + 20, [st_shallow["mass_cells"], st_deep["mass_cells"]])
