extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #263: splitscreen pleas. A wave line floats above the dome; a local keeper
# whose view doesn't show the dome gets it on screen in its own view, not
# player 1's. Three cases, each shot (both views in one picture):
#   1. keeper 1 at the dome, keeper 2 down the mine: above the dome for
#      keeper 1, on screen in keeper 2's view only
#   2. both down the mine, apart: on screen in each view
#   3. keeper 1 down the mine, keeper 2 at the dome: on screen in keeper 1's
#      view only
# Each on-screen line must sit inside its keeper's view and be drawn there
# alone (its visibility layer is that keeper's).

const TIMEOUT := 300
const Split = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t231_split_restart.gd")
const Pleas = preload("res://mods-unpacked/flantor-StoryMode/pleas/plea_director.gd")

var k1
var k2


func boot() -> Dictionary:
	return {"loadout": true, "splitscreen": true}


func run(h) -> void:
	if not await Split.start_split(h):
		return
	k1 = Keepers.getLocalKeeperByDeviceId(0)
	k2 = Keepers.getLocalKeeperByDeviceId(1)
	var pd = Pleas.instance()
	h.check("the plea director is here", pd != null)
	if pd == null:
		return
	var home: Vector2i = Level.map.getTileCoord(k1.global_position)
	await h.dig_room(Vector2i(-14, 34), Vector2i(-10, 37))
	await h.dig_room(Vector2i(10, 44), Vector2i(14, 47))
	for k in [k1, k2]:
		k.set("gravity_scale", 0.0)

	# ---- 1. keeper 1 at home, keeper 2 down the mine
	await h.teleport_tile(Vector2i(12, 47), k2)
	await h.wait(1.5)
	await _say(h, pd, "k2_away", "both", ["player2"])

	# ---- 2. both down the mine, apart
	await h.teleport_tile(Vector2i(-12, 37), k1)
	await h.wait(1.5)
	await _say(h, pd, "both_away", "screen", ["player1", "player2"])

	# ---- 3. keeper 2 home, keeper 1 still down
	await h.teleport_tile(home, k2)
	await h.wait(1.5)
	await _say(h, pd, "k1_away", "both", ["player1"])
	h.note("all pleas", pd.shown)


func _say(h, pd, label: String, where: String, views: Array) -> void:
	await h.wait(4.5)    # the last line gone
	var n: int = pd.shown.size()
	pd.say("arrive")
	await h.wait(0.6)
	var e: Dictionary = pd.shown[n] if pd.shown.size() > n else {}
	h.check("%s: the line shows %s, on screen in %s's view" % [label, where, views], e.get("where", "") == where and e.get("views", []) == views, e)
	var bits: Dictionary = {}
	for k in [k1, k2]:
		bits[k.playerId] = 1 << ViewportContainer.PLAYER_IDX_TO_CANVAS_LAYER_BIT[ViewportContainer.calcKeeperLocalIdx(k)]
	var placed: Array = []
	for holder in h.get_tree().get_nodes_in_group("story-plea"):
		if not holder.has_meta("view") or holder.is_queued_for_deletion():
			continue
		var pid: String = holder.get_meta("view")
		var k = k1 if pid == k1.playerId else k2
		var pin: Node2D = holder.get_parent()
		var cam = Level.viewports.getPlayerCam(pid)
		var vs: Vector2 = cam.get_viewport_rect().size / cam.zoom
		var view := Rect2(cam.get_screen_center_position() - vs / 2.0, vs)
		var at: Vector2 = holder.global_position
		placed.append({"view": pid, "at": at, "in its view": view.has_point(at), "layer": pin.visibility_layer, "only its view": pin.visibility_layer == bits[pid]})
	placed.sort_custom(func(a, b): return a["view"] < b["view"])
	h.check("%s: one on-screen line per away keeper, inside its view, drawn there only" % label,
		placed.map(func(p): return p["view"]) == views and placed.all(func(p): return p["in its view"] and p["only its view"]), placed)
	await h.shot(label)
