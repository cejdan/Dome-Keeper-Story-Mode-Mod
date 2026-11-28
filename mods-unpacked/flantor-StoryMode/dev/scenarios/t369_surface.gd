extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t369_rise.gd"

# #369: the lava reaches the surface with nobody aboard the ship or fighting:
# the "too late" loss. Huge map, seed 12345, the chains broken quietly, shaft
# C dug from the dome down. The keeper waits in the dome (not boarding); the
# rise starts 14 rows down. The warning grows in the dome as it comes up the
# shaft; it reaches the surface: the state "surfaced", the moment (the ground
# heaves, the roar), the [DRAFT] card, the end screen ("[DRAFT] Too Late"),
# the run lost. `-Extra "--board"` (t369_board): the keeper boards the ship
# mid-rise instead: the doom ending, a won run, no too-late, and the lava stops
# where it was once the ending starts.

const Endings = preload("res://mods-unpacked/flantor-StoryMode/data/endings.gd")
const Ship = preload("res://mods-unpacked/flantor-StoryMode/endgame/ship.gd")
static var _Ship = Ship  # calls go through this: lazy_preload makes const-preload calls slow


func boot() -> Dictionary:
	return {"seed": 12345, "free": true}


func dome():
	return Level.getDome("team1")


func go_home(h, k) -> void:
	k.teleport(dome().global_position + Vector2(10, -12))
	h.snap_camera(k)
	await h.wait(1.5)


func run(h) -> void:
	if not await setup(h):
		return
	var k = h.keeper()
	await dig_clean(h, Vector2i(0, 0), Vector2i(1, 40))
	await go_home(h, k)
	var ship = _Ship.find()
	h.check("the ship stands at the dome (free)", ship != null and _Ship.is_landed() and _Ship.phase() == "escape", [_Ship.phase()])
	rise.dev_start(14.0)
	var surfaced: Array = []
	rise.surfaced.connect(func(): surfaced.append(true))
	await h.wait(2.0)
	var u0: float = float(rise.closeness.get(k.playerId, 0.0))
	await h.until(func(): return rise.row < 6.0, 20.0)
	var u1: float = float(rise.closeness.get(k.playerId, 0.0))
	h.check("in the dome too, the warning grows as it comes up the shaft", u1 > u0 and u1 > 0.6, [u0, u1])
	await h.shot("lava_under_the_dome")
	if _Story.has_user_arg("board"):
		await _board(h, k, ship)
		return
	var got: bool = await h.until(func(): return _RisingLava.state() == "surfaced", 20.0)
	h.check("it reaches the surface: surfaced", got and surfaced == [true] and is_equal_approx(rise.row, float(Flood.SURFACE_ROW)), [_RisingLava.state(), rise.row])
	await h.wait(0.3)
	await h.shot("at_the_surface")
	h.check("nobody boarded or fighting: too late", Level.mode.is_ending() and Level.mode.too_late_shown == ["surface"], Level.mode.too_late_shown)
	await h.burst("the_ground_heaves", 6, 6)
	var ed = Level.mode.get_node_or_null("StoryEndings")
	await h.until(func(): return ed.playing == "too_late" and ed.last_step == "cards", 15.0)
	var seen: Array = []
	var t_end: float = h.now() + 30.0
	while h.now() < t_end and ed.last_step == "cards":
		var box = h.beat_box()
		if box != null and box.get("cards") != null and box.current_card() != "" and not seen.has(box.current_card()):
			await h.wait(1.2)
			seen.append(box.current_card())
			await h.shot("card_%d" % seen.size())
		await h.wait(0.2)
	h.check("the [DRAFT] surface card shows", seen == Endings.TOO_LATE_SURFACE_CARDS, seen)
	await h.until(func(): return Level.stage.endingPanel != null, 20.0)
	await h.wait(3.0)
	var panel = Level.stage.endingPanel
	await h.shot("too_late_end_screen")
	h.check("the end screen reads \"%s\"" % Endings.TOO_LATE_TITLE, panel != null and panel.titleLabel.text == Endings.TOO_LATE_TITLE, panel.titleLabel.text if panel != null else "")
	h.check("the run is lost, not won; one end screen", GameWorld.lost and not GameWorld.won and Level.mode.end_screens == 1, [GameWorld.lost, GameWorld.won, Level.mode.end_screens])


# Boarding mid-rise: the doom ending wins the run; the lava stops with it.
func _board(h, k, ship) -> void:
	h.down("ui_left")
	var t_end: float = h.now() + 6.0
	while h.now() < t_end and not (ship.can_focus(k) and k.focussedUsable == ship._usable):
		await h.frames(1)
	h.up("ui_left")
	await h.wait(0.3)
	h.check("the hatch has the focus mid-rise", k.focussedUsable == ship._usable, str(k.focussedUsable))
	h.down("ui_select")
	await h.wait(1.6)
	h.up("ui_select")
	var ending: bool = await h.until(func(): return Level.mode.is_ending(), 5.0)
	h.check("boarding mid-rise starts the doom ending", ending, Level.mode.is_ending())
	var row_at: float = rise.row
	await h.shot("boarded_mid_rise")
	await h.wait(4.0)
	h.check("the lava stops where it was once the ending starts", absf(rise.row - row_at) < 0.3 and rise.row > float(Flood.SURFACE_ROW), [row_at, rise.row])
	var id: String = await h.read_beat("thanks", 20.0, false)
	h.check("the horror thanks the keeper (doom_thanks)", id == "doom_thanks", id)
	var won: bool = await h.until(func(): return GameWorld.won, 90.0)
	h.check("a won run (the doom ending), no too-late", won and Level.mode.too_late_shown.is_empty() and _RisingLava.state() == "rising", [GameWorld.won, Level.mode.too_late_shown, _RisingLava.state()])
	await h.until(func(): return Level.stage.endingPanel != null, 40.0)
	await h.wait(2.0)
	await h.shot("doom_end_screen")
