extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t347_meter.gd"

# Ticket 347: does the lava ocean's simulation wake up, and what does it cost?
# On a Huge map (the ocean about 6,500 cells), a shaft is opened down to the
# ocean, then a big magma pocket over the shaft is broken so lava pours down
# into the ocean for a while; then the run's lava is saved and restored (what
# loading a save does). Each step logs the lava field's own tick, how many
# cells are awake, and the frame meter.
#
#   --mapsize=<id>   map size (default regular-huge)

const TIMEOUT := 300


func boot() -> Dictionary:
	return {"seed": 12345, "mapsize": _Story_arg("mapsize", "regular-huge")}


func _awake_watch(h, label: String, sec: float) -> Dictionary:
	var p0: int = _lava.phys_us
	var f0: int = _lava.phys_frames
	var most := 0
	var t := 0.0
	step = label
	while t < sec:
		await h.wait(0.25)
		t += 0.25
		most = maxi(most, _lava._awake.size())
	step = ""
	var r := {"lava tick ms": snappedf(float(_lava.phys_us - p0) / maxi(1, _lava.phys_frames - f0) / 1000.0, 0.001),
		"most awake": most, "awake now": _lava._awake.size(), "lava cells": _lava.mass.size()}
	h.note(label, r)
	ModLoaderLog.info("t347 wake [%s]: %s" % [label, JSON.stringify(r)], "flantor-StoryMode")
	return r


func run(h) -> void:
	h.disable_waves()
	var map = Level.map
	var td = map.tileData
	var o: Dictionary = td.get_meta("story_ocean", {})
	var ceiling: int = int(o["ceiling"])
	meter_start(h)
	await h.wait(1.0)
	h.note("ocean", {"cells": _lava.ocean_cells, "lava cells": _lava.mass.size()})
	await _awake_watch(h, "settled, at the surface", 4.0)
	var x := 4
	for y in range(ceiling - 14, ceiling + 1):
		for dx in range(-2, 3):
			var c := Vector2i(x + dx, y)
			td.set_resourcev(c, Data.TILE_DIRT_START)
			if td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE or td.get_hardnessv(c) < 0:
				td.set_hardnessv(c, Data.HARDNESS_MEDIUM)
	await h.dig_room(Vector2i(x, ceiling - 12), Vector2i(x, ceiling))
	await h.teleport_tile(Vector2i(x, ceiling - 4))
	await _awake_watch(h, "ocean opened", 4.0)
	# A big pocket over the shaft, broken: lava pours down into the ocean.
	var pocket: Array = []
	for dx in range(-1, 2):
		for y in range(ceiling - 14, ceiling - 12):
			pocket.append(Vector2i(x + dx, y))
	_lava.add_pocket(pocket)
	await h.dig_room(Vector2i(x, ceiling - 13), Vector2i(x, ceiling - 13))
	await _awake_watch(h, "lava pouring into the ocean", 12.0)
	await h.shot("pouring")
	await _awake_watch(h, "after the pour", 12.0)
	# What loading a save does to the lava.
	_lava.serialize()
	var blob: String = str(Data.ofOr(_lava.SAVE_KEY, ""))
	var ok: bool = _lava._restore(blob)
	h.note("restored", {"ok": ok, "blob chars": blob.length()})
	await _awake_watch(h, "after a restore", 12.0)
	await _awake_watch(h, "after a restore, later", 12.0)
	meter_stop()
	report(h)
