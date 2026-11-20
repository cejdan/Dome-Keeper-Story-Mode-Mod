extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #232 (1/2), host half: an online Story Mode run under way is saved. Sets up
# money, a played beat, the translator stage, two heat shield tiers, lava in
# one sealed room and gas in another, lets them settle, and saves the run into
# the multiplayer folder (slot SLOT), as vanilla's autosave does online. Writes
# what it saved to user://t232_saved.json for the second session. The client
# compares its view with the host's first. Pair: t232_mp_save_client; then
# t232_mp_load_host / t232_mp_load_client load the save in a new session.

const TIMEOUT := 300
const SLOT := 31
const SAVED := "user://t232_saved.json"


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if not await host_start(h):
		return
	var rooms: Dictionary = await setup_run_state(h)
	if rooms.is_empty():
		return
	await h.wait(6.0)    # the lava levels out on the floor, the gas rises
	var lava = Level.map.get_node("StoryLavaField")
	var gas = Level.map.get_node("StoryGasField")
	await look_at_rooms(h, rooms)
	await h.shot("host_rooms")
	var t0: int = Time.get_ticks_msec()
	SaveGame.saveGame("multiplayer", SLOT, true)
	var save_ms: int = Time.get_ticks_msec() - t0
	var f: Dictionary = facts(rooms)
	var lava_blob: String = str(Data.ofOr("story.lava", ""))
	var gas_blob: String = str(Data.ofOr("story.gas", ""))
	h.check("the run was saved", FileAccess.file_exists("user://multiplayer/savegame_%d.json" % SLOT), save_ms)
	h.check("the lava and gas went into the save's Data", lava_blob.length() > 0 and gas_blob.length() > 0, {"lava bytes": lava_blob.length(), "gas bytes": gas_blob.length()})
	# What the save holds, cell for cell (facts() a moment later may differ).
	var lv = JSON.parse_string(lava_blob)
	var gv = JSON.parse_string(gas_blob)
	var saved_lava := {}
	for e in lv["mass"]:
		saved_lava[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	var saved_gas := {}
	for e in gv["mass"]:
		saved_gas[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	f["saved lava room"] = snappedf(mass_in(saved_lava, room_of(rooms["lava"])), 0.001)
	f["saved gas room"] = snappedf(mass_in(saved_gas, room_of(rooms["gas"])), 0.001)
	f["saved lava cells"] = saved_lava.size()
	f["saved gas cells"] = saved_gas.size()
	f["rooms"] = rooms
	f["beatsplayed"] = str(Data.ofOr("team1.story.beatsplayed", ""))
	h.note("saved", f)
	h.check("lava sits in its room", f["lava room"] > 3.0, f["lava room"])
	h.check("gas sits in its room", f["gas room"] > 3.0, f["gas room"])
	var out := FileAccess.open(SAVED, FileAccess.WRITE)
	out.store_string(JSON.stringify(f))
	out.close()
	share("saved", f)
	await host_wait_clients_left(h, 120.0)
