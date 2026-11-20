extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #232 (2/2), host half: a new process loads the online save t232_mp_save_host
# wrote (multiplayer folder, slot 31) the way Continue Multiplayer does: it
# hosts, the keeper choice opens, each player takes a saved keeper (the client
# picks its own, dev/harness.gd), and the host starts. Checks the loaded run
# against user://t232_saved.json, then shares its view for the client.
# Run t232_mp_save_host / t232_mp_save_client first.
# Pair: t232_mp_load_client (mp_playtest.ps1 -ClientDelay 12).

const TIMEOUT := 300
const SAVED := "user://t232_saved.json"
const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
# `--slot=<n> --notes=<user:// path>` load another save checked against its own
# notes (#265: t265_mp_oldsave_host's save from before per-keeper Heat Shielding).


func boot() -> Dictionary:
	# beats: true, so the saved beats are the ones checked (not the harness's mute).
	return {"loadout": true, "netload": int(_Story.user_arg("slot", "31")), "beats": true}


func run(h) -> void:
	var f := FileAccess.open(_Story.user_arg("notes", SAVED), FileAccess.READ)
	h.check("the first session's notes are there", f != null)
	if f == null:
		return
	var saved: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var rooms: Dictionary = saved["rooms"]
	var st = Level.stage
	h.check("the keeper choice opened for the save", st is DeviceSelectionStage, str(st))
	if not st is DeviceSelectionStage:
		return
	h.check("the save hosts an online session", Network.multiplayer_mode == Network.MultiplayerMode.ONLINE_ENET, Network.multiplayer_mode)
	# The host's own player joins the keeper choice with a key press, as there.
	var mine_in: bool = await h.until(func():
		if h.choice_keeper() == null:
			h.press("ui_down")
		return h.choice_keeper() != null, 20.0)
	h.check("the host's player is in the keeper choice", mine_in, h.lobby_rows())
	var joined: bool = await h.until(func(): return Lobby.members.size() >= 2, 90.0)
	h.check("the client joined the keeper choice", joined, {"lobby": h.lobby_rows(), "clients": Network.clients.map(func(c): return [c.peer_id, c.connection_state])})
	if not joined:
		return
	await h.until(func(): return h.choose_keeper(true), 30.0)
	# The client's choice, made here: what its walk into a keeper asks the host
	# (DeviceSelectionStage.serverChangeKeeper). A client walking into its own
	# keeper is t251_mp_load_*.
	await h.until(func():
		for k in Keepers.all.keepers:
			if is_instance_valid(k) and k.isMovementDummy and k.peerId != 1:
				var lk = h.free_saved_keeper(false)
				if lk != null:
					h.note("keeper choice: the client's keeper takes " + lk.playerId, k.playerId)
					st.serverChangeKeeper(k.playerId, lk.playerId)
				return false
		return st.playerIdByPeerDeviceId.size() >= 2, 30.0)
	var both: bool = await h.until(func(): return st.playerIdByPeerDeviceId.size() >= 2, 60.0)
	h.check("both players took a saved keeper", both, st.playerIdByPeerDeviceId)
	await h.until(func(): return Network.clients.all(func(c): return c.connection_state == Network.ConnectionState.DEVICE_SELECTION_STAGE_SYNC), 20.0)
	await h.wait(1.0)
	st.startRun()
	var started: bool = await h.until(func(): return is_instance_valid(Level.stage) and Level.stage is LevelStage and Level.stage.get("keeperInputStarted") == true and Level.map != null and Level.map.isMapReady() and not SaveGame.currentLoadingSavegame, 180.0)
	h.check("the saved run started", started)
	if not started:
		return
	h.disable_waves()
	await h.until(func(): return Level.map.has_node("StoryGasField"), 20.0)
	var synced: bool = await h.until(func(): return not Network.clients.is_empty() and Network.clients.all(func(c): return c.connection_state == Network.ConnectionState.LEVEL_STAGE_SYNC), 90.0)
	h.check("the client is in the run", synced, Network.clients.map(func(c): return c.connection_state))
	var mine := facts(rooms)
	h.note("loaded", mine)
	h.check("the level seed came back", mine["seed"] == int(saved["seed"]), {"now": mine["seed"], "saved": saved["seed"]})
	h.check("the money came back", mine["money"] == int(saved["money"]), {"now": mine["money"], "saved": saved["money"]})
	h.check("the beats played came back", str(Data.ofOr("team1.story.beatsplayed", "")) == saved["beatsplayed"])
	h.check("the translator stage came back", mine["translation"] == int(saved["translation"]), mine["translation"])
	h.check("the heat shield tier came back", mine["heat shield"] == int(saved["heat shield"]), mine["heat shield"])
	if saved.has("heat shields"):
		h.check("each keeper's heat shield tier came back (#265)", mine["heat shields"] == saved["heat shields"], {"now": mine["heat shields"], "saved": saved["heat shields"]})
	h.check("the lava came back", absf(mine["lava room"] - float(saved["saved lava room"])) < 0.1 and absi(mine["lava cells"] - int(saved["saved lava cells"])) < 40,
		{"room": [mine["lava room"], saved["saved lava room"]], "cells": [mine["lava cells"], saved["saved lava cells"]]})
	h.check("the gas came back", absf(mine["gas room"] - float(saved["saved gas room"])) < 0.2 and mine["gas rock"] == int(saved["gas rock"]),
		{"room": [mine["gas room"], saved["saved gas room"]], "rock": [mine["gas rock"], saved["gas rock"]], "cells": [mine["gas cells"], saved["saved gas cells"]]})
	await look_at_rooms(h, rooms)
	await h.shot("host_loaded")
	# The client compares its view with the host's, live.
	for i in 25:
		var now := facts(rooms)
		now["rooms"] = rooms
		now["saved"] = saved
		share("live", now)
		await h.wait(1.0)
		if Network.clients.is_empty():
			break
	await host_wait_clients_left(h, 60.0)
