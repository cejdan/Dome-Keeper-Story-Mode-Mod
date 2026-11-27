extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t365_anchors.gd"

# #368: the last chain sets the ship down by the dome (huge map, seed 12345,
# the Engineer). Until #367's cutscene: the placeholder. Nine chains break
# (the ship stays in the coil), the last one breaks with the keeper by the
# ship: the coil drags it down into the lava; the ground beside the dome
# cracks and the ship is pushed up out of it, legs out (shots of both). Then
# at the dome: it stands on the ground left of the dome, clear of the dome,
# its doors, its station and the keeper's way down; nothing of it collides;
# the boarding tube runs to a hatch in the dome's glass. Saves slot 68 (for
# t368_reload). The keeper walks into the dome's left side by real input:
# the hatch takes the use key's focus and the prompt shows; walking back to
# the station gives the focus back. Nobody boards here.

const Ship = preload("res://mods-unpacked/flantor-StoryMode/endgame/ship.gd")
static var _Ship = Ship  # calls go through this: lazy_preload makes const-preload calls slow
const ShipData = preload("res://mods-unpacked/flantor-StoryMode/data/ship.gd")
const ShipArt = preload("res://mods-unpacked/flantor-StoryMode/endgame/ship_art.gd")
const Sfx = preload("res://mods-unpacked/flantor-StoryMode/boss/sfx.gd")
const LAND_SLOT := 68

var ship


func boot() -> Dictionary:
	return {"seed": 12345, "boss": false}


# --- shared with t368_reload, t368_saved, t368_mp_* --------------------------------

func dome():
	return Level.getDome("team1")


# The keeper into the dome, standing on its floor.
func go_home(h, k) -> void:
	k.teleport(dome().global_position + Vector2(10, -12))
	h.snap_camera(k)
	await h.wait(1.5)


# Walks left in the dome by real input until the hatch has the keeper's focus.
func walk_to_hatch(h, k, pad: int = -1) -> bool:
	var ok: bool = false
	if pad >= 0:
		h.pad(pad, "ui_left", true)
	else:
		h.down("ui_left")
	var t_end: float = h.now() + 6.0
	while h.now() < t_end:
		await h.frames(1)
		if ship.can_focus(k) and k.focussedUsable == ship._usable:
			ok = true
			break
	if pad >= 0:
		h.pad(pad, "ui_left", false)
	else:
		h.up("ui_left")
	await h.wait(0.4)
	return ok and k.focussedUsable == ship._usable


# Holds the use key (real input) for `sec`.
func hold_use(h, sec: float) -> void:
	h.down("ui_select")
	await h.wait(sec)
	h.up("ui_select")


# Everything the ship stands on and near, for the checks: its box at the
# dome (global), the dome's box.
func ship_box() -> Rect2:
	var r := ShipArt.BODY_RECT
	r = r.expand(Vector2(r.position.x, ShipArt.FOOT_Y))
	r = r.expand(Vector2(ShipArt.VISOR[3].x, 0))
	return Rect2(ship.carrier.to_global(r.position), r.size)


func run(h) -> void:
	if not await setup(h):
		return
	ship = _Ship.find()
	if not h.check("the run has a ship", ship != null):
		return
	var k = h.keeper()
	await reveal_ocean(h)
	var list: Array = anchors.anchors.duplicate()
	var last: Dictionary = list.pop_back()
	for a in list:
		anchors.dev_break(a["id"], false)
	await h.wait(1.0)
	h.check("nine chains: still held in the ocean", ship.mode == "ocean" and not _Ship.should_be_landed(), [ship.mode, _EndGame.state()])
	# By the ship, the last chain far off.
	var home: Vector2 = ship.to_global(ship.ocean_home)
	k.teleport(home + Vector2(-160, -60))
	var cam = Level.viewports.getPlayerCam(k.playerId)
	cam.targetOffset = home + Vector2(0, 20) - k.global_position
	h.snap_camera(k)
	await h.wait(1.0)
	cool(h)
	await h.shot("held_before_last_chain")
	anchors.dev_break(last["id"], false)
	await h.frames(3)
	h.check("the last chain: the coil drags the ship down (the placeholder move)", ship.mode == "sinking" and _EndGame.is_free(), ship.mode)
	for t in [0.7, 1.4]:
		await h.wait(0.7)
		cool(h)
		await h.shot("sinking_%.1fs" % t)
	# Over to the dome for the rise.
	cam.targetOffset = Vector2.ZERO
	await go_home(h, k)
	var rising: bool = await h.until(func(): return ship.mode == "rising", 6.0)
	h.check("then the ground beside the dome cracks and the ship rises out of it", rising, ship.mode)
	await h.wait(0.5)
	await h.shot("rising_from_the_ground")
	await h.wait(0.6)
	await h.shot("rising_late")
	var landed: bool = await h.until(func(): return ship.mode == "dome", 6.0)
	h.check("it stands at the dome", landed and _Ship.is_landed(), ship.mode)
	var whats: Array = _Ship.events.map(func(e): return e["what"])
	h.check("in order: the live word, the rise, landed (live)", whats.has("free_live") and whats.find("rise") > whats.find("free_live") and whats.find("landed") > whats.find("rise") and _Ship.events.filter(func(e): return e["what"] == "landed")[0]["live"] == true, _Ship.events)
	h.check("with its sounds", int(Sfx.played.get("grow", 0)) >= 1 and int(Sfx.played.get("ship_land", 0)) == 1, Sfx.played)
	await h.wait(1.0)
	_check_at_dome(h, k)
	h.check("its phase: the escape (boarding plays the doom ending)", _Ship.phase() == "escape" and _Ship.board_kind() == "doom", _Ship.phase())
	await h.shot("ship_at_the_dome")
	SaveGame.saveGame("singleplayer", LAND_SLOT, true)
	await h.wait(1.5)
	h.note("saved slot %d" % LAND_SLOT, {"state": _EndGame.state(), "ship": ship.mode})
	# The hatch: walk to it by real input.
	var got: bool = await walk_to_hatch(h, k)
	h.check("walking left in the dome, the hatch takes the use key's focus", got, [k.focussedUsable, ship.can_focus(k), k.global_position - dome().global_position])
	await h.wait(0.3)
	h.check("and the prompt shows", ship._prompt.visible, ship._prompt.visible)
	await h.shot("boarding_prompt")
	await h.hold("ui_right", 0.9)
	await h.wait(0.5)
	h.check("walking back right, the hatch lets the focus go (the station gets it)", k.focussedUsable != ship._usable and not ship._prompt.visible, [str(k.focussedUsable), k.global_position - dome().global_position])
	await h.shot("back_at_the_station")
	h.check("nobody boarded: the run goes on", not GameWorld.won and not Level.mode.is_ending(), GameWorld.won)


# The ship at the dome is out of everyone's way.
func _check_at_dome(h, k) -> void:
	var d = dome()
	var box: Rect2 = ship_box()
	var dpos: Vector2 = d.global_position
	var dome_left: float = dpos.x + ship._wall_x - ship.to_local(dpos).x - 4.0
	h.note("ship box (global) and the dome", {"ship": box, "dome": dpos, "glass_x": ship.to_global(Vector2(ship._wall_x, 0)).x})
	h.check("it stands on the ground (feet within 2 px of it)", absf(ship.carrier.to_global(Vector2(0, ShipArt.FOOT_Y)).y - (dpos.y + 2.0)) <= 2.0, [ship.carrier.to_global(Vector2(0, ShipArt.FOOT_Y)).y, dpos.y + 2.0])
	h.check("left of the dome, clear of its glass (the nose ends before it)", box.end.x < ship.to_global(Vector2(ship._wall_x, 0)).x - 10.0 and box.position.x < dpos.x, [box, ship.to_global(Vector2(ship._wall_x, 0)).x])
	h.check("clear of the dome's doors and the keeper's way down (nothing under the ground)", box.end.y <= dpos.y + 4.0, box)
	var bodies: Array = ship.find_children("*", "PhysicsBody2D", true, false)
	h.check("nothing of it collides (no bodies)", bodies.is_empty(), bodies.map(func(b): return str(b.get_path())))
	h.check("the hatch's use area is on only here, in the dome's glass", ship._usable.monitorable and absf(ship._usable.global_position.x - ship.to_global(Vector2(ship._wall_x, 0)).x) < 12.0, ship._usable.global_position)
	var station = d.get_node_or_null("Station")
	if station != null:
		h.check("the station is on the other side of the dome (its use is not the hatch's)", station.global_position.x > dpos.x, station.global_position - dpos)
