extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #369: client half. The host starts the rise; this instance follows its
# level (one number a few times a second, extrapolated in between) and fills
# its own band from it: its level stays within a row of the host's (compared
# with what the host shares each second), its band's cells are lava here,
# the cells under it implied, the lava shows in its shaft (shot). Its keeper
# feels the warning. Then its keeper goes down into the lava and its suit
# gives out: it asks the host, the run ends for both ("too late"): the moment,
# the card, the end screen here too. Pair: t369_mp_host.

const RisingLava = preload("res://mods-unpacked/flantor-StoryMode/endgame/rising_lava.gd")
static var _RisingLava = RisingLava  # calls go through this: lazy_preload makes const-preload calls slow
const Endings = preload("res://mods-unpacked/flantor-StoryMode/data/endings.gd")
const TIMEOUT := 480


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var dug = await shared(h, "dug", 200.0)
	if not h.check("host dug the shaft", dug != null):
		return
	var rise = _RisingLava.find()
	var lava = Level.map.get_node("StoryLavaField")
	var ocean: Dictionary = Level.map.tileData.get_meta("story_ocean")
	var ceiling: int = int(ocean["ceiling"])
	h.check("client: the rising lava is built, nothing rising yet", rise != null and _RisingLava.state() == "" and not lava.flood_active(), _RisingLava.state())
	var gas = Level.map.get_node_or_null("StoryGasField")
	if gas != null:
		gas.freeze_toxin = true
	var k = h.keeper()
	await h.teleport_tile(Vector2i(3, ceiling - 14))
	await shared(h, "rising", 60.0)
	var on: bool = await h.until(func(): return _RisingLava.state() == "rising" and lava.flood_active(), 10.0)
	h.check("client: the host's rise reached it (state and level)", on and rise.row <= float(ceiling) + 1.01, [_RisingLava.state(), rise.row])
	h.check("client: told live (the roar)", _RisingLava.events.any(func(e): return e["what"] == "started" and e["live"]), _RisingLava.events)
	var diffs: Array = []
	var last_seen: int = -1
	var t_end: float = h.now() + 12.0
	while h.now() < t_end:
		await h.wait(0.25)
		lava.set_heat_of(k, 0.0)
		var r = await shared(h, "row", 5.0)
		if r != null and int(r[1]) != last_seen:
			last_seen = int(r[1])
			diffs.append(snappedf(float(r[0]) - rise.row, 0.01))
	h.note("client: host row - client row, as each word arrived", diffs)
	h.check("client: its level follows the host's (within 1.5 rows: the shared word itself comes late)", not diffs.is_empty() and diffs.all(func(d): return absf(d) < 1.5), diffs)
	var top: int = int(floor(rise.row))
	var band_cell := Vector2i(3, top + 1)
	var col: Array = []
	for y in range(top - 1, top + 5):
		for x in [3, 4]:
			var c := Vector2i(x, y)
			col.append([x, y, Level.map.tileData.get_resourcev(c), lava._fl_band.has(c), snappedf(lava.mass.get(c, 0.0), 0.01)])
	h.note("client: the shaft at the band", {"cells": col, "harden": lava.hardened, "row": rise.row})
	# (The host's dev dig doesn't reach a client cell for cell, so the check
	# takes the band's cells as this instance's map has them.)
	var full: Array = lava._fl_band.keys().filter(func(c): return c.y > top)
	var st: Dictionary = lava.flood_stats()
	var stored_under: Array = lava.mass.keys().filter(func(c): return c.y >= st["implied"][0] and c.y < st["implied"][1])
	h.check("client: its own band is lava here (filled from the level), the cells under it implied, none stored", not full.is_empty() and full.all(func(c): return lava.mass.get(c, 0.0) >= 0.99) and st["implied_seen"] > 0 and stored_under.is_empty(),
		{"full_cells": full.size(), "not_full": full.filter(func(c): return lava.mass.get(c, 0.0) < 0.99).slice(0, 6), "stored_under": stored_under.slice(0, 6), "stats": st})
	await h.teleport_tile(Vector2i(3, top - 5))
	await h.wait(0.5)
	lava.set_heat_of(k, 0.0)
	h.check("client: its keeper feels the warning", float(rise.closeness.get(k.playerId, 0.0)) > 0.7, rise.closeness)
	await h.shot("client_lava_below")
	await shared(h, "die", 60.0)
	await h.teleport_tile(Vector2i(3, int(ceil(rise.row)) + 4))
	await h.frames(2)
	h.check("client: down in the lava", lava.keeper_in_lava(k), lava.flood_stats())
	lava.set_heat_of(k, lava.HEAT_MAX * 0.98)
	var ended: bool = await h.until(func(): return Level.mode.is_ending(), 15.0)
	h.check("client: its suit gave out: the host ends the run for both", ended and _RisingLava.events.any(func(e): return e["what"] == "death"), _RisingLava.events)
	await h.until(func(): return Level.mode.too_late_shown.size() > 0, 10.0)
	h.check("client: the too-late moment plays here", Level.mode.too_late_shown == ["lava"], Level.mode.too_late_shown)
	h.check("client: no recall (it stayed in the lava)", lava.recalls == 0, lava.recalls)
	await h.wait(0.6)
	await h.shot("client_too_late")
	var screen: bool = await h.until(func(): return Level.stage.endingPanel != null, 60.0)
	await h.wait(2.0)
	var panel = Level.stage.endingPanel
	await h.shot("client_end_screen")
	h.check("client: the end screen reads \"%s\"" % Endings.TOO_LATE_TITLE, screen and panel.titleLabel.text == Endings.TOO_LATE_TITLE, panel.titleLabel.text if panel != null else "")
