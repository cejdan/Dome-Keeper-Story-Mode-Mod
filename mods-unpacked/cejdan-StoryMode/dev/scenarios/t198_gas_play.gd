extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Map 198, played: a pocket the map generated, opened the way a player opens
# one. A shaft runs from the surface down beside the shallowest gas pocket;
# the keeper stands in a side tunnel and drills into the green cracks with its
# own drill. The pocket bursts, the gas takes the tunnel and climbs the shaft
# to the surface. (What a full bar does is t202_toxin's.)

const Finder = preload("res://mods-unpacked/cejdan-StoryMode/gas/dev_gas_finder.gd")
const TIMEOUT := 300


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	await h.until(func(): return Level.map.get_node_or_null("StoryGasField") != null, 10.0)
	var field = Level.map.get_node("StoryGasField")
	var map = Level.map
	var all: Array = Finder.pockets(field.rock)
	h.check("the map has gas pockets", all.size() > 5, all.size())
	var pocket: Array = []
	var cells: Array = []
	for p in all:
		cells = Finder.tunnel_beside(map, p)
		if not cells.is_empty():
			pocket = p
			break
	h.check("a pocket with room beside it", not cells.is_empty(), pocket)
	h.note("pocket", {"cells": pocket, "tunnel": cells, "biome": map.tileData.get_biomev(pocket[0])})

	# The tunnel beside the pocket, and a shaft from its far end up to the surface.
	var dig: Array = cells.duplicate()
	var far: Vector2i = cells[2]
	for y in range(1, far.y):
		dig.append(Vector2i(far.x, y))
	# Row 1 runs on to the dome's own entrance and up it, the way a player's
	# mine joins the dome: under the dome's floor there is no sky.
	var mouth := 0
	for x in range(mini(0, far.x), maxi(0, far.x) + 1):
		dig.append(Vector2i(x, 1))
	dig.append(Vector2i(0, 0))
	var free: Array = []
	for c in dig:
		if not map.is_tile_empty(c) and not free.has(c):
			free.append(c)
	await h.reveal(dig + pocket)
	await h.clear_tiles(free)
	h.check("the mine reaches open sky", field._is_sky(Vector2i(mouth, -1)), mouth)
	await h.teleport_tile(cells[1])
	await h.wait(3.0)
	h.snap_camera()
	await h.shot("before")
	h.check("nothing breached yet", field.breaches == 0 and field.toxin == 0.0, field.stats())
	var base: float = field.total() + field.vented + field.faded

	# Drill into the pocket with the keeper's own drill.
	var key: String = "ui_left" if cells[0].x < cells[1].x else "ui_right"
	h.down(key)
	var breached: bool = await h.until(func(): return field.breaches > 0, 60.0)
	h.up(key)
	h.check("the keeper's drill opened the pocket", breached, field.stats())
	await h.burst("burst", 30, 5)
	h.check("the whole pocket burst", field.rock.keys().filter(func(c): return pocket.has(c)).is_empty(), field.breaches)
	# The keeper stays put. A small, shallow pocket's gas rushes past and on up
	# the shaft: the bar jumps, then clears.
	var peak := 0.0
	for i in 40:
		peak = maxf(peak, field.toxin)
		await h.wait(0.1)
	h.check("the keeper breathed it", peak > 20.0, peak)
	h.note("toxin", {"peak": peak, "now": field.toxin, "gassed": field.gassed})
	await h.shot("gas_gone_past")

	# Meanwhile the gas climbs the shaft and leaves at the surface.
	await h.teleport_tile(Vector2i(2 if far.x > 0 else -2, 1))
	h.keeper().set("gravity_scale", 0.0)
	field.freeze_toxin = true
	await h.burst("shaft_mouth", 16, 8)
	var out: bool = await h.until(func(): return field.vented > 1.0, 40.0)
	h.check("gas left the mine through the shaft", out, field.stats())
	await h.until(func(): return field.stats()["awake"] == 0, 60.0)
	var st: Dictionary = field.stats()
	h.note("the end", st)
	h.check("all of the gas is accounted for (the pocket's, and any cavern the shaft cut)", absf(float(st["total"]) + float(st["vented"]) + float(st["faded"]) - base - 3.0 * pocket.size()) < 0.05, st)
	await h.teleport_tile(cells[1])
	await h.wait(1.0)
	await h.shot("after")
