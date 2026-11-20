extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #265, online, host half of the save: an online run as a save from before
# #265 holds it (dev/old_heat_save.gd): the team bought Heat Shielding I-II
# and the Suit Blaster, which every keeper has. Saved into the multiplayer
# folder, slot SLOT, with the notes t232_mp_load_host checks the load against:
# after the load both keepers must be at tier II ("heat shields" "2,2").
# Pair: t265_mp_oldsave_client. Then load it with
#   mp_playtest.ps1 t232_mp_load_host t232_mp_load_client -ClientDelay 12 -Extra "--slot=32 --notes=user://t265_saved.json"

const TIMEOUT := 300
const SLOT := 32
const SAVED := "user://t265_saved.json"
const OldSave = preload("res://mods-unpacked/flantor-StoryMode/dev/old_heat_save.gd")
static var _OldSave = OldSave  # calls go through this: lazy_preload makes const-preload calls slow


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if not await host_start(h):
		return
	var rooms: Dictionary = await setup_run_state(h)
	if rooms.is_empty():
		return
	await h.wait(6.0)
	var old: Dictionary = _OldSave.make_old(2, true)
	h.note("made old", old)
	h.check("the run looks like a save from before #265", old["limits"].is_empty() and old["players"].size() == 2 and int(Data.ofOr("team1.suit.heatshield", 0)) == 2
		and old["bought"].has("player2.suitblaster"), old)
	await h.wait(1.0)
	SaveGame.saveGame("multiplayer", SLOT, true)
	var f: Dictionary = facts(rooms)
	# What the load must show: the team's tier on every keeper.
	f["heat shield"] = 2
	f["heat shields"] = "2,2"
	var lava_blob: String = str(Data.ofOr("story.lava", ""))
	var gas_blob: String = str(Data.ofOr("story.gas", ""))
	var saved_lava := {}
	for e in JSON.parse_string(lava_blob)["mass"]:
		saved_lava[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	var saved_gas := {}
	for e in JSON.parse_string(gas_blob)["mass"]:
		saved_gas[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	f["saved lava room"] = snappedf(mass_in(saved_lava, room_of(rooms["lava"])), 0.001)
	f["saved gas room"] = snappedf(mass_in(saved_gas, room_of(rooms["gas"])), 0.001)
	f["saved lava cells"] = saved_lava.size()
	f["saved gas cells"] = saved_gas.size()
	f["rooms"] = rooms
	f["beatsplayed"] = str(Data.ofOr("team1.story.beatsplayed", ""))
	h.check("the run was saved", FileAccess.file_exists("user://multiplayer/savegame_%d.json" % SLOT))
	var out := FileAccess.open(SAVED, FileAccess.WRITE)
	out.store_string(JSON.stringify(f))
	out.close()
	h.note("saved", f)
	share("saved", true)
	await host_wait_clients_left(h, 60.0)
