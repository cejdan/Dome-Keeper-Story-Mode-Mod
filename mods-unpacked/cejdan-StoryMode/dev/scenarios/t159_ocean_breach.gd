extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 159: breaking into the lava ocean for the first time froze the game for
# 2-3 seconds. The keeper drills through the ocean's ceiling from a short shaft
# while every frame's length is recorded; the longest frame must stay short.
# Also notes what the map revealed (cells, tile nodes) and the lava's step time.
# Before the fix: one 3.4 s frame, 6,525 cells and 410 tiles revealed at once.

const TIMEOUT := 240
# The longest frame allowed around the breach (ms).
const MAX_FRAME_MS := 100.0

var _frames: Array = []
var _recording := false


func boot() -> Dictionary:
	return {"seed": 12345}


func _record(h) -> void:
	var last: int = Time.get_ticks_usec()
	while _recording:
		await h.get_tree().process_frame
		var t: int = Time.get_ticks_usec()
		_frames.append(t - last)
		last = t


func run(h) -> void:
	h.disable_waves()
	var map = Level.map
	var td = map.tileData
	var o: Dictionary = td.get_meta("story_ocean", {})
	var ceiling: int = int(o["ceiling"])
	var field = map.get_node("StoryLavaField")
	field.magma.clear()
	h.set_inv("money", 100000)
	for i in range(1, 5):
		await h.buy("storyheatshield%d" % i)
	Data.apply("player1.keeper1.drillStrength", 100000)
	var x: int = 5
	await h.dig_room(Vector2i(x, ceiling - 4), Vector2i(x, ceiling - 1))
	await h.teleport_tile(Vector2i(x, ceiling - 1))
	await h.wait(1.5)
	field.heat = 0.0
	await h.shot("at_ceiling")
	var before: Dictionary = {"tiles": map.tiles.size(), "visible": map.visibleTileCoords.size(),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "lava_us": field.phys_us, "lava_frames": field.phys_frames}
	_recording = true
	_record(h)
	await h.wait(0.5)
	h.down("ui_down")
	var broke: bool = await h.until(func():
		field.heat = 0.0
		return map.getTileCoord(h.keeper().global_position).y > ceiling, 15.0)
	h.up("ui_down")
	# The cavern unveils outward from the hole over the next frames (a shot
	# every 8 frames; each shot costs a few ms of its own).
	await h.burst("unveil", 10, 8)
	h.note("focus", {"focused": DisplayServer.window_is_focused(), "paused": GameWorld.paused, "flood pending": map.flood_pending()})
	await h.wait(1.5)
	_recording = false
	field.heat = 0.0
	await h.shot("in_the_ocean_air")
	var after: Dictionary = {"tiles": map.tiles.size(), "visible": map.visibleTileCoords.size(),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "lava_us": field.phys_us, "lava_frames": field.phys_frames}
	var ms: Array = _frames.map(func(u): return snappedf(u / 1000.0, 0.1))
	var worst: float = ms.max() if not ms.is_empty() else 0.0
	var slow: Array = ms.filter(func(v): return v > 50.0)
	h.note("breach", {"broke through": broke, "before": before, "after": after,
		"tiles made": after["tiles"] - before["tiles"], "cells revealed": after["visible"] - before["visible"],
		"lava step ms over the window": snappedf((after["lava_us"] - before["lava_us"]) / 1000.0, 0.1)})
	h.note("frames", {"count": ms.size(), "worst ms": worst, "over 50 ms": slow, "top 10": _top(ms, 10)})
	h.check("the keeper broke into the ocean", broke)
	h.check("no frame around the breach takes over %d ms" % int(MAX_FRAME_MS), worst <= MAX_FRAME_MS, worst)


func _top(a: Array, n: int) -> Array:
	var s: Array = a.duplicate()
	s.sort()
	s.reverse()
	return s.slice(0, n)
