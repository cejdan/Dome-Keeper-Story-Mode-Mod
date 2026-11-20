extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #246: the third player, first time in: plays the start of the run and quits
# when the host names it. t246_mp_late_join_rejoin comes back in its place.
# Pair: t246_mp_late_join_host.

const TIMEOUT := 240


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	var leave = await shared(h, "leave", 120.0)
	h.check("the host asks this client to leave", leave != null and int(leave) == h.multiplayer.get_unique_id(), [leave, h.multiplayer.get_unique_id()])
