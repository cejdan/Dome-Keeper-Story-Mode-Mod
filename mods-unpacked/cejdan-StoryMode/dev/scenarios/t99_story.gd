extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 99: the story's regression run. One seed, every beat live, walked in
# story order and captured page by page:
#   B1 .. B8 by teleport (each biome's beat), with each biome's events where
#   they sit: the first gem, the gate broken by a real Suit Blaster blast, the
#   miners' bones (uncovered, then delivered for their value, which opens
#   the miner's log), the three
#   translator chambers (opened, carried home, installed, the horror's reply,
#   then a plea at the new translation stage), and an overheat death;
#   the lava ocean, 10 unobtainium (the seal beats), the boss chamber (the
#   awakening, then "not yet"); Retire Rich bought with the shop open and the
#   whole doom ending to the end screen.
# Heat Shielding IV is bought first so depth heat never recalls the keeper.
# Checks every beat and log opens exactly once, nothing else ever opens, and
# the run ends won. The saved ending is t97_saved.

const BeatData = preload("res://mods-unpacked/cejdan-StoryMode/data/beats.gd")
const LogData = preload("res://mods-unpacked/cejdan-StoryMode/data/logs.gd")
const PleaData = preload("res://mods-unpacked/cejdan-StoryMode/data/pleas.gd")
const Endings = preload("res://mods-unpacked/cejdan-StoryMode/data/endings.gd")
const Bones = preload("res://mods-unpacked/cejdan-StoryMode/data/bones.gd")
const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")
const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")
const LavaData = preload("res://mods-unpacked/cejdan-StoryMode/data/lava.gd")
const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const Awakening = preload("res://mods-unpacked/cejdan-StoryMode/beats/awakening.gd")
const Runes = preload("res://mods-unpacked/cejdan-StoryMode/pleas/runes.gd")

const UNOB_ID := 47
const GEM_IDS := [42, 43, 44, 46]
const GATE_X := 2
# The overheat death comes after this biome's events (B5).
const DEATH_BIOME := 4

var opened: Array = []
var field = null
var td = null
var pd = null
var translators: int = 0


func boot() -> Dictionary:
	return {"seed": 12345, "beats": true}


# ---------------------------------------------------------------- helpers

func _expect(h, id: String, label: String, timeout: float = 8.0) -> void:
	var got: String = await h.read_beat(label, timeout)
	var what: String = "log" if not LogData.by_id(id).is_empty() else "tier %d" % int(BeatData.by_id(id).get("tier", 0))
	h.check("%s plays (%s)" % [id, what], got == id, got)


# Nothing on screen and nothing waiting.
func _quiet(h, label: String) -> void:
	await h.wait(1.0)
	var q: String = str(Data.ofOr(StoryBeats.QUEUED, ""))
	h.check("%s: no other beat opens" % label, not StoryBeats.is_open() and q == "", {"open": StoryBeats.instance().open_id, "queued": q})


func _cool() -> void:
	if field != null:
		field.heat = 0.0


# A cell of biome `b` near the map's middle column, mid-band, above the ocean
# (as t26_wired).
func _cell_in_biome(b: int) -> Vector2i:
	var ceiling: int = int(td.get_meta("story_ocean", {}).get("ceiling", 1 << 20))
	var cells: Array = []
	for c: Vector2i in td.get_used_biome_cells():
		if td.get_biomev(c) == b and absi(c.x) <= 6 and c.y < ceiling - 1:
			cells.append(c)
	cells.sort_custom(func(a, c): return a.y < c.y)
	return cells[cells.size() / 2] if cells.size() > 0 else Vector2i(9999, 9999)


# The biome an event belongs to: the deeper of its tile and where the keeper
# stands for it, so its phase comes after that biome's beat.
func _phase(at: Vector2i, stand: Vector2i) -> int:
	return maxi(td.get_biomev(at), td.get_biomev(stand))


func _home(h) -> void:
	var dome = Level.getDome("team1")
	var to: Vector2 = field.recall_pos if field != null and field.recall_pos != null else dome.global_position + Vector2(0, -20)
	h.keeper().teleport(to)
	h.snap_camera()
	await h.wait(0.8)
	_cool()


# A wave's arrival line from the current pool: the pool matches the deepest
# biome, and the label on screen shows it at the current translation stage.
func _plea(h, label: String, want_stage: String) -> void:
	var line: String = pd.say("arrive", null, "", 6.0)
	await h.wait(1.2)
	var shown = h.get_tree().get_nodes_in_group("story-plea").filter(func(n): return n.get_meta("line", "") == line)
	var text: String = shown.back().get_child(0).get_parsed_text() if not shown.is_empty() else ""
	var st: int = Runes.stage()
	h.check("plea %s: stage %s pool, translation stage %d" % [label, want_stage, st],
			pd.stage() == want_stage and PleaData.pool(want_stage, "arrive").has(line) and text == Runes.render(line, st),
			{"stage": pd.stage(), "line": line, "shown": text, "want": Runes.render(line, st)})
	await h.shot("plea_%s" % label)
	await h.wait(1.0)


# ---------------------------------------------------------------- events

func _first_gem(h, gem: Vector2i) -> void:
	h.note("first gem", {"cell": gem, "type": Minerals.by_tile_id(td.get_resourcev(gem)), "biome": td.get_biomev(gem)})
	await h.dig_room(gem + Vector2i(-2, -3), gem + Vector2i(2, -1))
	await h.reveal([gem])
	await h.teleport_tile(gem + Vector2i(0, -1))
	Level.map.destroyTile("team1", "", Level.map.getTile(Vector2(gem)))
	await _expect(h, "first_gem", "first_gem")


func _gate(h, top: int) -> void:
	var gate: Array = td.get_resource_cells_by_id(Metal.GATE_ID)
	await h.dig_room(Vector2i(GATE_X - 3, top - 4), Vector2i(GATE_X + 3, top - 1))
	await h.teleport_tile(Vector2i(GATE_X, top - 1))
	GameWorld.serverAddUpgrade("player1.suitblaster", "team1")
	await h.wait(1.0)
	Data.apply("player1.suitblaster.charge", 1.0)
	await h.wait(1.0)
	await h.shot("gate_before_blast")
	await h.press("keeper_gadget1")
	var opened_mid: bool = await h.until(func(): return StoryBeats.is_open(), 6.0)
	h.check("the blast breaks the gate (beat opens mid-blast)", opened_mid and StoryBeats.instance().open_id == "gate_broken")
	await _expect(h, "gate_broken", "gate_broken")
	await h.wait(3.0)
	var left: int = 0
	for c: Vector2i in gate:
		if c.x == GATE_X and td.get_resourcev(c) == Metal.GATE_ID:
			left += 1
	h.check("the gate column is cleared", left == 0, left)
	await h.shot("gate_after_blast")


func _bones(h, p: Array) -> void:
	var at: Vector2i = Vector2i(int(p[0]), int(p[1]))
	var b: int = int(p[2])
	await h.dig_room(at + Vector2i(-2, -3), at + Vector2i(2, -1))
	await h.teleport_tile(at + Vector2i(0, -1))
	await h.reveal([at])
	await h.shot("bones_b%d" % (b + 1))
	var dome = Level.getDome("team1")
	var m0: int = int(h.inv("money"))
	Level.map.destroyTile("team1", "", Level.map.getTile(Vector2(at)))
	await h.wait(0.5)
	var drop = null
	for d in Level.drops.find_children("*", "", true, false):
		if d.get("type") == Bones.TYPE and not d.absorbed:
			drop = d
	if drop != null:
		drop.global_position = dome.getDropTarget("iron").global_position + Vector2(0, -8)
		drop.linear_velocity = Vector2.ZERO
		await h.until(func(): return int(h.inv("money")) > m0, 10.0)
	h.check("B%d bones delivered: +$%d" % [b + 1, Bones.value_for(b)], drop != null and int(h.inv("money")) - m0 == Bones.value_for(b), int(h.inv("money")) - m0)
	# Selling the bones opens the miner's log (#94).
	await _expect(h, "log_b%d" % (b + 1), "log_b%d" % (b + 1), 5.0)


func _translator(h, ch) -> void:
	var at: Vector2i = Level.map.getTileCoord(ch.global_position + Vector2(12, 12))
	var n: int = translators + 1
	await h.dig_room(at + Vector2i(-3, -3), at + Vector2i(4, -1))
	await h.reveal([at, at + Vector2i(1, 0), at + Vector2i(0, 1), at + Vector2i(1, 1)])
	await h.teleport_tile(at + Vector2i(0, -1))
	await h.wait(0.8)
	await h.shot("chamber%d_found" % n)
	for c: Vector2i in [at, at + Vector2i(1, 0), at + Vector2i(0, 1), at + Vector2i(1, 1)]:
		var t = Level.map.getTile(Vector2(c))
		if t != null:
			Level.map.destroyTile("team1", "", t)
	await h.until(func(): return ch.currentState == ch.State.OPEN, 8.0)
	await h.teleport_tile(at + Vector2i(1, 1))
	await h.wait(1.0)
	await h.shot("chamber%d_open" % n)
	h.check("chamber %d (B%d) opens" % [n, td.get_biomev(at) + 1], ch.currentState == ch.State.OPEN, ch.currentState)
	ch.registerHit("player1")
	await h.wait(0.8)
	var carried: Array = h.keeper().carriedCarryables.filter(func(c): return is_instance_valid(c) and c.type == "translator")
	h.check("chamber %d: the keeper carries its translator" % n, carried.size() == 1, h.keeper().carriedCarryables.size())
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
	h.check("translator %d installed" % n, got, h.inv("translator"))
	await _expect(h, "translator_%d" % n, "translator_%d" % n)
	translators = n
	h.check("translation stage is %d" % n, Runes.stage() == n, Runes.stage())
	await _plea(h, "translator%d" % n, PleaData.stage_for(StoryBeats.deepest()))


func _lava_death(h) -> void:
	var r0: int = field.recalls
	field.heat = field.HEAT_MAX + 5.0
	await h.until(func(): return field.recalls > r0, 5.0)
	h.check("overheat recalls the keeper", field.recalls > r0, field.recalls)
	await _expect(h, "lava_death", "lava_death")


# ---------------------------------------------------------------- run

func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	td = Level.map.tileData
	field = Level.map.get_node_or_null("StoryLavaField")
	pd = load("res://mods-unpacked/cejdan-StoryMode/pleas/plea_director.gd").instance()
	StoryBeats.instance().beat_opened.connect(func(id): opened.append(id))
	h.check("lava field and plea director are in the run", field != null and pd != null)

	# Heat Shielding IV first: depth heat can't recall the keeper.
	h.set_inv("money", 10000000)
	for n in range(1, 5):
		await h.buy("storyheatshield%d" % n)
	h.set_inv("money", 0)
	h.check("Heat Shielding IV bought", LavaData.shield_tier() == 4 and LavaData.passive_heat_mult() == 0.0, LavaData.shield_tier())
	await h.shot("start")
	await _plea(h, "start", "A")

	# Where each biome's events are.
	var gem: Vector2i = Vector2i(9999, 0)
	for id: int in GEM_IDS:
		for c: Vector2i in td.get_resource_cells_by_id(id):
			if absi(c.x) < 30 and c.y < 120 and (gem.x == 9999 or c.y < gem.y):
				gem = c
	var gem_phase: int = _phase(gem, gem + Vector2i(0, -1))
	var gate_top: int = 1 << 20
	for c: Vector2i in td.get_resource_cells_by_id(Metal.GATE_ID):
		if c.x == GATE_X and c.y < gate_top:
			gate_top = c.y
	var gate_phase: int = td.get_biomev(Vector2i(GATE_X, gate_top - 1))
	var bones: Array = td.get_meta("story_bones", [])
	h.check("the run has 8 sets of bones", bones.size() == 8, bones)
	var chambers: Array = []
	for c in Level.map.find_children("*", "", true, false):
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("TranslatorChamber.gd"):
			chambers.append(c)
	chambers.sort_custom(func(a, b): return a.global_position.y < b.global_position.y)
	h.check("the run has 3 translator chambers", chambers.size() == 3, chambers.size())
	h.note("plan", {"gem": [gem, gem_phase], "gate": [gate_top, gate_phase], "bones": bones,
			"chambers": chambers.map(func(ch): return td.get_biomev(Level.map.getTileCoord(ch.global_position + Vector2(12, 12))))})

	# ---- B1 .. B8
	for b in range(0, 8):
		if b >= 1:
			var c: Vector2i = _cell_in_biome(b)
			await h.dig_room(c + Vector2i(-2, -2), c + Vector2i(2, 0))
			await h.teleport_tile(c)
			await _expect(h, "biome_b%d" % (b + 1), "b%d" % (b + 1))
			_cool()
		if gem_phase == b:
			await _first_gem(h, gem)
		if gate_phase == b:
			await _gate(h, gate_top)
		for p in bones:
			var at: Vector2i = Vector2i(int(p[0]), int(p[1]))
			if _phase(at, at + Vector2i(0, -1)) == b:
				await _bones(h, p)
				_cool()
		for ch in chambers:
			var at: Vector2i = Level.map.getTileCoord(ch.global_position + Vector2(12, 12))
			if _phase(at, at + Vector2i(0, -1)) == b:
				await _translator(h, ch)
		if b == DEATH_BIOME:
			await _lava_death(h)
		await _quiet(h, "B%d" % (b + 1))
	h.check("deepest reached is B8", StoryBeats.deepest() == 7, StoryBeats.deepest())
	h.check("all 3 translators installed", translators == 3 and Runes.stage() == 3, Runes.stage())

	# ---- the lava ocean
	var ocean: Dictionary = td.get_meta("story_ocean", {})
	var oc: Vector2i = Vector2i(0, int(ocean.get("top", 0)) - 1)
	await h.dig_room(oc + Vector2i(-2, -2), oc)
	await h.teleport_tile(oc)
	await _expect(h, "lava_ocean", "ocean")
	_cool()
	await _plea(h, "ocean", "D")

	# ---- ten unobtainium: the seal breaks
	var cells: Array = td.get_resource_cells_by_id(UNOB_ID)
	cells.sort_custom(func(a, b): return absi(a.x) + a.y < absi(b.x) + b.y)
	h.check("the ocean holds at least 10 unobtainium", cells.size() >= 10, cells.size())
	var seal: Dictionary = {1: "unobtainium_1", 3: "unobtainium_3", 5: "unobtainium_5", 7: "unobtainium_7", 10: "unobtainium_10"}
	for i in mini(10, cells.size()):
		var c: Vector2i = cells[i]
		await h.reveal([c])
		await h.teleport_tile(c + Vector2i(0, -1))
		_cool()
		Level.map.destroyTile("team1", "", Level.map.getTile(Vector2(c)))
		await h.frames(3)
		if seal.has(i + 1):
			await _expect(h, seal[i + 1], "unob%02d" % (i + 1), 6.0)
		else:
			await _quiet(h, "unobtainium %d" % (i + 1))
	h.check("10 mined, the seal at %.2f" % Awakening.level(), Awakening.mined() == 10, Awakening.mined())

	# ---- the boss chamber
	var room: Rect2i = td.get_meta("story_boss_chamber", Rect2i())
	await h.teleport_tile(room.position + room.size / 2)
	await _expect(h, "boss_chamber", "chamber", 6.0)
	h.check("the horror is awake", Awakening.is_awake(), Awakening.level())
	await _expect(h, "boss_wait", "not_yet", 6.0)
	await _quiet(h, "boss chamber")

	# ---- Retire Rich, from inside the shop: the doom ending
	await _home(h)
	var ed = Level.mode.get_node_or_null("StoryEndings")
	h.set_inv("money", 1000000)
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	await h.shot("shop_open")
	h.check("Retire Rich bought", await h.buy("storyretirerich"))
	await _expect(h, "doom_thanks", "thanks")
	await h.until(func(): return ed.last_step == "last_words", 5.0)
	var lines: Array = []
	for i in Endings.DOOM_LAST_WORDS.size():
		await h.wait(1.4)
		lines.append(h.get_tree().get_nodes_in_group("story-plea").map(func(n): return n.get_child(0).get_parsed_text()))
		await h.shot("last_words_%d" % (i + 1))
		await h.wait(2.0)
	var first: String = str(lines[0].back()) if lines.size() > 0 and lines[0].size() > 0 else ""
	h.check("the monsters' last words, all in English (stage 3)", first == Runes.render(Endings.DOOM_LAST_WORDS[0], 3), lines)
	await h.until(func(): return ed.last_step == "cards", 10.0)
	var seen: Array = []
	var t_end: float = h.now() + 40.0
	while h.now() < t_end and ed.last_step == "cards":
		var box = h.beat_box()
		if box != null and box.get("cards") != null and box.current_card() != "" and not seen.has(box.current_card()):
			await h.wait(1.2)
			seen.append(box.current_card())
			await h.shot("card_%d" % seen.size())
		await h.wait(0.2)
	h.check("every doom card shows", seen == Endings.DOOM_CARDS, seen)
	await h.until(func(): return Level.stage.endingPanel != null, 15.0)
	await h.wait(3.0)
	var panel = Level.stage.endingPanel
	await h.shot("end_screen")
	h.check("the end screen reads \"%s\"" % Endings.DOOM_TITLE, panel != null and panel.titleLabel.text == Endings.DOOM_TITLE, panel.titleLabel.text if panel != null else "")

	# ---- the whole story, once each
	h.note("opened in order", opened)
	var want: Array = BeatData.BEATS.map(func(b): return b["id"]) + LogData.LOGS.map(func(l): return l["id"])
	var wrong: Dictionary = {}
	for id in want:
		if opened.count(id) != 1:
			wrong[id] = opened.count(id)
	for id in opened:
		if not want.has(id):
			wrong[id] = "unknown"
	h.check("all %d beats and logs opened exactly once" % want.size(), wrong.is_empty() and opened.size() == want.size(), wrong)
	h.check("the run is won", GameWorld.won and Data.ofOr("game.over", "") == "won", {"won": GameWorld.won, "game.over": Data.ofOr("game.over", "")})
