extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 26: story beats fire from the game. The keeper visits B2..B8 and the
# lava ocean (each beat captured with its tier), mines a gem, blasts the gate
# (the beat opens mid-blast; the blast and the blaster's recharge carry on after)
# and overheats. Nothing fires twice.

const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const BeatData = preload("res://mods-unpacked/cejdan-StoryMode/data/beats.gd")
const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")
const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")


func boot() -> Dictionary:
	return {"seed": 12345, "beats": true}


# A cell of biome `b` near the map's middle column, mid-band, above the lava
# ocean (whose rows carry B8's biome index).
func _cell_in_biome(td, b: int) -> Vector2i:
	var ceiling: int = int(td.get_meta("story_ocean", {}).get("ceiling", 1 << 20))
	var cells: Array = []
	for c: Vector2i in td.get_used_biome_cells():
		if td.get_biomev(c) == b and absi(c.x) <= 6 and c.y < ceiling - 1:
			cells.append(c)
	cells.sort_custom(func(a, c): return a.y < c.y)
	return cells[cells.size() / 2] if cells.size() > 0 else Vector2i(9999, 9999)


func _expect(h, id: String, label: String) -> void:
	var got: String = await h.read_beat(label)
	var tier: int = int(BeatData.by_id(id).get("tier", 0))
	h.check("%s plays (tier %d)" % [id, tier], got == id, got)


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	var td = Level.map.tileData
	var field = Level.map.get_node_or_null("StoryLavaField")

	# ---- each biome, B2 to B8
	for b in range(1, 8):
		var c: Vector2i = _cell_in_biome(td, b)
		await h.dig_room(c + Vector2i(-2, -2), c + Vector2i(2, 0))
		await h.teleport_tile(c)
		h.check("keeper is in B%d" % (b + 1), td.get_biomev(h.keeper_tile()) == b, [h.keeper_tile(), td.get_biomev(h.keeper_tile())])
		await _expect(h, "biome_b%d" % (b + 1), "b%d" % (b + 1))
		if field != null:
			field.heat = 0.0
	h.check("deepest reached is B8", StoryBeats.deepest() == 7, StoryBeats.deepest())

	# ---- the lava ocean
	var ocean: Dictionary = td.get_meta("story_ocean", {})
	h.check("the map has an ocean", not ocean.is_empty(), ocean)
	var oc: Vector2i = Vector2i(0, int(ocean.get("top", 0)) - 1)
	await h.dig_room(oc + Vector2i(-2, -2), oc)
	await h.teleport_tile(oc)
	await _expect(h, "lava_ocean", "ocean")
	h.check("deepest reached is the ocean", StoryBeats.deepest() == 8, StoryBeats.deepest())
	if field != null:
		field.heat = 0.0

	# ---- back up: no biome beat plays twice
	var b2: Vector2i = _cell_in_biome(td, 1)
	await h.teleport_tile(b2)
	await h.wait(1.5)
	h.check("re-entering B2 plays nothing", not StoryBeats.is_open())

	# ---- first gem: mine a real gem tile
	var gem: Vector2i = Vector2i(9999, 0)
	for id: int in [42, 43, 44, 46]:
		for c: Vector2i in td.get_resource_cells_by_id(id):
			if absi(c.x) < 30 and c.y < 120 and (gem.x == 9999 or c.y < gem.y):
				gem = c
	h.note("gem", {"cell": gem, "type": Minerals.by_tile_id(td.get_resourcev(gem))})
	await h.dig_room(gem + Vector2i(-2, -3), gem + Vector2i(2, -1))
	await h.reveal([gem])
	await h.teleport_tile(gem + Vector2i(0, -1))
	Level.map.destroyTile("team1", "", Level.map.getTile(Vector2(gem)))
	await _expect(h, "first_gem", "first_gem")
	# A second gem plays nothing.
	var gem2: Vector2i = Vector2i(9999, 0)
	for c: Vector2i in td.get_resource_cells_by_id(td.get_resourcev(gem) if td.get_resourcev(gem) >= 0 else 42):
		if c != gem and absi(c.x) < 30:
			gem2 = c
			break
	if gem2.x != 9999:
		await h.reveal([gem2])
		Level.map.destroyTile("team1", "", Level.map.getTile(Vector2(gem2)))
		await h.wait(1.5)
		h.check("a second gem plays nothing", not StoryBeats.is_open())

	# ---- the gate, broken by a real Suit Blaster blast
	var gate: Array = td.get_resource_cells_by_id(Metal.GATE_ID)
	var x: int = 2
	var top: int = 1 << 20
	for c: Vector2i in gate:
		if c.x == x and c.y < top:
			top = c.y
	await h.dig_room(Vector2i(x - 3, top - 4), Vector2i(x + 3, top - 1))
	await h.teleport_tile(Vector2i(x, top - 1))
	GameWorld.serverAddUpgrade("player1.suitblaster", "team1")
	await h.wait(1.0)
	Data.apply("player1.suitblaster.charge", 1.0)
	await h.wait(1.0)
	await h.press("keeper_gadget1")
	var opened: bool = await h.until(func(): return StoryBeats.is_open(), 6.0)
	h.check("gate_broken opens while the blast is going", opened and StoryBeats.instance().open_id == "gate_broken")
	var charge_open: float = float(Data.ofOr("player1.suitblaster.charge", -1))
	await h.wait(2.0)
	h.check("the blaster's charge holds while the beat is up", is_equal_approx(float(Data.ofOr("player1.suitblaster.charge", -1)), charge_open), [charge_open, Data.ofOr("player1.suitblaster.charge", -1)])
	await _expect(h, "gate_broken", "gate_broken")
	await h.wait(3.0)
	var left: int = 0
	for c: Vector2i in gate:
		if c.x == x and td.get_resourcev(c) == Metal.GATE_ID:
			left += 1
	h.check("the blast still clears the gate column after the beat", left == 0, left)
	var charge_a: float = float(Data.ofOr("player1.suitblaster.charge", -1))
	await h.wait(3.0)
	var charge_b: float = float(Data.ofOr("player1.suitblaster.charge", -1))
	h.check("the blaster recharges after the beat", charge_b > charge_a, [charge_a, charge_b])
	await h.shot("after_gate")

	# ---- lava death (overheat recall)
	if field != null:
		var r0: int = field.recalls
		field.heat = field.HEAT_MAX + 5.0
		await h.until(func(): return field.recalls > r0, 5.0)
		await _expect(h, "lava_death", "lava_death")
		field.heat = field.HEAT_MAX + 5.0
		await h.until(func(): return field.recalls > r0 + 1, 5.0)
		await h.wait(1.5)
		h.check("a second death plays nothing", not StoryBeats.is_open())

	var played: Array = Array(str(Data.ofOr("team1.story.beatsplayed", "")).split(",", false))
	h.note("played in order", played)
	var dupes: bool = false
	for id in played:
		if played.count(id) > 1:
			dupes = true
	h.check("no beat played twice", not dupes, played)
	# The harness marks the keeper's welcome log played (#123); it isn't wired here.
	played = played.filter(func(id): return id != "keeper_welcome")
	h.check("all 11 wired beats played", played.size() == 11, played.size())
