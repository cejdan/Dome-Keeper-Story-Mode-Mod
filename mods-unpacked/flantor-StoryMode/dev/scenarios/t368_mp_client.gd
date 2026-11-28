extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #368: client half. Its ship is built from the host's map facts, in the
# ocean. The host's last chain reaches it live: the last-chain cutscene
# (#367) plays here too and the ship stands at the dome. Its keeper walks into the dome to
# the hatch by real input (the hatch's focus and prompt are this instance's
# own) and holds the use key: it asks the host, which boards it; the lift-off
# plays here with this keeper aboard, then the host's doom ending (the cards)
# and the end screen "The Planet Is Lost". Pair: t368_mp_host.

const Ship = preload("res://mods-unpacked/flantor-StoryMode/endgame/ship.gd")
static var _Ship = Ship  # calls go through this: lazy_preload makes const-preload calls slow
const Endings = preload("res://mods-unpacked/flantor-StoryMode/data/endings.gd")
const Base = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t368_land.gd")
const TIMEOUT := 420


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var ready = await shared(h, "ready", 150.0)
	if not h.check("host ready", ready != null):
		return
	var ok: bool = await h.until(func(): return _Ship.find() != null and h.keeper() != null, 30.0)
	if not h.check("client: the ship is built from the host's map facts", ok):
		return
	var ship = _Ship.find()
	h.check("client: in the ocean", ship.mode == "ocean", ship.mode)
	var k = h.keeper()
	var base = Base.new()
	base.ship = ship
	await base.go_home(h, k)
	var landed: bool = await h.until(func(): return ship.mode == "dome", 45.0)
	var whats: Array = _Ship.events.map(func(e): return e["what"])
	h.check("client: the host's last chain plays here live: the cutscene takes the ship, then at the dome", landed and whats.has("free_live") and whats.has("taken")
		and _Ship.events.any(func(e): return e["what"] == "landed" and e["live"]), _Ship.events)
	await shared(h, "landed", 45.0)
	var LastChain = load("res://mods-unpacked/flantor-StoryMode/endgame/last_chain.gd")
	await h.until(func(): return LastChain.is_done() and not GameWorld.paused, 40.0)
	await h.wait(0.5)
	await h.shot("client_ship_at_dome")
	var got: bool = await base.walk_to_hatch(h, k)
	h.check("client: its keeper walks to the hatch: focus and prompt here", got and ship._prompt.visible, [str(k.focussedUsable), k.global_position - Level.getDome("team1").global_position])
	await h.shot("client_prompt")
	h.down("ui_select")
	var lifting: bool = await h.until(func(): return ship.mode == "lifting", 6.0)
	h.up("ui_select")
	var asked: Array = _Ship.events.filter(func(e): return e["what"] == "board_asked")
	var lift: Array = _Ship.events.filter(func(e): return e["what"] == "lift_off")
	h.check("client: holding the use key asks the host, which lifts off with this keeper aboard", lifting and asked.size() == 1 and lift.size() == 1 and lift[0]["player"] == k.playerId, _Ship.events)
	await h.wait(2.5)
	await h.shot("client_liftoff")
	var gone: bool = await h.until(func(): return ship.mode == "gone", 10.0)
	h.check("client: the ship climbs out of sight", gone, ship.mode)
	var panel: bool = await h.until(func(): return Level.stage.endingPanel != null, 90.0)
	await h.wait(1.0)
	await h.shot("client_end_screen")
	h.check("client: the doom ending's end screen", panel and GameWorld.won and Level.stage.endingPanel.titleLabel.text == Endings.DOOM_TITLE, [GameWorld.won, Level.stage.endingPanel.titleLabel.text if panel else null])
	var ed = Level.mode.get_node_or_null("StoryEndings")
	h.check("client: the host's cards showed here", ed != null and ed.cards_shown >= 1, ed.cards_shown if ed != null else null)
	await shared(h, "done", 30.0)
