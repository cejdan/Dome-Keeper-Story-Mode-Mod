extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 347: the frame meter the t347_* scenarios share (not a scenario of
# its own). Every frame, for the step the scenario says it is in: the frame
# time, the engine's process and physics times, the root viewport's measured
# render time (CPU and GPU), draw calls, and the lava and gas fields' own time
# (their physics tick, their draw callbacks, the gas look's CPU side). Vsync and
# the frame cap are switched off for the run, so the numbers are cost, not the
# monitor's refresh.
#
#   --ablate=1   the scenario's heavy steps are followed by windows with one
#                suspect switched off at a time (see ablate()).

var step := ""
var _meter: Dictionary = {}       # step -> {key: [per-frame numbers]}
var _last_us := 0
var _vp_rid: RID
var _lava = null
var _gas = null
var _prev: Dictionary = {}
var _hold_heat := true            # keep suit heat and toxin at zero: the meter is the test


func meter_start(h) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_vp_rid = Engine.get_main_loop().root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	_lava = Level.map.get_node_or_null("StoryLavaField")
	_gas = Level.map.get_node_or_null("StoryGasField")
	if _gas != null:
		_gas.freeze_toxin = true
	Engine.get_main_loop().process_frame.connect(_on_frame)
	h.note("meter", {"res": DisplayServer.window_get_size(), "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps})


func meter_stop() -> void:
	if Engine.get_main_loop().process_frame.is_connected(_on_frame):
		Engine.get_main_loop().process_frame.disconnect(_on_frame)


func _counter(node, key: String) -> int:
	if node == null or not is_instance_valid(node):
		return 0
	return int(node.get(key)) if key in node else 0


func _look_us() -> int:
	if _gas == null or not is_instance_valid(_gas):
		return 0
	var t := 0
	for l in _gas.looks.values():
		if is_instance_valid(l):
			t += l.cpu_us
	return t


func _look_awake() -> bool:
	if _gas == null or not is_instance_valid(_gas):
		return false
	for l in _gas.looks.values():
		if is_instance_valid(l) and not l.get("asleep"):
			return true
	return false


func _on_frame() -> void:
	var now: int = Time.get_ticks_usec()
	if _hold_heat and _lava != null and is_instance_valid(_lava):
		for pid in _lava.heats.keys():
			_lava.heats[pid] = 0.0
	var cur := {
		"lava phys": _counter(_lava, "phys_us"), "lava draw": _counter(_lava, "draw_us"), "lava glow": _counter(_lava, "glow_us"),
		"gas phys": _counter(_gas, "phys_us"), "gas draw": _counter(_gas, "draw_us"), "gas look": _look_us()}
	if _last_us > 0 and step != "" and not GameWorld.paused:
		if not _meter.has(step):
			_meter[step] = {}
		var m: Dictionary = _meter[step]
		var row := {
			"frame ms": (now - _last_us) / 1000.0,
			"process ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"physics ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			"render cpu ms": RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid),
			"render gpu ms": RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid),
			"draw calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"look awake": 1.0 if _look_awake() else 0.0,
			"lava cells drawn": _lava._vis_cache.size() if _lava != null and is_instance_valid(_lava) else 0,
		}
		for k in cur:
			row[k + " ms"] = (cur[k] - _prev.get(k, cur[k])) / 1000.0
		for k in row:
			if not m.has(k):
				m[k] = []
			m[k].append(row[k])
	_prev = cur
	_last_us = now


static func stats(a: Array) -> Dictionary:
	if a.is_empty():
		return {}
	var s: Array = a.duplicate()
	s.sort()
	var sum := 0.0
	for v in s:
		sum += float(v)
	return {"avg": snappedf(sum / s.size(), 0.01), "p95": snappedf(float(s[int(s.size() * 0.95)]), 0.01), "max": snappedf(float(s.back()), 0.01)}


# One line per step, also in the log: frames, and avg/p95/max of each number.
func report(h, label: String = "frame meter") -> Dictionary:
	var out: Dictionary = {}
	for st in _meter:
		var m: Dictionary = _meter[st]
		var r: Dictionary = {"frames": m["frame ms"].size()}
		for k in m:
			r[k] = stats(m[k])
		out[st] = r
		ModLoaderLog.info("t347 %s [%s]: %s" % [label, st, JSON.stringify(r)], "flantor-StoryMode")
	h.note(label, out)
	return out


func avg(rep: Dictionary, st: String, key: String = "frame ms") -> float:
	if not rep.has(st) or not rep[st].has(key) or rep[st][key].is_empty():
		return -1.0
	return float(rep[st][key]["avg"])


# Measures `sec` seconds as step `name`.
func measure(h, name: String, sec: float) -> void:
	step = name
	await h.wait(sec)
	step = ""


# --ablate=1: after a heavy step, the same spot measured again with one suspect
# off at a time: each field's whole node (process and draw), only its drawing,
# the lava glow, the gas look.
func ablate(h, base: String, sec: float = 4.0) -> void:
	if _Story_arg("ablate", "0") != "1":
		return
	var cases: Array = []
	if _lava != null:
		cases.append(["lava off", [_lava], "process"])
		cases.append(["lava hidden", [_lava], "visible"])
		cases.append(["lava glow hidden", [_lava.get_node_or_null("LavaGlow")], "visible"])
	if _gas != null:
		cases.append(["gas off", [_gas], "process"])
		cases.append(["gas hidden", [_gas], "visible"])
		var looks: Array = _gas.looks.values().filter(func(l): return is_instance_valid(l))
		cases.append(["gas look off", looks, "process"])
	if _lava != null and _gas != null:
		cases.append(["both off", [_lava, _gas], "process"])
		cases.append(["both hidden", [_lava, _gas], "visible"])
	for cs in cases:
		var nodes: Array = cs[1].filter(func(n): return n != null)
		for n in nodes:
			if cs[2] == "process":
				n.process_mode = Node.PROCESS_MODE_DISABLED
			else:
				n.visible = false
		await h.frames(5)
		await measure(h, "%s: %s" % [base, cs[0]], sec)
		for n in nodes:
			if is_instance_valid(n):
				if cs[2] == "process":
					n.process_mode = Node.PROCESS_MODE_INHERIT
				else:
					n.visible = true
	await measure(h, "%s: again" % base, sec)


func _Story_arg(key: String, dflt: String) -> String:
	return load("res://mods-unpacked/flantor-StoryMode/story.gd").user_arg(key, dflt)
