extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 54: vanilla Relic Hunt still has its relic and wins by delivering it.


func boot() -> Dictionary:
	return {"seed": 12345, "mode": "relichunt"}


func run(h) -> void:
	h.disable_waves()
	var cells: Array = Level.map.tileData.get_resource_cells_by_id(Data.TILE_RELIC)
	h.check("the Relic Hunt map has a relic", cells.size() > 0, cells.size())
	Data.apply("team1.dome.maxHealth", 1000000)
	Data.apply("team1.dome.health", 1000000)
	GameWorld.runStarted = true
	await h.deliver("relic", 1)
	await h.wait(5.0)
	h.snap("relic delivered", ["team1.inventory.relic"])
	# The final act: clear its waves (no one at the laser) until the run is won.
	h.speed(3.0)
	var t0: float = h.now()
	while not GameWorld.won and h.now() - t0 < 240.0:
		for mm in h.get_tree().get_nodes_in_group("monster-manager"):
			if Data.of("team1.monsters.wavepresent"):
				mm.instantlyKillWave()
		await h.wait(2.0)
	h.speed(1.0)
	h.check("delivering the relic wins Relic Hunt", GameWorld.won, Data.ofOr("game.over", ""))
	await h.wait(8.0)
	await h.shot("relichunt_won")
