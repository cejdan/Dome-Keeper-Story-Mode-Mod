extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #242: client half. The host changed a story key, the money, the water and the
# boss state while this client's full Data sync was on its way; this client
# must end up with the host's values (StoryNet's settled resend), and keep
# them. Logs every value it read on the way. Pair: t242_mp_data_resend_host.

const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow
const KEY := "team1.story.t242"
const TIMEOUT := 300

var _seen: Array = []
var _last: Dictionary = {}


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var tree: SceneTree = h.get_tree()
	var watch := func(): _watch(h)
	tree.process_frame.connect(watch)
	_watch(h)
	var want = await shared(h, "final", 60.0)
	h.check("the host shared its final values", want is Dictionary, want)
	if not want is Dictionary:
		return
	var have := func() -> Dictionary:
		return {"money": Data.ofOr("team1.inventory.money", null), "water": Data.ofOr("team1.inventory.water", null), "story": Data.ofOr(KEY, null), "boss": _Director.current()}
	await h.until(func(): return _matches(have.call(), want), 5.0)
	var got: Dictionary = have.call()
	h.note("values read on the way", _seen)
	h.check("the story key is the host's", _same(got["story"], want["story"]), {"client": got["story"], "host": want["story"]})
	h.check("the money is the host's", _same(got["money"], want["money"]), {"client": got["money"], "host": want["money"]})
	h.check("the water is the host's", _same(got["water"], want["water"]), {"client": got["water"], "host": want["water"]})
	h.check("the boss state is the host's", _same(got["boss"], want["boss"]), {"client": got["boss"], "host": want["boss"]})
	await h.wait(3.0)
	h.check("and they stay so", _matches(have.call(), want), have.call())
	tree.process_frame.disconnect(watch)
	await h.shot("client_end")


func _matches(got: Dictionary, want: Dictionary) -> bool:
	for k in ["money", "water", "story", "boss"]:
		if not _same(got[k], want[k]):
			return false
	return true


# JSON (the share) turns ints into floats.
func _same(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return absf(float(a) - float(b)) < 0.001
	return str(a) == str(b)


func _watch(h) -> void:
	var now := {"money": Data.ofOr("team1.inventory.money", null), "story": Data.ofOr(KEY, null), "boss": _Director.current()}
	if now != _last:
		_last = now
		var row := now.duplicate()
		row["t"] = snappedf(h.now(), 0.01)
		_seen.append(row)
