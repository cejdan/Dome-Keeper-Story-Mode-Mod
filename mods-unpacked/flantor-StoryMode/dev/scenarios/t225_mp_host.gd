extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #225: host half. Shares its lava, gas and chain counts so the client can
# compare them with its own. Pair: t225_mp_client.

const TIMEOUT := 420


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if not await host_start(h):
		return
	var counts: Dictionary = _counts()
	h.note("host hazard counts", counts)
	share("counts", counts)
	await h.wait(1.0)
	await h.shot("host_start")
	await host_wait_clients_left(h)


static func _counts() -> Dictionary:
	var lava = Level.map.get_node_or_null("StoryLavaField")
	var gas = Level.map.get_node_or_null("StoryGasField")
	var chains: int = -1
	for c in Level.map.get_children():
		if c.get("chains") is Array:
			chains = c.chains.size()
	return {"magma": lava.magma.size() if lava else -1, "lava cells": lava.mass.size() if lava else -1, "gas rock": gas.rock.size() if gas else -1, "chains": chains}
