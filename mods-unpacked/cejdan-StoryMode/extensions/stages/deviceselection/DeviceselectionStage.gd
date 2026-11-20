extends "res://stages/deviceselection/DeviceselectionStage.gd"

# Vanilla's keeper choice in a Story Mode save (loading an online save, a
# drop-in): a keeper taken while a client is still spawning the choice's
# keepers waits until that client is in sync. Vanilla tells a client of a taken
# keeper only once it is in DEVICE_SELECTION_STAGE_SYNC, and its catch-up then
# replaces the client's own keeper with the host's (#251; vanilla Relic Hunt
# does the same: t251_mp_load_* -Extra "--vanilla --instantpick").

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")

# Longest wait for a spawning client before taking the keeper anyway.
const SPAWN_WAIT := 15.0

var _story_pending: Dictionary = {}


@rpc("reliable", "any_peer")
func serverChangeKeeper(currentPlayerId: String, newPlayerId: String) -> void:
	if Level.loadout == null or Level.loadout.modeId != Story.MODE_ID or not multiplayer.is_server() or clientOnlyMode:
		super(currentPlayerId, newPlayerId)
		return
	if _story_pending.has(currentPlayerId):
		return
	if _story_client_spawning():
		_story_pending[currentPlayerId] = true
		var t0: int = Time.get_ticks_msec()
		while is_inside_tree() and _story_client_spawning() and Time.get_ticks_msec() - t0 < SPAWN_WAIT * 1000:
			await get_tree().process_frame
		_story_pending.erase(currentPlayerId)
		if not is_inside_tree() or startedRun or Keepers.getKeeper(currentPlayerId) == null:
			return
		ModLoaderLog.info("Keeper choice: %s takes %s once the clients are in sync (%d ms)" % [currentPlayerId, newPlayerId, Time.get_ticks_msec() - t0], Story.LOG)
	super(currentPlayerId, newPlayerId)


# Vanilla's _process writes each local keeper's movement keys straight into
# Data.values every frame, so they never go out in a Data delta: a client has
# the host's keeper's keys only once a full sync brings them, and a keeper
# taken after the last one (the host's, as the client syncs) reads them on the
# client every frame until then ("Tried to access unknown data
# player1.keeper1.maxspeed"; a vanilla save logs it too, for fewer frames).
# A client fills a missing key of another keeper from its own keeper of the
# same kind (vanilla's same fixed values; Story Mode keepers are all the
# Engineer). The host's value replaces it when it lands.
func _process(delta: float) -> void:
	super(delta)
	if multiplayer.is_server() or Level.loadout == null or Level.loadout.modeId != Story.MODE_ID:
		return
	var local: Dictionary = {}
	for keeper: Keeper in Keepers.local.getAll():
		local[keeper.techId] = keeper.playerId
	for keeper: Keeper in Keepers.getAll():
		if not is_instance_valid(keeper) or keeper.is_multiplayer_authority() or not local.has(keeper.techId):
			continue
		if Data.values.has(keeper.playerId + ".keeper.speedbuff"):
			continue
		var mine: String = local[keeper.techId]
		for suffix: String in [".keeper.speedbuff", ".keeper.drillbuff", ".keeper.zoominmine", ".keeper.additionalupwardsspeed"]:
			_story_fill(keeper.playerId + suffix, mine + suffix)
		var tech: String = "." + keeper.techId + "."
		for key: String in Data.values.keys():
			if key.begins_with(mine + tech):
				_story_fill(keeper.playerId + key.substr(mine.length()), key)


func _story_fill(key: String, from: String) -> void:
	if not Data.values.has(key) and Data.values.has(from):
		Data.values[key] = Data.values[from]


func _story_client_spawning() -> bool:
	for c in Network.clients:
		if c.connection_state == Network.ConnectionState.DEVICE_SELECTION_STAGE_SPAWN:
			return true
	return false
