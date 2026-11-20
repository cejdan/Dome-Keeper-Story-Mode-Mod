extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 147: Metal Bit for the Mine Driller and Drillbert. Without it, metal
# stops both (as before). With it, their drills cut metal. The keeper's own
# drill still can't (t20_metal covers that).

const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")

const TIMEOUT := 420


func boot() -> Dictionary:
	return {"seed": 12345}


func _find(h, pred: Callable):
	for n in h.get_tree().root.find_children("*", "", true, false):
		if pred.call(n):
			return n
	return null


func _metal_left(cells: Array) -> int:
	var n: int = 0
	for c: Vector2i in cells:
		var t = Level.map.getTile(Vector2(c))
		if t != null and Metal.is_metal(t.type):
			n += 1
	return n


func run(h) -> void:
	h.disable_waves()
	var td = Level.map.tileData
	h.set_inv("money", 5000)
	var shop_ids: Array = GameWorld.upgrades.keys().filter(func(k): return "metal" in k)
	h.note("metal upgrades in the shop", shop_ids)

	# ---- Mine Driller: three metal tiles under its drill head.
	GameWorld.serverAddUpgrade("drill", "team1")
	await h.wait(3.0)
	var toucher = _find(h, func(n): return n.name == "TileToucher" and n.get_parent().has_method("onSpawnSidedrill"))
	h.check("the Mine Driller is installed", toucher != null)
	h.check("Metal Bit for the driller is in the shop", GameWorld.upgrades.has("team1." + Metal.DRILL_UPGRADE), shop_ids)
	if toucher == null:
		return
	var head: Vector2i = Level.map.getTileCoord(toucher.global_position)
	var shaft: Array = []
	for dy in range(2, 5):
		var c := Vector2i(head.x, head.y + dy)
		td.set_resourcev(c, Metal.TILE_ID)
		shaft.append(c)
	await h.reveal(shaft)
	await h.teleport_tile(Vector2i(head.x + 2, head.y + 1))
	h.note("driller", {"head": head, "metal": shaft})
	h.speed(4.0)
	await h.wait(60.0)
	h.speed(1.0)
	await h.shot("driller_blocked")
	h.check("without Metal Bit the driller stops at metal (%d of 3 left)" % _metal_left(shaft), _metal_left(shaft) == 3, Level.map.getTileCoord(toucher.global_position))
	var ok: bool = await h.buy(Metal.DRILL_UPGRADE)
	h.check("Metal Bit (driller) bought for $600", ok and h.inv("money") == 4400, h.inv("money"))
	h.speed(4.0)
	await h.until(func(): return _metal_left(shaft) == 0, 120.0)
	h.speed(1.0)
	await h.shot("driller_through")
	h.check("with Metal Bit the driller cuts through all three", _metal_left(shaft) == 0, {"left": _metal_left(shaft), "head": Level.map.getTileCoord(toucher.global_position)})

	# ---- Drillbert: a corridor ending in a 2-tall metal wall.
	GameWorld.serverAddUpgrade("drillbot", "team1")
	await h.wait(3.0)
	# Drillbert leaves his station when a keeper takes him; spawn him the way
	# the station does (DrillbotStation.gd), without a carrier.
	var station = _find(h, func(n): return n.has_method("addDrillbot") and "drillbots" in n)
	var bot = null
	if station != null:
		bot = Level.drops.network_spawn({"type": CONST.DRILLBOT, "team": "team1", "position": Level.map.getTilePos(Vector2i(13, 14))})
		station.drillbots.network_track_drillbot(bot)
		await h.wait(0.5)
	h.check("Drillbert is out, running the extended script", bot != null and bot.get_script().get_script_constant_map().has("Metal"), bot.get_script().get_script_constant_map().keys() if bot else null)
	h.check("Metal Bit for Drillbert is in the shop", GameWorld.upgrades.has("team1." + Metal.DRILLBOT_UPGRADE))
	if bot == null:
		return
	var y: int = 14
	var x0: int = 10
	var wall: Array = [Vector2i(x0 + 6, y - 1), Vector2i(x0 + 6, y)]
	for x in range(x0 - 1, x0 + 9):
		for yy in range(y - 2, y + 2):
			td.set_resourcev(Vector2i(x, yy), Data.TILE_DIRT_START)
	for c: Vector2i in wall:
		td.set_resourcev(c, Metal.TILE_ID)
	await h.dig_room(Vector2i(x0, y - 1), Vector2i(x0 + 5, y))
	var around: Array = []
	for x in range(x0 - 1, x0 + 9):
		for yy in range(y - 2, y + 2):
			around.append(Vector2i(x, yy))
	await h.reveal(around)
	await h.teleport_tile(Vector2i(x0 + 1, y))
	await _place_bot(h, bot, Vector2i(x0 + 3, y))
	await h.wait(1.0)
	await h.shot("drillbert_placed")
	h.speed(3.0)
	await h.wait(25.0)
	h.speed(1.0)
	await h.shot("drillbert_blocked")
	h.note("drillbert", {"state": bot.state, "pos": Level.map.getTileCoord(bot.global_position), "metal left": _metal_left(wall)})
	h.check("without Metal Bit Drillbert doesn't get through metal", _metal_left(wall) == 2, _metal_left(wall))
	ok = await h.buy(Metal.DRILLBOT_UPGRADE)
	h.check("Metal Bit (Drillbert) bought", ok)
	await _place_bot(h, bot, Vector2i(x0 + 3, y))
	h.speed(3.0)
	await h.until(func(): return _metal_left(wall) < 2, 60.0)
	h.speed(1.0)
	await h.shot("drillbert_through")
	h.check("with Metal Bit Drillbert breaks the metal", _metal_left(wall) < 2, {"left": _metal_left(wall), "state": bot.state, "pos": Level.map.getTileCoord(bot.global_position)})
	# The two Metal Bit panels in the shop.
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	for i in 8:
		for j in 2:
			await h.press("ui_down")
			await h.wait(0.2)
		await h.shot("shop_%d" % i)
	await h.press("ui_cancel")
	h.snap("end", [])


# Drillbert on the corridor floor at `c`, facing right, awake and working.
func _place_bot(h, bot, c: Vector2i) -> void:
	bot.global_position = Level.map.getTilePos(c)
	bot.linear_velocity = Vector2.ZERO
	bot.normalMode()
	bot.localSetDirection(Vector2.RIGHT)
	bot.direction = Vector2.RIGHT
	bot.startWorking()
	bot.remainingHits = 400
	await h.frames(5)
