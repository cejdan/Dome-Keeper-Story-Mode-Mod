extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #232 (1/2), client half: before the host saves, this client sees the run the
# host set up (the baseline for the reloaded session), then leaves.
# Pair: t232_mp_save_host.

const TIMEOUT := 300


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var saved = await shared(h, "saved", 150.0)
	h.check("the host saved the run", saved is Dictionary, saved)
	if not saved is Dictionary:
		return
	await h.wait(1.5)
	var rooms: Dictionary = saved["rooms"]
	var mine := facts(rooms)
	h.note("client facts", mine)
	check_facts(h, mine, saved, "before the save")
	# The save's lava and gas blobs stay on the host (StoryNet.save_blob).
	h.check("the save blobs were not sent here", str(Data.ofOr("story.lava", "")) == "" and str(Data.ofOr("story.gas", "")) == "",
		{"lava": str(Data.ofOr("story.lava", "")).length(), "gas": str(Data.ofOr("story.gas", "")).length()})
	await look_at_rooms(h, rooms)
	await h.wait(1.0)
	await h.shot("client_rooms")
