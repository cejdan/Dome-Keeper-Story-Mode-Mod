extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #251 (1/2), client half: stays in the run until the host has saved it, then
# leaves. Pair: t251_mp_save_host.

const TIMEOUT := 300


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var saved = await shared(h, "saved", 150.0)
	h.check("the host saved the run", saved is Dictionary, saved)
	await h.shot("client_saved")
