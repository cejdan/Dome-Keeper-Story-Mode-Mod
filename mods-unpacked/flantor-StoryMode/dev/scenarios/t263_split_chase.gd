extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #263: the chase's edge warning in splitscreen. Starts the chase with the dev
# command (keeper 1 in Velle's chamber), then puts keeper 1 partway up the
# shaft home and keeper 2 in the dome, both views away from the lead tip. Each
# local keeper must get its own mark at its own view's edge, drawn in its view
# alone; then keeper 2 goes down by the tentacles (lead tip in its view: no
# mark there) while keeper 1's mark stays. Both views are shot each time.

const TIMEOUT := 300
const Split = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t231_split_restart.gd")
static var _Split = Split  # calls go through this: lazy_preload makes const-preload calls slow
const Director = preload("res://mods-unpacked/flantor-StoryMode/boss/boss_director.gd")
static var _Director = Director  # calls go through this: lazy_preload makes const-preload calls slow

var k1
var k2


func boot() -> Dictionary:
	return {"loadout": true, "splitscreen": true}


func run(h) -> void:
	if not await _Split.start_split(h):
		return
	k1 = Keepers.getLocalKeeperByDeviceId(0)
	k2 = Keepers.getLocalKeeperByDeviceId(1)
	var boss = _Director.instance()
	boss._dev_boss("chase")
	var started: bool = await h.until(func(): return _Director.current() == "chase" and boss.chase != null, 10.0)
	h.check("the chase starts", started, _Director.current())
	if not started:
		return
	var chase = boss.chase
	boss.health.set_safe(k1, 99999.0)
	boss.health.set_safe(k2, 99999.0)
	await h.until(func(): return chase.wait <= 0.0 and float(chase.heads[0]) > 30.0, 8.0)
	var path: Array = boss.dev_path
	await h.teleport_tile(path[path.size() / 2], k1)
	k1.set("gravity_scale", 0.0)
	await h.wait(1.0)
	_check_marks(h, chase, "both away", {"player1": true, "player2": true})
	await h.shot("both_away")

	# Keeper 2 down by the tentacles' lead tip: its view shows the tip itself.
	var lead_tile: Vector2i = Level.map.getTileCoord(chase.to_global(chase.lead_pos()))
	await h.teleport_tile(lead_tile + Vector2i(0, -2), k2)
	k2.set("gravity_scale", 0.0)
	await h.wait(0.3)
	_check_marks(h, chase, "keeper 2 at the tip", {"player1": true, "player2": false})
	await h.shot("k2_at_tip")


# For each local keeper: is the lead tip off its view (a mark is due), and is
# its mark its own child drawn in its view only?
func _check_marks(h, chase, label: String, due: Dictionary) -> void:
	var rows: Dictionary = {}
	var ok := true
	for k in [k1, k2]:
		var cam = Level.viewports.getPlayerCam(k.playerId)
		var vs: Vector2 = cam.get_viewport_rect().size / cam.zoom
		var view := Rect2(chase.to_local(cam.get_screen_center_position()) - vs * 0.5, vs).grow(-10.0)
		var off: bool = not view.has_point(chase.lead_pos())
		var m = chase._marks.get(k.playerId)
		var bit: int = 1 << ViewportContainer.PLAYER_IDX_TO_CANVAS_LAYER_BIT[ViewportContainer.calcKeeperLocalIdx(k)]
		var own: bool = m != null and is_instance_valid(m) and m.visibility_layer == bit
		rows[k.playerId] = {"tip off its view": off, "own mark": own, "layer": m.visibility_layer if m != null else null}
		ok = ok and off == due[k.playerId] and own
	h.check("%s: a mark per keeper, in its own view, where the tip is off it %s" % [label, due], ok, rows)
