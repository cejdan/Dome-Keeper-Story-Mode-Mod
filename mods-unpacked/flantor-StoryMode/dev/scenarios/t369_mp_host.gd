extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #369: host half of the online check for the rising lava. The host frees the
# chains (quietly), digs shaft A up from the ocean (its tiles break on the
# client too) and starts the rise: it owns the level and sends it, one number;
# the band's cells never go over the lava stream (they are not in what it
# sent). It shares its level every second for the client to compare. Then the
# client's keeper, caught in the lava, dies in it: the host takes its word
# and ends the run for both, "too late". Pair: t369_mp_client.

const EndGame = preload("res://mods-unpacked/flantor-StoryMode/endgame/end_game.gd")
static var _EndGame = EndGame  # calls go through this: lazy_preload makes const-preload calls slow
const RisingLava = preload("res://mods-unpacked/flantor-StoryMode/endgame/rising_lava.gd")
static var _RisingLava = RisingLava  # calls go through this: lazy_preload makes const-preload calls slow
const Base = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t369_rise.gd")
const TIMEOUT := 480


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if not await host_start(h):
		return
	var ok: bool = await h.until(func(): return _RisingLava.find() != null, 20.0)
	if not h.check("host: the rising lava is built", ok):
		return
	var base = Base.new()
	base.rise = _RisingLava.find()
	base.lava = Level.map.get_node("StoryLavaField")
	base.ocean = Level.map.tileData.get_meta("story_ocean")
	base.ceiling = int(base.ocean["ceiling"])
	base.top = int(base.ocean["top"])
	load("res://mods-unpacked/flantor-StoryMode/dev/boss_dev.gd").give_gear()
	load("res://mods-unpacked/flantor-StoryMode/map/chain_anchors.gd").find().dev_free_all()
	_EndGame.dev_free()
	await base.dig_clean(h, Vector2i(3, 90), Vector2i(4, base.ceiling))
	var k = h.keeper()
	await h.teleport_tile(Vector2i(3, 92))
	share("dug", true)
	await shared_wait_client(h, "client_ready")
	var sent0: Dictionary = base.lava._net_sent.duplicate()
	base.rise.dev_start(float(base.ceiling) + 1.0)
	share("rising", true)
	# The level, every second, for the client to compare with its own.
	var t_end: float = h.now() + 14.0
	while h.now() < t_end:
		await h.wait(1.0)
		base.cool(h)
		share("row", [snappedf(base.rise.row, 0.001), Time.get_ticks_msec()])
	var band: Array = base.lava._fl_band.keys()
	# (A cell that held lava before the flood was sent then; nothing since.)
	var sent: Array = band.filter(func(c): return base.lava._net_sent.get(c, -1.0) != sent0.get(c, -1.0))
	h.check("host: the band's cells were never sent over the lava stream", sent.is_empty() and not band.is_empty(), {"band": band.size(), "sent": sent.slice(0, 6)})
	await h.shot("host_rising")
	share("die", true)
	var ended: bool = await h.until(func():
		base.cool(h)
		return Level.mode.is_ending() and not Level.mode.too_late_shown.is_empty(), 60.0)
	var client_pid: String = ""
	for kk in Keepers.getAll():
		if kk != k:
			client_pid = kk.playerId
	h.check("host: the client's keeper died in the lava: too late, for everyone", ended and Level.mode.too_late_shown == ["lava"] and _RisingLava.events.is_empty() == false, [Level.mode.too_late_shown, client_pid])
	var screen: bool = await h.until(func(): return Level.stage.endingPanel != null, 40.0)
	await h.wait(2.0)
	await h.shot("host_end_screen")
	h.check("host: the run is lost; the end screen", screen and GameWorld.lost and Level.mode.end_screens == 1, [GameWorld.lost, Level.mode.end_screens])
	await host_wait_clients_left(h)


# Waits for the client to say something through its own keeper's state: a
# client can't write Data, so it just waits the time a client needs.
func shared_wait_client(h, _what: String) -> void:
	await h.wait(4.0)
