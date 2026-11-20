extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #223: the client half of an online Story Mode session on this machine. Joins
# t223_mp_host on 127.0.0.1 and starts once its run is playable; then looks at
# what reached it from the host and plays a little.

const TIMEOUT := 420


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	h.check("mode is storymode", Level.loadout.modeId == "storymode", Level.loadout.modeId)
	h.check("mode node loaded", Level.mode != null and Level.mode.has_method("getRunWeight"))
	await h.wait(3.0)
	var rows: Array = []
	for k in Keepers.getAll():
		rows.append({"player": k.playerId, "peer": k.peerId, "local": k.peerId == h.multiplayer.get_unique_id(), "tile": Level.map.getTileCoord(k.global_position)})
	h.note("keepers", rows)
	h.check("two keepers in the run", Keepers.getAll().size() == 2, rows)
	h.check("lava field", Level.map.has_node("StoryLavaField"))
	h.check("gas field", Level.map.has_node("StoryGasField"))
	var lava = Level.map.get_node_or_null("StoryLavaField")
	var gas = Level.map.get_node_or_null("StoryGasField")
	h.note("hazards", {"magma": lava.magma.size() if lava else -1, "gas rock": gas.rock.size() if gas else -1})
	h.snap("start", ["team1.inventory.money", "team1.story.beatsplayed"])
	await h.shot("start")
	await h.hold("ui_left", 0.3)
	await h.hold("ui_down", 8.0)
	await h.shot("client_dug")
	h.note("client keeper tile", h.keeper_tile())
	await h.hold("ui_left", 3.0)
	await h.shot("client_left")
	await h.wait(5.0)
	await h.shot("client_end")
	h.map_png("client_map")
