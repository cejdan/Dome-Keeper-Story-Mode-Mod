extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 54: Retire Rich, the $1,000,000 shop item that wins the run; no relic
# on Story Mode maps.

const MapConfig = preload("res://mods-unpacked/cejdan-StoryMode/data/map_config.gd")
const T21 = preload("res://mods-unpacked/cejdan-StoryMode/dev/scenarios/t21_gate.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	var relics: int = 0
	for s in 50:
		var td = h.generate_map(MapConfig.make_archetype(), 3000 + s)
		if td != null:
			relics += td.get_resource_cells_by_id(Data.TILE_RELIC).size() + td.get_resource_cells_by_id(Data.TILE_RELIC_SWITCH).size()
			if s < 3:
				var c: Dictionary = T21.new()._colors()
				c[Data.TILE_RELIC] = Color("#ff00ff")
				c[Data.TILE_RELIC_SWITCH] = Color("#ff00ff")
				h.map_png("no_relic_seed%d" % (3000 + s), c, 4, td)
			td.queue_free()
		await h.frames(1)
	h.check("50 seeds: zero relic or relic switch tiles", relics == 0, relics)
	h.check("this run's map: no relic", Level.map.tileData.get_resource_cells_by_id(Data.TILE_RELIC).is_empty())

	var entry: Dictionary = GameWorld.upgrades.get("team1.storyretirerich", {})
	h.check("Retire Rich is in the shop at $1,000,000", entry.get("cost", {}) == {"money": 1000000}, entry.get("cost", {}))
	h.set_inv("money", 999999)
	var refused: bool = not (await h.buy("storyretirerich"))
	h.check("with $999,999 it can't be bought", refused and not GameWorld.won, h.inv("money"))
	h.set_inv("money", 1000000)
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	for i in 14:
		await h.press("ui_down")
		await h.wait(0.2)
	await h.shot("shop_retire_rich")
	# Buy it the way the shop's Buy button does.
	var ok: bool = await h.buy("storyretirerich")
	h.check("bought with $1,000,000", ok and h.inv("money") == 0, h.inv("money"))
	await h.until(func(): return GameWorld.won, 5.0)
	h.check("the run is won", GameWorld.won and Data.ofOr("game.over", "") == "won", {"won": GameWorld.won, "game.over": Data.ofOr("game.over", "")})
	await h.wait(8.0)
	await h.shot("victory")
	h.check("no final wave", not Data.ofOr("team1.monsters.wavepresent", false))
