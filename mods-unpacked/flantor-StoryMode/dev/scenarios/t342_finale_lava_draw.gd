extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t171_finale_play.gd"

# Ticket 342: the surface finale ran at a few frames a second in a real run
# (playtest 2026-11-23, Small map, with red "blood" rain on screen). The rain
# was not it: the lava field's draw culling handed back every lava cell when
# the view (in cells) was bigger than the lava, as in the zoomed-out surface
# battle, so the lava ocean far below was drawn in full every frame. The dev
# finale (`--boss=finale`) never showed it: there the ocean is unrevealed, and
# unseen cells are skipped before drawing.
#
# This reaches the finale the real way (the chamber with the ocean revealed
# around it, Velle killed, the chase, the keeper home) with rain forced, then
# lets the t171 laser bot play the battle under a frame meter. It checks that
# the lava drawn is only what is on screen, and that the battle's frames stay
# fast (about 180 ms each before the fix, 7 ms after, on the dev machine).
#
#   --rain=1|0|acid   weather forced at the start (default 1: rain)
#   --flow=real|dev   real (default) as above; dev = straight into the finale
#   --ablate=1        in round 1, switch Velle, the chase, the lava field and
#                     the gas field off for 5 s each in turn; the meter shows
#                     each window (how #342 was found)

const FRAME_MS_MAX := 25.0    # average over a battle step; the bug made it ~180

var _meter: Dictionary = {}   # step -> lists of per-frame numbers
var _last_us: int = 0
var _fin = null
var _off: String = ""
var _lava_checks: Array = []


func boot() -> Dictionary:
	return {"seed": 12345}


func _find_script(n: Node, tail: String, out: Array) -> void:
	var s = n.get_script()
	if s != null and str(s.resource_path).ends_with(tail):
		out.append(n)
	for c in n.get_children():
		_find_script(c, tail, out)


func _one(tail: String):
	var found: Array = []
	_find_script(Engine.get_main_loop().root, tail, found)
	return found[0] if not found.is_empty() else null


func _on_frame() -> void:
	var now: int = Time.get_ticks_usec()
	if _last_us > 0 and _fin != null and is_instance_valid(_fin) and not GameWorld.paused:
		var step: String = _fin.step if _off == "" else _off
		if not _meter.has(step):
			_meter[step] = {"ms": [], "draws": [], "proc": [], "phys": []}
		_meter[step]["ms"].append((now - _last_us) / 1000.0)
		_meter[step]["draws"].append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_meter[step]["proc"].append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_meter[step]["phys"].append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_last_us = now


func _stats(a: Array) -> Dictionary:
	if a.is_empty():
		return {}
	var s: Array = a.duplicate()
	s.sort()
	var sum: float = 0.0
	for v in s:
		sum += float(v)
	return {"avg": snappedf(sum / s.size(), 0.01), "p95": snappedf(float(s[int(s.size() * 0.95)]), 0.01), "max": snappedf(float(s.back()), 0.01)}


func run(h) -> void:
	var rain: String = _Story.user_arg("rain", "1")
	var ws = _one("content/weather/WeatherSystem.gd")
	if ws != null:
		for tn in ["changeWeatherTimer", "initialWeatherTimer"]:
			var tm = ws.get_node_or_null(tn)
			if tm != null:
				tm.stop()
		# WEATHER index: 2 rain, 8 acid rain, -1 clear.
		ws.update_weather(2 if rain == "1" else (8 if rain == "acid" else -1), 1)
	await h.wait(1.0)
	h.note("weather", {"rain": rain, "nodes": Engine.get_main_loop().get_nodes_in_group("team1.weather").size()})
	if _Story.user_arg("flow", "real") == "real":
		await _real_way(h)
	Engine.get_main_loop().process_frame.connect(_on_frame)
	_fin_watch(h)
	if _Story.user_arg("ablate", "0") == "1":
		_ablate(h)
	_lava_watch(h)
	await super.run(h)
	Engine.get_main_loop().process_frame.disconnect(_on_frame)
	var report: Dictionary = {"rain": rain}
	for step in _meter:
		var m: Dictionary = _meter[step]
		report[step] = {"frames": m["ms"].size(), "frame ms": _stats(m["ms"]), "draw calls": _stats(m["draws"]),
			"process ms": _stats(m["proc"]), "physics ms": _stats(m["phys"])}
	h.note("frame meter", report)
	ModLoaderLog.info("t342 frame meter: %s" % JSON.stringify(report), "flantor-StoryMode")
	# The lava drawn at the surface: only cells on screen, never the whole field.
	h.check("the lava field drew only cells on screen during the battle", not _lava_checks.is_empty() and _lava_checks.all(func(e): return e["off screen"] == 0 and e["drawn"] < e["lava cells"]), _lava_checks)
	if _Story.user_arg("flow", "real") == "real":
		var ocean_seen: bool = not _lava_checks.is_empty() and _lava_checks[0]["revealed"] > 100
		h.check("the lava ocean was revealed (the case the dev finale misses)", ocean_seen, _lava_checks.slice(0, 1))
	if _Story.user_arg("ablate", "0") != "1":
		for step in ["round1", "round2", "round3"]:
			if report.has(step):
				var avg: float = report[step]["frame ms"]["avg"]
				h.check("%s runs fast: average frame %.1f ms (under %.0f)" % [step, avg, FRAME_MS_MAX], avg < FRAME_MS_MAX, report[step])


# The finale as a run reaches it: the fight in the chamber (Velle killed
# outright), the chase, the keeper home. The dev command reveals the chamber
# and the lava ocean around it, as a keeper who dug down there has.
func _real_way(h) -> void:
	h.disable_waves()
	var boss = _Director.instance()
	var k = h.keeper()
	var home: Vector2 = k.global_position
	boss._dev_boss("true")
	await h.until(func(): return boss.velle != null and is_instance_valid(boss.velle) and boss.velle.state == "fight", 20.0)
	await h.wait(1.0)
	boss.velle._damage_core(99999.0)
	await h.until(func(): return boss.current() == "chase", 15.0)
	await h.wait(4.0)
	await h.shot("chase")
	k.teleport(home)
	await h.until(func(): return boss.current() == "finale", 10.0)
	if boss.current() != "finale":
		boss._chase_done()
	h.note("real way", {"state": boss.current(), "velle state": boss.velle.state if is_instance_valid(boss.velle) else "",
		"chase": boss.chase != null and is_instance_valid(boss.chase)})


# --ablate=1: once round 1 is on, switch each suspect off for 5 s in turn.
func _ablate(h) -> void:
	await h.until(func(): return _fin != null and _fin.step == "round1", 60.0)
	await h.wait(3.0)
	for tail: String in ["", "boss/velle.gd", "boss/chase.gd", "lava/lava_field.gd", "gas/gas_field.gd", ""]:
		var nodes: Array = []
		if tail != "":
			_find_script(Engine.get_main_loop().root, tail, nodes)
		for n in nodes:
			n.process_mode = Node.PROCESS_MODE_DISABLED
		_off = "off " + (tail if tail != "" else "nothing") + " (%d)" % nodes.size()
		await h.wait(5.0)
		for n in nodes:
			if is_instance_valid(n):
				n.process_mode = Node.PROCESS_MODE_INHERIT
	_off = ""


# Every 5 s of the battle: how many lava cells the field draws, and whether
# any of them is outside the view.
func _lava_watch(h) -> void:
	var lf = _one("lava/lava_field.gd")
	if lf == null:
		return
	await h.until(func(): return _fin != null and _fin.step == "round1", 60.0)
	for i in 6:
		await h.wait(5.0)
		if _fin == null or not is_instance_valid(_fin) or not _fin.step.begins_with("round"):
			continue
		var vis: Array = lf._visible_cells()
		var off_screen: int = 0
		for c: Vector2i in vis:
			if not lf._in_boxes(c):
				off_screen += 1
		var revealed: int = 0
		for c: Vector2i in lf.shown:
			if _FieldUtil_seen(lf, c):
				revealed += 1
		_lava_checks.append({"step": _fin.step, "drawn": vis.size(), "off screen": off_screen, "lava cells": lf.shown.size(), "revealed": revealed,
			"view": [lf._view_c0, lf._view_c1]})


func _FieldUtil_seen(lf, c: Vector2i) -> bool:
	return lf._FieldUtil.seen(lf.map, c)


# The finale node exists once super.run() starts it: pick it up for the meter.
func _fin_watch(h) -> void:
	while _fin == null:
		await h.frames(1)
		var boss = _Director.instance()
		if boss != null and boss.finale != null:
			_fin = boss.finale
