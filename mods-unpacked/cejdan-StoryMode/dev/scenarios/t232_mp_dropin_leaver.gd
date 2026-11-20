extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #232 (drop-in), the first client: plays the start of the run, then leaves
# when the host says (its process quits). t232_mp_dropin_client joins again in
# its place. Pair: t232_mp_dropin_host.

const TIMEOUT := 240


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var ready = await shared(h, "ready", 180.0)
	h.check("the host set the run up", ready is Dictionary, ready)
	h.note("leaving as", Keepers.first().playerId if Keepers.first() != null else "")
