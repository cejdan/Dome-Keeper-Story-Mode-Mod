extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 54: Retire Rich, the $1,000,000 shop item that wins the run. No relic
# on this run's map; the many-seed check is t54_no_relics.


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	# The 50-seed no-relic sweep is t54_no_relics (#120); the doom ending (#96)
	# left room here for only 25 seeds inside the 300 s timeout.
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
	# The doom ending (#96) plays before the run is won; with beats muted it is
	# the last words and the narration cards, about 30 s.
	await h.until(func(): return GameWorld.won, 60.0)
	h.check("the run is won", GameWorld.won and Data.ofOr("game.over", "") == "won", {"won": GameWorld.won, "game.over": Data.ofOr("game.over", "")})
	await h.wait(8.0)
	await h.shot("victory")
	h.check("no final wave", not Data.ofOr("team1.monsters.wavepresent", false))
