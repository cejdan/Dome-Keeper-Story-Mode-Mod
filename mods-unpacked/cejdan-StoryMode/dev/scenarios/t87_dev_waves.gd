extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 87: a hand-played Story Mode dev run gets monster waves (vanilla dev
# mode switches them off). `waves: true` stands in for "no scenario running".
# Run with -Extra "--nowaves" to check the switch keeps them off.


func boot() -> Dictionary:
	return {"seed": 12345, "waves": true}


func run(h) -> void:
	var off: bool = "--nowaves" in OS.get_cmdline_user_args()
	await h.until(func(): return Level.stage.keeperInputStarted, 60.0)
	await h.wait(1.0)
	var mm = Level.monstersByTeamId["team1"]
	h.note("start", {"devMode": GameWorld.devMode, "disabled": mm.disabled, "cooldown": Data.of("team1.monsters.waveCooldown")})
	if off:
		h.check("--nowaves keeps waves off", mm.disabled)
		return
	h.check("waves enabled in dev run", not mm.disabled)
	Data.apply("team1.dome.maxHealth", 1000000)
	Data.apply("team1.dome.health", 1000000)
	# Vanilla starts the wave clock after 8 dug tiles; dig them like a player.
	var dug := 0
	var k: Vector2i = Level.map.getTileCoord(h.keeper().global_position)
	for y in range(k.y, k.y + 30):
		for x in range(k.x - 3, k.x + 4):
			var t = Level.map.getTile(Vector2(x, y))
			if t != null and is_instance_valid(t) and dug < 10:
				Level.map.destroyTile("team1", "keeper1", t)
				dug += 1
	await h.wait(1.0)
	h.note("dug", {"tiles": dug, "tilesdestroyed": Data.ofOr("map.tilesdestroyed", 0), "runStarted": GameWorld.runStarted})
	h.check("wave clock started by digging", GameWorld.runStarted)
	var c0: float = Data.of("team1.monsters.waveCooldown")
	await h.wait(3.0)
	var c1: float = Data.of("team1.monsters.waveCooldown")
	h.check("wave countdown runs", c1 < c0, {"before": c0, "after": c1})
	# Skip most of the wait, then let the vanilla countdown bring the wave.
	Data.apply("team1.monsters.waveCooldown", 3)
	var came: bool = await h.until(func(): return Data.of("team1.monsters.wavepresent"), 30.0)
	h.check("a wave arrives", came)
	await h.wait(6.0)
	var monsters: int = h.get_tree().get_nodes_in_group("team1-monster").size()
	await h.shot("wave")
	h.check("monsters spawned", monsters > 0, monsters)
