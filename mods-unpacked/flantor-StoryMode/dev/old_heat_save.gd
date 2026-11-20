extends RefCounted

# Dev-only (#265): turns the run under way into one as a save from before #265
# holds it, so a save written now loads the way such a save does. Before #265
# the team held Heat Shielding (team1.storyheatshield1-4 hanging off the
# storymode root, Data team1.suit.heatshield) and the Suit Blaster entry
# (team1.storysuitblaster, which granted every keeper's suitblaster); there
# were no <playerId>.storykeeper limits and no per-keeper entries.
# Host only. Returns what it did, for the scenario's notes.

const KeeperUpgrades = preload("res://mods-unpacked/flantor-StoryMode/gamemode/keeper_upgrades.gd")
static var _KeeperUpgrades = KeeperUpgrades  # calls go through this: lazy_preload makes const-preload calls slow


static func make_old(tier: int, blaster: bool) -> Dictionary:
	var gw = GameWorld
	var pids: Array = _KeeperUpgrades.player_ids()
	# The per-keeper side goes: limits, entries (bought or not), Data.
	for pid: String in pids:
		gw.upgradeLimits.erase(pid + "." + KeeperUpgrades.LIMIT)
		for raw: String in _KeeperUpgrades._team_entries():
			gw.upgrades.erase(pid + "." + raw)
			gw.boughtUpgrades.erase(pid + "." + raw)
		Data.values.erase(pid + ".suit.heatshield")
	# The team's entries, as #44 / #18 made them.
	for raw: String in _KeeperUpgrades._team_entries():
		var u: Dictionary = Data.deepDuplicateUpgrade(Data.upgrades[raw])
		u.erase("limit")
		if u.get("predecessors", []).has("keeper1"):
			u["predecessors"] = ["storymode"]
			u.erase("predecessorsany")
		Data.makeInstancedUpgrade(u, "team1")
		gw.upgrades[u["id"]] = u
	for n in range(1, tier + 1):
		gw.boughtUpgrades.append("team1.storyheatshield%d" % n)
	Data.apply(KeeperUpgrades.OLD_TEAM_TIER_KEY, tier)
	if blaster:
		gw.boughtUpgrades.append("team1.storysuitblaster")
		for pid: String in pids:
			if not gw.boughtUpgrades.has(pid + ".suitblaster"):
				gw.serverAddUpgrade(pid + ".suitblaster", _KeeperUpgrades.team_of(pid))
	return {
		"players": pids, "tier": tier, "blaster": blaster,
		"team entries": gw.upgrades.keys().filter(func(k): return k.begins_with("team1.story") and ("heat" in k or "suit" in k)),
		"bought": gw.boughtUpgrades.filter(func(k): return "storyheat" in k or "suitblaster" in k),
		"limits": gw.upgradeLimits.filter(func(l): return "storykeeper" in l),
	}
