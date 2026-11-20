extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #265, online, client half of the old-style save: joins and stays until the
# host has saved (its own view of the old state isn't checked: the host turns
# the run old by hand, and Data it erases is not erased here).
# Pair: t265_mp_oldsave_host.

const TIMEOUT := 300


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var saved = await shared(h, "saved", 150.0)
	h.check("the host saved", saved == true)
	await h.wait(1.0)
