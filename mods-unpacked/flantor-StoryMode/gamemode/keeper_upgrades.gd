extends RefCounted

# Story Mode's per-keeper shop entries (#265): Heat Shielding I-IV and the Suit
# Blaster, bought per player the way vanilla v5 sells keeper-tree upgrades.
#
# Vanilla: the keeper root (keeper1) is added per player (LevelKeeperSpawner:
# addUpgrade("keeper1", "player2")), so everything after it is instanced with
# the player's id: player2.drill1, limited by player2.mining, raising
# player2.keeper1.drillStrength. GameWorld.prepareLevelStart makes the
# <playerId>.mining / .carry limits available for each keeper; the shop
# (TechTree.calculateTracks) shows team1.<id> and <playerId>.<id>, so each
# player sees its own keeper track.
#
# Story Mode's entries hang off keeper1 too (data/upgrades.yaml) with the limit
# `storykeeper`, which is per player the same way: <playerId>.storykeeper, made
# available here for Story Mode runs only (mod_main.gd prepareGameMode), so
# vanilla modes never offer them. player2.storyheatshield2 sets
# player2.suit.heatshield = 2 (LavaData.shield_tier reads it per keeper).

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow

const LIMIT := "storykeeper"
const HEAT_SHIELD := "storyheatshield"   # + tier, 1..TIERS
const TIERS := 4
const BLASTER_ENTRY := "storysuitblaster"
# Before #265 the team held the tier (and the shop entries were team1.*).
const OLD_TEAM := "team1"
const OLD_TEAM_TIER_KEY := "team1.suit.heatshield"


# Makes <playerId>.storykeeper available for each of `player_ids`. True if any
# was missing.
static func add_limits(player_ids: Array) -> bool:
	var added := false
	for pid: String in player_ids:
		var limit: String = pid + "." + LIMIT
		if not GameWorld.isUpgradeLimitAvailable(limit):
			GameWorld.setUpgradeLimitAvailable(limit)
			added = true
	return added


# Every keeper's playerId in this run: the loadout's (a keeper of a player who
# left is still there for a drop-in) and every live keeper's.
static func player_ids() -> Array:
	var out: Array = []
	if Level.loadout != null:
		for lk in Level.loadout.keepers:
			if not out.has(lk.playerId):
				out.append(lk.playerId)
	for k in Keepers.getAll():
		if is_instance_valid(k) and not out.has(k.playerId):
			out.append(k.playerId)
	return out


# The team's teamId for a keeper's playerId.
static func team_of(pid: String) -> String:
	return Keepers.getKeeper(pid).teamId if Keepers.hasKeeper(pid) else OLD_TEAM


# Gives `pid` Heat Shielding up to `tier` for free (dev gear, old saves). Host
# only; vanilla's serverAddUpgrade sends each one to the clients.
static func give_heat_shield(pid: String, tier: int = TIERS) -> Array:
	var given: Array = []
	if not GameWorld.multiplayer.is_server():
		return given
	for n in range(1, mini(tier, TIERS) + 1):
		var id: String = "%s.%s%d" % [pid, HEAT_SHIELD, n]
		if GameWorld.boughtUpgrades.has(id):
			continue
		if not GameWorld.upgrades.has(id):
			ModLoaderLog.warning("No %s in the shop to give" % id, Story.LOG)
			break
		GameWorld.serverAddUpgrade(id, team_of(pid))
		given.append(id)
	return given


# A keeper that has the Suit Blaster (granted some other way: dev gear, a save
# from before #265) has its own shop entry marked bought, so it isn't sold again.
static func mark_blaster_entries() -> void:
	if not GameWorld.multiplayer.is_server():
		return
	for pid: String in player_ids():
		var entry: String = pid + "." + BLASTER_ENTRY
		if GameWorld.boughtUpgrades.has(pid + ".suitblaster") and GameWorld.upgrades.has(entry) and not GameWorld.boughtUpgrades.has(entry):
			GameWorld.serverAddUpgrade(entry, team_of(pid))


# After a save loads, on the host (gamemode/Storymode.gd). A save from before
# #265 has no <playerId>.storykeeper limits and no per-keeper entries, and holds
# the team's entries and tier instead: every keeper gets the team's tier (the
# team's purchase protected everyone then), the team's entries leave the shop,
# and a keeper with the Suit Blaster has its own entry marked bought.
static func after_load() -> void:
	if not _Story.is_story() or not GameWorld.multiplayer.is_server():
		return
	var pids: Array = player_ids()
	var changed: bool = add_limits(pids)
	# The team's tier: its bought entries (the Data key too, for a save that set it
	# straight, as the boss dev gear did).
	var tier := 0
	for n in range(TIERS, 0, -1):
		if GameWorld.boughtUpgrades.has("%s.%s%d" % [OLD_TEAM, HEAT_SHIELD, n]):
			tier = n
			break
	tier = maxi(tier, clampi(int(Data.ofOr(OLD_TEAM_TIER_KEY, 0)), 0, TIERS))
	var dropped: Array = []
	for raw: String in _team_entries():
		var id: String = OLD_TEAM + "." + raw
		if GameWorld.upgrades.has(id) or GameWorld.boughtUpgrades.has(id):
			GameWorld.upgrades.erase(id)
			GameWorld.boughtUpgrades.erase(id)
			dropped.append(id)
	if changed or not dropped.is_empty():
		for pid: String in pids:
			GameWorld.updateAvailableUpgrades(pid)
		GameWorld.updateAvailableUpgrades(OLD_TEAM)
	var given: Array = []
	if tier > 0:
		for pid: String in pids:
			if int(Data.ofOr(pid + ".suit.heatshield", 0)) < tier:
				given.append_array(give_heat_shield(pid, tier))
		Data.apply(OLD_TEAM_TIER_KEY, 0)
	mark_blaster_entries()
	if changed or not dropped.is_empty() or not given.is_empty():
		ModLoaderLog.info("Save from before #265: per-keeper limits %s, team entries dropped %s, Heat Shielding %d given: %s" % [
			str(changed), str(dropped), tier, str(given)], Story.LOG)
		# Clients already in the level get the new shop as vanilla sends it.
		for c in Network.clients:
			if c.connection_state == Network.ConnectionState.LEVEL_STAGE_SYNC:
				c.set_upgrade_data(GameWorld.getUpgradeData())


static func _team_entries() -> Array:
	var out: Array = [BLASTER_ENTRY]
	for n in range(1, TIERS + 1):
		out.append(HEAT_SHIELD + str(n))
	return out
