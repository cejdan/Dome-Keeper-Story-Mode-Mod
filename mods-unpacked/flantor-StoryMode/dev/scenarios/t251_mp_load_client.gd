extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #251 (2/2), client half: joins the host that loaded an online save, walks
# into its own saved keeper in the keeper choice, and plays the run on it.
# Pair: t251_mp_load_host.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
const Save = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t251_mp_save_host.gd")
const TIMEOUT := 300


func boot() -> Dictionary:
	# `loadout`: begin in the keeper choice, not once the run is playable.
	return {"netjoin": true, "loadout": true}


func _view(st) -> Dictionary:
	return {
		"keepers": Keepers.all.keepers.filter(func(x): return is_instance_valid(x)).map(func(x): return [x.playerId, x.peerId, x.deviceId, x.isMovementDummy]),
		"taken": st.playerIdByPeerDeviceId if is_instance_valid(st) and st is DeviceSelectionStage else {},
		"lobby": h_lobby(),
	}


func h_lobby() -> Array:
	return Lobby.members.map(func(m): return [m.peer_id, m.device_id, m.player_id])


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Save.saved_path()))
	var st = Level.stage
	h.check("the keeper choice opened here", st is DeviceSelectionStage, str(st))
	if not st is DeviceSelectionStage:
		return
	var me_in: bool = await h.until(func(): return h.choice_keeper() != null, 30.0)
	h.note("client view in the keeper choice", _view(st))
	h.check("this client's player is in the keeper choice", me_in, _view(st))
	var took: String = ""
	var t0: float = h.now()
	while took == "" and h.now() - t0 < 60.0:
		took = await h.walk_into_choice(false, saved["client"]["playerId"])
		if took == "":
			await h.wait(0.5)
	var key: String = "%d-" % h.multiplayer.get_unique_id()
	var mine := func():
		for k in st.playerIdByPeerDeviceId:
			if str(k).begins_with(key):
				return st.playerIdByPeerDeviceId[k]
		return ""
	await h.until(func(): return mine.call() != "", 15.0)
	h.note("client view after its choice", _view(st))
	h.check("this client took its saved keeper by walking into it", took == saved["client"]["playerId"] and mine.call() == took, {"took": took, "saved": saved["client"], "view": _view(st)})
	await h.shot("client_keeper_choice")
	var started: bool = await h.until(func(): return is_instance_valid(Level.stage) and Level.stage is LevelStage and Level.stage.get("keeperInputStarted") == true and Level.map != null and Level.map.isMapReady(), 180.0)
	h.check("the run started here", started)
	if not started:
		return
	var loaded = await shared(h, "loaded", 60.0)
	h.check("the host shared its keepers", loaded is Dictionary, loaded)
	var now: Dictionary = {}
	for k in Keepers.getAll():
		now["host" if k.peerId == 1 else "client"] = {"playerId": k.playerId, "techId": k.techId}
	h.note("keepers in the run (client)", now)
	h.check("each player is on their saved keeper (client)", now == saved, {"now": now, "saved": saved})
	var lk = Story.local_keeper()
	h.check("this client plays its saved keeper", lk != null and lk.playerId == saved["client"]["playerId"], lk.playerId if lk else null)
	await h.wait(1.0)
	await h.shot("client_loaded")
