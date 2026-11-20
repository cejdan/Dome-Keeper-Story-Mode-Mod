extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 289: Workshop footage, an early-game story teaser. Run it under Movie
# Maker (see dev/workshop_shoot.gd); "clip" notes give the frames to cut at.
# Only beats from the first hours (B1 to B3): the company's welcome memo, the
# monsters' pleas during a wave (in their runes: no translator yet), a miner's
# bones in the rock and the log they hold, the voice in B2 and B3, the first
# translator. Each page stays up long enough to read.

const Shoot = preload("res://mods-unpacked/cejdan-StoryMode/dev/workshop_shoot.gd")
const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const Bones = preload("res://mods-unpacked/cejdan-StoryMode/data/bones.gd")
const TIMEOUT := 900


func boot() -> Dictionary:
	return {"seed": 12345, "beats": true, "welcome": true}


func _pd():
	return load("res://mods-unpacked/cejdan-StoryMode/pleas/plea_director.gd").instance()


# Waits for a beat, holds each page `sec` s (typing included), shoots it,
# turns it with select. Returns the beat id.
func _read(h, label: String, sec: float) -> String:
	await h.until(func(): return StoryBeats.is_open(), 8.0)
	var id: String = StoryBeats.instance().open_id
	Shoot.clip(h, "beat_" + label)
	for page in 12:
		await h.wait(sec)
		await h.shot("%s_p%d" % [label, page + 1])
		await h.press("ui_select")
		await h.wait(0.3)
		if StoryBeats.instance().open_id != id:
			break
		# A press that only finished the typing: press again next round.
	Shoot.clip(h, "beat_" + label + "_end")
	h.note("read", {"label": label, "id": id})
	await h.wait(1.0)
	return id


func _sell_bones(h, biome: int) -> void:
	var dome = Level.getDome("team1")
	var target: Vector2 = dome.getDropTarget("iron").global_position + Vector2(0, -8)
	var drop = Level.drops.network_spawn({"type": Bones.TYPE, "position": target + Vector2(0, -12), "impulse": Vector2.ZERO})
	drop.value = Bones.value_for(biome)
	drop.biome = biome


# A small room in `biome` near x 0: top-left of a 7 x 3 room.
func _room(h, td, biome: int) -> Vector2i:
	var o: Vector2i = Shoot.find_rock(td, 7, 3, [biome], 4, 90, -12, 8)
	await h.reveal(Shoot.rect(o - Vector2i(2, 2), 11, 7))
	await h.clear_tiles(Shoot.rect(o, 7, 3))
	return o


func run(h) -> void:
	Shoot.window_1080()
	var td = Level.map.tileData

	# ---- 1. the welcome memo, a moment after landing
	var id: String = await _read(h, "welcome", 6.0)
	h.check("the run opens with the welcome memo", id == "keeper_welcome", id)
	h.disable_waves()

	# ---- 2. a wave, and the monsters' pleas in their runes
	await h.wait(1.0)
	var pd = _pd()
	pd.death_chance = 1.0
	Data.apply("team1.dome.maxHealth", 1000000)
	Data.apply("team1.dome.health", 1000000)
	h.enable_waves()
	GameWorld.runStarted = true
	Data.apply("team1.story.deepest", 0)
	Data.apply("team1.monsters.wavecooldown", 2)
	var came: bool = await h.until(func(): return Data.of("team1.monsters.wavepresent"), 40.0)
	h.check("a wave arrives", came)
	await h.until(func(): return pd.shown.size() > 0, 4.0)
	Shoot.clip(h, "plea_arrive")
	await h.wait(2.5)
	await h.shot("plea_arrive")
	await h.until(func(): return pd.shown.size() > 1, 10.0)
	await h.wait(0.8)
	await h.shot("plea_fight")
	await h.wait(1.5)
	var mm = Level.monstersByTeamId["team1"]
	mm.instantlyKillWave()
	await h.wait(0.6)
	await h.shot("plea_death")
	await h.wait(2.0)
	Shoot.clip(h, "plea_end")
	h.note("pleas", pd.shown)
	await h.until(func(): return not Data.of("team1.monsters.wavepresent"), 60.0)
	h.disable_waves()

	# ---- 3. a miner's bones in the rock, and the log they hold
	var bones := Vector2i(-9999, -9999)
	for c in td.get_used_cells(MapData.LAYER_BIOME):
		if td.get_resourcev(c) == Bones.TILE_ID and td.get_biomev(c) == 0:
			bones = c
	h.check("B1 has its bones", bones.x != -9999, bones)
	var dig: Array = []
	for dx in range(1, 5):
		dig.append(bones + Vector2i(dx, 0))
	await h.reveal(Shoot.rect(bones - Vector2i(3, 3), 10, 7))
	await h.clear_tiles(dig)
	await h.teleport_tile(bones + Vector2i(3, 0))
	await h.wait(1.5)
	h.snap_camera()
	await h.wait(1.0)
	Shoot.clip(h, "bones_rock")
	await h.shot("bones_in_rock")
	h.down("ui_left")
	await h.until(func(): return Level.map.is_tile_empty(bones), 15.0)
	h.up("ui_left")
	await h.wait(1.5)
	await h.shot("bones_dropped")
	Shoot.clip(h, "bones_rock_end")
	await h.teleport_tile(Vector2i(0, -1))
	await h.wait(2.0)
	_sell_bones(h, 0)
	id = await _read(h, "log_b1", 6.0)
	h.check("the bones open Dale's log", id == "log_b1", id)

	# ---- 4. the voice in B2
	var r2: Vector2i = await _room(h, td, 1)
	await h.teleport_tile(r2 + Vector2i(3, 2))
	await h.wait(1.5)
	if not StoryBeats.is_open():
		StoryBeats.fire("biome_b2")
	id = await _read(h, "b2", 5.0)
	h.check("B2 plays its beat", id == "biome_b2", id)

	# ---- 5. the first translator, at the dome
	await h.teleport_tile(Vector2i(0, -1))
	await h.wait(1.5)
	StoryBeats.fire("translator_1")
	await _read(h, "translator_1", 5.0)

	# ---- 6. the voice in B3, and Ines' log
	var r3: Vector2i = await _room(h, td, 2)
	await h.teleport_tile(r3 + Vector2i(3, 2))
	await h.wait(1.5)
	if not StoryBeats.is_open():
		StoryBeats.fire("biome_b3")
	id = await _read(h, "b3", 5.0)
	h.check("B3 plays its beat", id == "biome_b3", id)
	await h.teleport_tile(Vector2i(0, -1))
	await h.wait(2.0)
	_sell_bones(h, 2)
	await _read(h, "log_b3", 6.0)
	await h.wait(1.0)
