extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #246: the client that stays (the second player). Reads the money, the story
# key and the boss state every frame while the third player leaves and joins
# again; the host bumps all three to a counter n every frame meanwhile. A value
# going back (n lower than one already seen) is flicker; how long after the
# host set an n it shows here is lag (both from the wall clock, same machine;
# the host's log is user://t246_host.json). Must end with the host's values.
# Pair: t246_mp_late_join_host.

const Director = preload("res://mods-unpacked/cejdan-StoryMode/boss/boss_director.gd")
const KEY := "team1.story.t246"
const LOG := "user://t246_host.json"
const TIMEOUT := 420

var _seen: Array = []     # [unix msec, money n, story n, boss n] on every change
var _last := [-1, -1, -1]


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var tree: SceneTree = h.get_tree()
	var each := func(): _watch()
	tree.process_frame.connect(each)
	var leave = await shared(h, "leave", 120.0)
	h.check("this client stays", leave != null and int(leave) != h.multiplayer.get_unique_id(), [leave, h.multiplayer.get_unique_id()])
	var want = await shared(h, "final", 240.0)
	h.check("the host shared its final values", want is Dictionary, want)
	if not want is Dictionary:
		return
	await h.wait(3.0)
	tree.process_frame.disconnect(each)
	var n: int = int(want["n"])
	h.check("the money is the host's", _last[0] == n, {"client": _last[0], "host": n})
	h.check("the story key is the host's", _last[1] == n, {"client": _last[1], "host": n})
	h.check("the boss state is the host's", _last[2] == n, {"client": _last[2], "host": n})
	var f := FileAccess.open(LOG, FileAccess.READ)
	var host: Dictionary = JSON.parse_string(f.get_as_text()) if f != null else {}
	h.check("the host's log is there", not host.is_empty())
	if host.is_empty():
		return
	var set_at: Dictionary = {}
	for s in host["sets"]:
		set_at[int(s[1])] = int(s[0])
	# Flicker: per value, every change to an n below the highest seen so far,
	# and how long until it was back at or above that.
	var names := ["money", "story", "boss"]
	var report: Dictionary = {}
	for vi in 3:
		var best := -1
		var backs: Array = []
		var open_back = null
		var lags: Array = []
		for row in _seen:
			var v: int = row[vi + 1]
			if v < 1:
				continue
			if set_at.has(v) and v > best:
				lags.append(row[0] - set_at[v])
			if open_back != null and v >= open_back["to"]:
				open_back["ms"] = row[0] - open_back["at"]
				open_back = null
			if v < best:
				if open_back == null:
					open_back = {"at": row[0], "from": best, "to": best, "back to": v}
					backs.append(open_back)
			best = maxi(best, v)
		lags.sort()
		report[names[vi]] = {"went back": backs.size(), "times": backs.slice(0, 12),
			"lag ms (median, 90%, max)": [lags[lags.size() / 2], lags[int(lags.size() * 0.9)], lags[-1]] if not lags.is_empty() else []}
	h.note("flicker and lag", report)
	var frames_with_data_queued: int = host["queue"].filter(func(q): return int(q[2]) > 0).size()
	h.note("host frames with a chunked Data message to this client queued", frames_with_data_queued)
	for name in names:
		h.check("%s never went back" % name, report[name]["went back"] == 0, report[name]["times"])
	await h.shot("watcher_end")


func _n(v) -> int:
	var s := str(v)
	var i := s.rfind("_")
	if s.begins_with("v"):
		return int(s.substr(1))
	if i >= 0:
		return int(s.substr(i + 1))
	return -1


func _watch() -> void:
	var m = Data.ofOr("team1.inventory.money", null)
	var now := [int(m) - 5000 if m != null and int(m) > 5000 else -1, _n(Data.ofOr(KEY, "")), _n(Director.current()) if Director.current().begins_with("t246_") else -1]
	if now != _last:
		_last = now
		_seen.append([int(Time.get_unix_time_from_system() * 1000.0), now[0], now[1], now[2]])
