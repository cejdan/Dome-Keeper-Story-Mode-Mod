extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 49: clumps of metal scattered through B6-B8. 50-seed report of the
# metal share of rock per biome and clump sizes; then a look at it in the
# running game, a drill test and a blast. The lava ocean's rows (#43: its rock
# ceiling, floor and chamber walls, all biome B8) are built after the metal, so
# shares are measured above the ocean's ceiling (#117).

const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")
const MapConfig = preload("res://mods-unpacked/cejdan-StoryMode/data/map_config.gd")
const T21 = preload("res://mods-unpacked/cejdan-StoryMode/dev/scenarios/t21_gate.gd")

const SEEDS: int = 50
const TOLERANCE: float = 0.75  # percentage points


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	var B: int = MapConfig.BIOMES
	var metal: Array = []
	var rock: Array = []
	for b in B:
		metal.append(0)
		rock.append(0)
	var sizes: Dictionary = {}
	var near_special: int = 0
	var failed: int = 0
	for s in SEEDS:
		var td = h.generate_map(MapConfig.make_archetype(), 1000 + s)
		if td == null:
			failed += 1
			continue
		var ceiling: int = int(td.get_meta("story_ocean", {}).get("ceiling", 1 << 20))
		for c: Vector2i in td.get_used_biome_cells():
			if c.y >= ceiling:
				continue
			var b: int = clampi(td.get_biomev(c), 0, B - 1)
			var r: int = td.get_resourcev(c)
			if r == Metal.TILE_ID:
				metal[b] += 1
				for ox in range(-1, 2):
					for oy in range(-1, 2):
						var r2: int = td.get_resourcev(c + Vector2i(ox, oy))
						if (r2 >= Data.TILE_GADGET and r2 <= Data.TILE_CAVE) or r2 == Data.TILE_DIRT_MARK_BLOCKED_FOR_CHAMBER:
							near_special += 1
			elif r == Data.TILE_DIRT_START:
				rock[b] += 1
		for g: Array in h.deposits_of(td, Metal.TILE_ID):
			sizes[g.size()] = sizes.get(g.size(), 0) + 1
		if s == 0:
			h.map_png("metal_seed1000", T21.new()._colors(), 6, td)
		td.queue_free()
		await h.frames(1)
	h.check("all %d seeds generated" % SEEDS, failed == 0, failed)
	for b in B:
		var share: float = 100.0 * metal[b] / maxf(1.0, float(metal[b] + rock[b]))
		var want: float = 100.0 * float(MapConfig.METAL_SHARE.get(b, 0.0))
		h.check("B%d metal is %.1f%% of rock (want %.0f%%)" % [b + 1, share, want], absf(share - want) <= TOLERANCE if want > 0 else metal[b] == 0, {"metal": metal[b], "rock": rock[b]})
	var bad_size: int = 0
	for n: int in sizes:
		if n < int(MapConfig.METAL_CLUMP[0]) or n > int(MapConfig.METAL_CLUMP[1]):
			bad_size += sizes[n]
	h.check("clumps are 2-5 tiles", bad_size == 0, sizes)
	h.check("no metal next to chamber, relic or cave tiles", near_special == 0, near_special)

	# ---- in the running game: a look at B7
	var td2 = Level.map.tileData
	var pick: Vector2i = Vector2i(9999, 9999)
	for c: Vector2i in td2.get_resource_cells_by_id(Metal.TILE_ID):
		if td2.get_biomev(c) == 6 and absi(c.x) < 20 and td2.get_resourcev(c + Vector2i(0, -1)) == Data.TILE_DIRT_START:
			pick = c
			break
	h.check("the run's B7 has metal", pick.x != 9999, pick)
	var area: Array = []
	for y in range(pick.y - 8, pick.y + 9):
		for x in range(pick.x - 14, pick.x + 15):
			area.append(Vector2i(x, y))
	await h.reveal(area)
	await h.dig_room(pick + Vector2i(-1, -2), pick + Vector2i(1, -1))
	await h.teleport_tile(pick + Vector2i(0, -1))
	await h.wait(8.0)
	await h.shot("b7_metal")
	await h.hold("ui_down", 6.0)
	h.check("drilling a scattered metal tile leaves it", td2.get_resourcev(pick) == Metal.TILE_ID)
	GameWorld.serverAddUpgrade("player1.suitblaster", "team1")
	await h.wait(1.0)
	Data.apply("player1.suitblaster.charge", 1.0)
	await h.teleport_tile(pick + Vector2i(0, -1))
	await h.wait(1.0)
	await h.press("keeper_gadget1")
	await h.burst("blast", 10, 3)
	await h.wait(1.5)
	h.check("a Suit Blaster blast breaks it", td2.get_resourcev(pick) == Data.TILE_EMPTY, td2.get_resourcev(pick))
	await h.shot("after_blast")
