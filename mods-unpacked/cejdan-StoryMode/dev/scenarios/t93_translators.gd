extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 93: three translator chambers in B2, B4 and B6. A 20-seed map check
# finds exactly one per biome, clear of the gate, open to the surface. In the
# running game the keeper opens each chamber, carries the translator home, and
# installing it raises the plea translation stage and plays the horror's beat.
# Ends by saving to slot 12 for t93_reload.

const MapConfig = preload("res://mods-unpacked/cejdan-StoryMode/data/map_config.gd")
const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")
const Runes = preload("res://mods-unpacked/cejdan-StoryMode/pleas/runes.gd")
const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")

const LINE := "Every hole you make, it *breathes*."


func boot() -> Dictionary:
	return {"seed": 12345, "beats": true}


# Open (not border) path from the chamber up to the map's top rows, crossing
# rock, ore and blastable metal: anything but the border.
func _reaches_top(td, at: Vector2i) -> bool:
	var top: int = 1 << 20
	for c: Vector2i in td.get_used_biome_cells():
		top = mini(top, c.y)
	var seen: Dictionary = {at: true}
	var open: Array = [at]
	while open.size() > 0:
		var c: Vector2i = open.pop_back()
		if c.y <= top + 1:
			return true
		for d: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
			var n: Vector2i = c + d
			if seen.has(n) or td.get_biomev(n) < 0 or td.get_resourcev(n) == Data.TILE_BORDER:
				continue
			seen[n] = true
			open.append(n)
	return false


func _chamber_report(h) -> void:
	var bad: Array = []
	for s in 20:
		var td = h.generate_map(MapConfig.make_archetype(), 2000 + s)
		if td == null:
			bad.append([2000 + s, "no map"])
			continue
		var placed: Array = td.get_meta("story_translators", [])
		var biomes: Array = placed.map(func(p): return int(p[2]))
		biomes.sort()
		if biomes != [1, 3, 5]:
			bad.append([2000 + s, "biomes", biomes])
		var gadget: int = td.get_resource_cells_by_id(Data.TILE_GADGET).size()
		if gadget != 12:
			bad.append([2000 + s, "gadget tiles", gadget])
		for p in placed:
			var at: Vector2i = Vector2i(int(p[0]), int(p[1]))
			for oy in range(-1, 3):
				for ox in range(-1, 3):
					var r: int = td.get_resourcev(at + Vector2i(ox, oy))
					if r == Metal.GATE_ID or r == Data.TILE_BORDER or r == Metal.TILE_ID:
						bad.append([2000 + s, "touches", p, r])
			if not _reaches_top(td, at):
				bad.append([2000 + s, "unreachable", p])
		td.queue_free()
		await h.frames(1)
	h.check("20 seeds: exactly one translator chamber in each of B2, B4, B6, clear of gate/metal/border and open to the surface", bad.is_empty(), bad)


func _chambers() -> Array:
	var out: Array = []
	for c in Level.map.find_children("*", "", true, false):
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("TranslatorChamber.gd"):
			out.append(c)
	out.sort_custom(func(a, b): return a.global_position.y < b.global_position.y)
	return out


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	await _chamber_report(h)
	var chambers: Array = _chambers()
	h.check("the run has 3 translator chambers", chambers.size() == 3, chambers.size())
	var pd = load("res://mods-unpacked/cejdan-StoryMode/pleas/plea_director.gd").instance()
	var td = Level.map.tileData
	# Only the translators' beats may play here: mark the depth and event beats
	# played, so diving to the chambers (and the deep heat) plays nothing else.
	Data.apply("team1.story.beatsplayed", "biome_b2,biome_b3,biome_b4,biome_b5,biome_b6,biome_b7,biome_b8,lava_ocean,first_gem,gate_broken,lava_death")
	# Depth heat would recall the keeper (and drop the translator) in B6: buy
	# Heat Shielding IV, which shuts it out.
	h.set_inv("money", 10000000)
	for n in range(1, 5):
		await h.buy("storyheatshield%d" % n)
	h.set_inv("money", 0)
	for i in chambers.size():
		var ch = chambers[i]
		var at: Vector2i = Level.map.getTileCoord(ch.global_position + Vector2(12, 12))
		h.note("chamber %d" % (i + 1), {"tile": at, "biome": td.get_biomev(at)})
		await h.dig_room(at + Vector2i(-3, -3), at + Vector2i(4, -1))
		await h.reveal([at, at + Vector2i(1, 0), at + Vector2i(0, 1), at + Vector2i(1, 1)])
		await h.teleport_tile(at + Vector2i(0, -1))
		await h.wait(0.8)
		await h.shot("chamber%d_found" % (i + 1))
		for c: Vector2i in [at, at + Vector2i(1, 0), at + Vector2i(0, 1), at + Vector2i(1, 1)]:
			var t = Level.map.getTile(Vector2(c))
			if t != null:
				Level.map.destroyTile("team1", "", t)
		await h.until(func(): return ch.currentState == ch.State.OPEN, 8.0)
		await h.teleport_tile(at + Vector2i(1, 1))
		await h.wait(1.0)
		await h.shot("chamber%d_open" % (i + 1))
		h.check("chamber %d opens" % (i + 1), ch.currentState == ch.State.OPEN, ch.currentState)
		ch.registerHit("player1")
		await h.wait(0.8)
		var carried: Array = h.keeper().carriedCarryables.filter(func(c): return is_instance_valid(c) and c.type == "translator")
		h.check("chamber %d: the keeper carries a translator" % (i + 1), carried.size() == 1, h.keeper().carriedCarryables.size())
		await h.shot("chamber%d_carry" % (i + 1))
		# Home: into the dome, by the relic socket.
		var n0: int = int(h.inv("translator"))
		var dome = Level.getDome("team1")
		h.keeper().teleport(dome.global_position + Vector2(0, -20))
		h.snap_camera()
		var got: bool = await h.until(func(): return int(h.inv("translator")) > n0, 12.0)
		if not got:
			for c in carried:
				if is_instance_valid(c):
					c.global_position = dome.getDropTarget("relic").global_position
			got = await h.until(func(): return int(h.inv("translator")) > n0, 8.0)
		h.check("translator %d installed at the dome" % (i + 1), got, h.inv("translator"))
		var id: String = await h.read_beat("translator%d_beat" % (i + 1), 8.0)
		h.check("the horror's translator_%d beat plays" % (i + 1), id == "translator_%d" % (i + 1), id)
		h.check("translation stage is %d" % (i + 1), Runes.stage() == i + 1, Runes.stage())
		pd.say("arrive", null, LINE, 6.0)
		await h.wait(1.2)
		await h.shot("plea_at_stage%d" % (i + 1))
	h.check("chambers are spent", chambers.all(func(c): return c.currentState == c.State.EMPTY))
	await SaveGame.saveGame("singleplayer", 12, true)
	await h.wait(1.0)
	h.note("saved slot 12", {"stage": Runes.stage(), "translators": h.inv("translator")})
