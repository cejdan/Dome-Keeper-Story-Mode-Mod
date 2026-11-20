extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #232 (2/2), client half: joins the host that loaded the online save, takes a
# saved keeper in the keeper choice (dev/harness.gd), and sees the same lava,
# gas, money, beats played, translator stage and heat shield tier as the host.
# Pair: t232_mp_load_host.

const TIMEOUT := 300


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var live = await shared(h, "live", 90.0)
	h.check("the host shared the loaded run", live is Dictionary)
	if not live is Dictionary:
		return
	await h.wait(3.0)    # the lava snapshot and the #242 resend have landed
	live = await shared(h, "live")
	var rooms: Dictionary = live["rooms"]
	var mine := facts(rooms)
	h.note("client facts", mine)
	check_facts(h, mine, live, "loaded run")
	h.check("loaded run: the beats played are the host's", str(Data.ofOr("team1.story.beatsplayed", "")) == live["saved"]["beatsplayed"])
	h.check("loaded run: the map facts reached this client", mine["map meta"] == true)
	# #265: this keeper's own shop entries came with the loaded run, bought up
	# to its tier (the tree each player sees is built from them).
	var pid: String = h.keeper().playerId
	var tier: int = int(Data.ofOr(pid + ".suit.heatshield", 0))
	var entries: Array = range(1, 5).map(func(n): return [GameWorld.upgrades.has("%s.storyheatshield%d" % [pid, n]), GameWorld.boughtUpgrades.has("%s.storyheatshield%d" % [pid, n])])
	h.check("loaded run: this keeper's Heat Shielding entries are here, bought up to its tier %d" % tier,
		range(4).all(func(i): return entries[i][0] and entries[i][1] == (i < tier)) and GameWorld.isUpgradeLimitAvailable(pid + ".storykeeper"), entries)
	await look_at_rooms(h, rooms)
	await h.wait(1.0)
	await h.shot("client_loaded")
