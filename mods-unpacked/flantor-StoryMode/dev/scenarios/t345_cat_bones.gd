extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #345: the Beastmaster's (keeper4) cats and the miner bones (#94).
#   A. Cats dig the B4 set of bones out of the rock themselves: one bones drop,
#      worth B4's value, carried home by the cats; the sale pays exactly that
#      and opens log_b4.
#   B. The keeper breaks the B6 set; the cats carry the bones home; the sale
#      pays B6's value and opens log_b6.
# Ores around each hole are turned to plain rock first, so the money that
# comes in is the bones' alone. `-Extra "--catupgrades"` gives the cats a
# certain extra piece and has them break a tile once it is empty (the
# Beastmaster's upgrades): still one set of bones, paid once.

const TIMEOUT := 300
const Bones = preload("res://mods-unpacked/flantor-StoryMode/data/bones.gd")
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
static var _StoryBeats = StoryBeats  # calls go through this: lazy_preload makes const-preload calls slow
const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const Keeper2Run = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t297_keeper2.gd")

var seen: Dictionary = {}  # bones drop UID -> [value, biome] last seen


func boot() -> Dictionary:
	return {"seed": 12345, "keeper": "keeper4", "beats": true}


func _bones_drops() -> Array:
	return Level.drops.synchronizer.drops.values().filter(func(d): return is_instance_valid(d) and d.type == Bones.TYPE)


func _track() -> void:
	for d in _bones_drops():
		seen[d.UID] = [int(d.value), int(d.biome)]


# A room over the bones at `at`, with every ore within 8 tiles made plain rock,
# and a dug-out hole in it.
func _room_with_hole(h, k, at: Vector2i):
	var td = Level.map.tileData
	for y in range(at.y - 9, at.y + 9):
		for x in range(at.x - 9, at.x + 10):
			var c := Vector2i(x, y)
			var r: int = td.get_resourcev(c)
			if c != at and r != Data.TILE_EMPTY and r != Data.TILE_DIRT_START and r != -1:
				td.set_resourcev(c, Data.TILE_DIRT_START)
	await h.dig_room(at + Vector2i(-4, -3), at + Vector2i(4, -1))
	await h.reveal([at, at + Vector2i(-1, 0), at + Vector2i(1, 0)])
	var goblins = Level.getDome(k.teamId).goblins
	var hole = goblins.spawn_hole(k.playerId, Level.map.getTilePos(at + Vector2i(-3, -1)))
	for i in Keeper4GameplaySettings.HOLE_TOTAL_PUNCHES:
		hole.receive_punch()
	await h.until(func(): return is_instance_valid(hole) and hole.hole_state == GoblinHole.HoleState.DUG_OUT, 10.0)
	await h.teleport_tile(at + Vector2i(2, -1), k)
	return hole


# Waits for the sale, then reads the log it opens.
func _sale(h, label: String, b: int, m0: int) -> void:
	var want: int = Bones.value_for(b)
	var paid: bool = await h.until(func():
		_track()
		return int(h.inv("money")) > m0, 90.0)
	await h.wait(0.3)
	h.check("%s: the cats brought the bones home and they sold" % label, paid, int(h.inv("money")) - m0)
	h.check("%s: the sale paid B%d's $%d" % [label, b + 1, want], int(h.inv("money")) - m0 == want, int(h.inv("money")) - m0)
	var id: String = await h.read_beat("log_b%d" % (b + 1), 10.0)
	h.check("%s: selling them opened log_b%d" % [label, b + 1], id == "log_b%d" % (b + 1), id)


func run(h) -> void:
	h.disable_waves()
	var k = h.keeper()
	h.check("the run's keeper is the Beastmaster", k != null and k.techId == "keeper4", k.techId if k else null)
	await h.wait(1.0)
	await Keeper2Run.close_tutorials(h)
	# Only the logs may play.
	Data.apply("team1.story.beatsplayed", "keeper_welcome,biome_b2,biome_b3,biome_b4,biome_b5,biome_b6,biome_b7,biome_b8,lava_ocean,first_gem,gate_broken,lava_death_1,lava_death_2,lava_death_3,lava_death_4")
	h.set_inv("money", 10000000)
	for n in range(1, 5):
		await h.buy("storyheatshield%d" % n, k)
	h.set_inv("money", 0)
	Data.apply(k.playerId + ".keeper4.catgoblincount", 6)
	Data.apply(k.playerId + ".keeper4.catgoblinminingspeed", 4.0)
	if _Story.has_user_arg("catupgrades"):
		Data.apply(k.playerId + ".keeper4.goblinextraresourcechance", 1.0)
		Data.apply(k.playerId + ".keeper4.goblindestroytileondig", true)
	var placed: Array = Level.map.tileData.get_meta("story_bones", [])
	var by_biome: Dictionary = {}
	for p in placed:
		by_biome[int(p[2])] = Vector2i(int(p[0]), int(p[1]))
	h.check("the run has B4 and B6 bones", by_biome.has(3) and by_biome.has(5), placed)

	# ---- A: the cats dig the B4 bones out themselves
	var a: Vector2i = by_biome[3]
	await _room_with_hole(h, k, a)
	var t = Level.map.getTile(Vector2(a))
	h.check("A: the B4 bones are uncovered", t != null and t.type == Bones.TYPE, t.type if t else "none")
	await h.wait(1.0)
	await h.shot("a_room")
	var m0: int = int(h.inv("money"))
	var mined: bool = await h.until(func():
		_track()
		var tt = Level.map.getTile(Vector2(a))
		return tt == null or tt.type != Bones.TYPE, 60.0)
	await h.wait(0.5)
	_track()
	h.check("A: the cats dug the bones out", mined, Level.map.getTile(Vector2(a)).type if Level.map.getTile(Vector2(a)) else "none")
	h.note("A: bones drops seen [value, biome]", seen)
	h.check("A: exactly one bones drop, worth B4's $%d" % Bones.value_for(3), seen.size() == 1 and seen.values()[0] == [Bones.value_for(3), 3], seen)
	await h.shot("a_dug")
	await _sale(h, "A", 3, m0)
	await h.shot("a_sold")

	# ---- B: the keeper breaks the B6 bones, the cats carry them home
	seen.clear()
	var b: Vector2i = by_biome[5]
	await _room_with_hole(h, k, b)
	await h.wait(0.5)
	m0 = int(h.inv("money"))
	Level.map.destroyTile("team1", "", Level.map.getTile(Vector2(b)))
	await h.wait(0.5)
	_track()
	h.check("B: breaking the B6 bones drops one, worth $%d" % Bones.value_for(5), seen.size() == 1 and seen.values()[0] == [Bones.value_for(5), 5], seen)
	await h.shot("b_broken")
	var carried: bool = await h.until(func(): return _bones_drops().any(func(d): return d.carrierCount() > 0), 30.0)
	h.check("B: a cat picks the bones up", carried)
	await h.shot("b_carried")
	await _sale(h, "B", 5, m0)
	await h.shot("b_sold")
	h.snap("end", [])
