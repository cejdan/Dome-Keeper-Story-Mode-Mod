extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #251 (2/2), host half: a new process loads t251_mp_save_host's online save
# the way Continue Multiplayer does. In vanilla's keeper choice each player
# walks into their own saved keeper: the host here, the client in
# t251_mp_load_client (nobody picks for anyone). The host starts the run and
# checks each player is on the keeper they saved with.
# `-Extra "--vanilla"` loads the Relic Hunt save instead.
# Run t251_mp_save_host / t251_mp_save_client first (with the same -Extra).
# Pair: t251_mp_load_client (mp_playtest.ps1 -ClientDelay 12).

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const Save = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t251_mp_save_host.gd")
static var _Save = Save  # calls go through this: lazy_preload makes const-preload calls slow
const TIMEOUT := 300


func boot() -> Dictionary:
	return {"loadout": true, "netload": _Save.slot()}


func run(h) -> void:
	var f := FileAccess.open(_Save.saved_path(), FileAccess.READ)
	h.check("the first session's notes are there", f != null, _Save.saved_path())
	if f == null:
		return
	var saved: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var st = Level.stage
	h.check("the keeper choice opened for the save", st is DeviceSelectionStage, str(st))
	if not st is DeviceSelectionStage:
		return
	var mine_in: bool = await h.until(func():
		if h.choice_keeper() == null:
			h.press("ui_down")
		return h.choice_keeper() != null, 20.0)
	h.check("the host's player is in the keeper choice", mine_in, h.lobby_rows())
	var joined: bool = await h.until(func(): return Lobby.members.size() >= 2, 90.0)
	h.check("the client joined the keeper choice", joined, h.lobby_rows())
	if not joined:
		return
	# The host walks into its own saved keeper. `--instantpick`: it takes it
	# the moment the client is in the lobby instead, as t232_mp_load_host
	# does (the timing behind #251's errors).
	var took: String = ""
	var t0: float = h.now()
	while took == "" and h.now() - t0 < 30.0:
		if _Story.has_user_arg("instantpick"):
			var lk = h.free_saved_keeper(true)
			if lk != null and h.choose_keeper(true):
				took = lk.playerId
		else:
			took = await h.walk_into_choice(true, saved["host"]["playerId"])
		if took == "":
			await h.wait(0.5)
	await h.until(func(): return st.playerIdByPeerDeviceId.values().has(took), 10.0)
	h.check("the host took its saved keeper", took == saved["host"]["playerId"] and st.playerIdByPeerDeviceId.values().has(took), {"took": took, "saved": saved["host"], "taken": st.playerIdByPeerDeviceId})
	# The client walks into its own (t251_mp_load_client).
	var both: bool = await h.until(func(): return st.playerIdByPeerDeviceId.size() >= 2, 90.0)
	h.check("the client took a saved keeper itself", both, st.playerIdByPeerDeviceId)
	await h.shot("host_keeper_choice")
	if not both:
		return
	await h.until(func(): return Network.clients.all(func(c): return c.connection_state == Network.ConnectionState.DEVICE_SELECTION_STAGE_SYNC), 20.0)
	await h.wait(1.0)
	st.startRun()
	var started: bool = await h.until(func(): return is_instance_valid(Level.stage) and Level.stage is LevelStage and Level.stage.get("keeperInputStarted") == true and Level.map != null and Level.map.isMapReady() and not SaveGame.currentLoadingSavegame, 180.0)
	h.check("the saved run started", started)
	if not started:
		return
	h.disable_waves()
	var synced: bool = await h.until(func(): return not Network.clients.is_empty() and Network.clients.all(func(c): return c.connection_state == Network.ConnectionState.LEVEL_STAGE_SYNC), 90.0)
	h.check("the client is in the run", synced, Network.clients.map(func(c): return c.connection_state))
	var now: Dictionary = {}
	for k in Keepers.getAll():
		now["host" if k.peerId == 1 else "client"] = {"playerId": k.playerId, "techId": k.techId}
	h.note("keepers in the run", now)
	h.check("each player is on their saved keeper", now == saved, {"now": now, "saved": saved})
	await h.wait(1.0)
	await h.shot("host_loaded")
	share("loaded", now)
	await host_wait_clients_left(h, 60.0)
