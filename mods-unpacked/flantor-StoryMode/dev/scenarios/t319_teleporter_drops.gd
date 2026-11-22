extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 319: the teleporter's suction (the teleporterteleportresourcesback
# supplement) pulls in every Story Mode drop it should and pays for it like
# the crusher. The teleporter is set down in a room under the dome.
#
#   one   each type on its own, dropped beside the teleporter: vanilla's
#         IronDrop, Story iron, every mod mineral, miner bones. Each must be
#         pulled in, counted in the inventory, and paid its value; the bones
#         pay their sale value and open their biome's log.
#   batch four at once inside the suction: all pulled in, one after another.
#   left  a translator and a vanilla relic: the suction leaves relics alone,
#         so it leaves the translator too. Both stay, pickable.
#
# `-Extra "--vanilla"`: Relic Hunt with iron, water and sand, and a relic, to
# show vanilla's suction is unchanged.

const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
static var _Minerals = Minerals  # calls go through this: lazy_preload makes const-preload calls slow
const Bones = preload("res://mods-unpacked/flantor-StoryMode/data/bones.gd")
static var _Bones = Bones  # calls go through this: lazy_preload makes const-preload calls slow
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
static var _StoryBeats = StoryBeats  # calls go through this: lazy_preload makes const-preload calls slow

const TIMEOUT := 300
# The room the teleporter is set down in, under the dome.
const ROOM_A := Vector2i(-4, 5)
const ROOM_B := Vector2i(4, 8)
const BONES_BIOME := 2
# Long enough for the cooldown (3.8 s) and the pull, with room to spare.
const PULL_WAIT := 14.0
const VANILLA_IRON := "vanilla IronDrop"

var tp = null
var _beat_ids: Array = []


func boot() -> Dictionary:
	if _vanilla():
		return {"mode": "relichunt", "seed": 12345, "gadget": "teleporter"}
	return {"seed": 12345, "gadget": "teleporter", "beats": true}


func _vanilla() -> bool:
	return OS.get_cmdline_user_args().has("--vanilla")


func _row(d) -> Dictionary:
	if not is_instance_valid(d):
		return {"gone": true}
	return {
		"type": d.type, "pos": d.global_position.round(), "absorbed": d.absorbed,
		"independent": d.independent, "pickable": d.canFocusCarry(),
		"to_tp": d.global_position.distance_to(tp.global_position) if is_instance_valid(tp) else -1.0,
	}


func _money(h) -> int:
	return int(Data.ofOr("team1.inventory.money", 0))


func _spawn(h, label: String, offset: Vector2):
	var t: String = "iron" if label == VANILLA_IRON else label
	var story_iron: PackedScene = Data.DROP_SCENES["iron"]
	if label == VANILLA_IRON:
		Data.DROP_SCENES["iron"] = load("res://content/drop/iron/IronDrop.tscn")
	var d = Level.drops.network_spawn({"type": t, "position": tp.global_position + offset, "impulse": Vector2.ZERO})
	Data.DROP_SCENES["iron"] = story_iron
	if t == _Bones.TYPE:
		d.value = _Bones.value_for(BONES_BIOME)
		d.biome = BONES_BIOME
	return d


func _value(label: String) -> int:
	if _vanilla():
		return 0
	if label == _Bones.TYPE:
		return _Bones.value_for(BONES_BIOME)
	return _Minerals.value_of("iron" if label == VANILLA_IRON else label)


func _ready_to_pull() -> bool:
	return is_instance_valid(tp) and tp.suckCooldown <= 0.0 and tp.currentlySuckedResource == null


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	if not _vanilla():
		# Every beat played but the bones' log (B3), so nothing else opens.
		Data.apply("team1.story.beatsplayed", "biome_b2,biome_b3,biome_b4,biome_b5,biome_b6,biome_b7,biome_b8,lava_ocean,first_gem,gate_broken,lava_death_1,lava_death_2,lava_death_3,lava_death_4,log_b1,log_b2,log_b4,log_b5,log_b6,log_b7,log_b8")
	GameWorld.addUpgrade("teleporterteleportresourcesback", "team1")
	await h.frames(3)
	h.check("the teleporter's suction is on", bool(Data.ofOr("team1.teleporter.teleportResources", false)), {"area": Data.ofOr("team1.teleporter.teleportResourcesArea", 0), "cooldown": Data.ofOr("team1.teleporter.teleportResourcesCooldown", 0)})

	var station = null
	for n in h.get_tree().root.find_children("*", "", true, false):
		if n is TeleporterStation:
			station = n
			break
	h.check("the teleporter station is in the cellar", station != null)
	if station == null:
		return
	await h.dig_room(ROOM_A, ROOM_B)
	var mid: Vector2 = Level.map.getTilePos(Vector2i(0, ROOM_B.y))
	# Out of the station as a keeper takes it (TeleporterStation.registerHit),
	# set down in the room.
	tp = Level.drops.network_spawn({"type": CONST.TELEPORTER, "team": "team1", "position": mid + Vector2(0, -6)})
	station.setTeleporter(tp)
	station.hasTeleporter = false
	await h.teleport_tile(Vector2i(ROOM_A.x + 1, ROOM_B.y))
	await h.wait(2.0)
	# Ore the dig broke out would be pulled in too: clear it away.
	for c in h.get_tree().get_nodes_in_group("carryable"):
		if c != tp and c.has_method("remove") and "absorbed" in c and not c.absorbed and c.global_position.distance_to(tp.global_position) < 160.0:
			h.note("cleared a stray %s" % c.type, c.global_position)
			c.remove()
	await h.wait(0.5)
	h.note("teleporter", {"pos": tp.global_position.round(), "radius_px": tp.get_node("ResourceSucker/CollisionShape2D").shape.radius, "suction_off": tp.get_node("ResourceSucker/CollisionShape2D").disabled})
	await h.shot("teleporter_in_room")
	h.speed(2.0)

	# ---- one: each type on its own.
	var singles: Array = [VANILLA_IRON, "iron"]
	if _vanilla():
		singles += ["water", "sand"]
	else:
		singles += _Minerals.MOD_MINERALS + [_Bones.TYPE]
	for label: String in singles:
		await h.until(_ready_to_pull, PULL_WAIT)
		var t: String = "iron" if label == VANILLA_IRON else label
		var inv0: int = int(Data.ofOr("team1.inventory." + t, 0))
		var m0: int = _money(h)
		var d = _spawn(h, label, Vector2(14, -10))
		var t0: float = h.now()
		var pulled: bool = await h.until(func(): return tp.currentlySuckedResource == d, 4.0)
		if label == singles[0] or label == _Bones.TYPE:
			await h.wait(0.4)
			await h.shot("one_%s_pulling" % label.replace(" ", "_"))
		var taken: bool = await h.until(func(): return not is_instance_valid(d) or d.absorbed, PULL_WAIT)
		var t_taken: float = h.now() - t0
		await h.wait(0.8)
		var inv1: int = int(Data.ofOr("team1.inventory." + t, 0))
		var paid: int = _money(h) - m0
		h.check("one: %s pulled in and taken (%.1f s)" % [label, t_taken], pulled and taken, _row(d))
		h.check("one: %s counted (inventory %d -> %d)" % [label, inv0, inv1], inv1 == inv0 + 1, {"inv0": inv0, "inv1": inv1})
		if not _vanilla():
			h.check("one: %s paid $%d (expected $%d)" % [label, paid, _value(label)], paid == _value(label), {"paid": paid, "expected": _value(label)})
		if label == _Bones.TYPE:
			var log_id: String = "log_b%d" % (BONES_BIOME + 1)
			var opened: bool = await h.until(func(): return _StoryBeats.instance().open_id == log_id, 8.0)
			h.check("one: the bones opened their log (%s)" % log_id, opened, _StoryBeats.instance().open_id)
			if opened:
				await h.read_beat(log_id, 3.0, true)
				await h.wait(0.5)

	# ---- batch: four at once inside the suction.
	await h.until(_ready_to_pull, PULL_WAIT)
	var batch: Array = ["iron", "water", "sand", VANILLA_IRON] if _vanilla() else ["bronze", "sapphire", "emerald", VANILLA_IRON]
	var m0b: int = _money(h)
	var expect_b: int = 0
	var bd: Array = []
	# Dropped side by side beside the teleporter, a moment apart, to land on
	# the floor inside the suction's 33.6 px (it hovers 12-25 px up). Spawned
	# on top of each other, they knock one another out of it, vanilla iron as
	# much as any; spawned at floor height, they can end up in the rock.
	var offs: Array = [Vector2(-20, -6), Vector2(-11, -6), Vector2(11, -6), Vector2(20, -6)]
	for i in batch.size():
		bd.append(_spawn(h, batch[i], offs[i]))
		expect_b += _value(batch[i])
		await h.wait(0.15)
	await h.wait(0.6)
	h.note("batch: in the suction at the start", bd.map(_row))
	await h.shot("batch_start")
	await h.until(func(): return bd.all(func(d): return not is_instance_valid(d) or d.absorbed), batch.size() * PULL_WAIT)
	await h.wait(0.8)
	await h.shot("batch_after")
	for i in batch.size():
		h.check("batch: %s pulled in and taken" % batch[i], not is_instance_valid(bd[i]) or bd[i].absorbed, _row(bd[i]))
	if not _vanilla():
		h.check("batch: paid $%d (expected $%d)" % [_money(h) - m0b, expect_b], _money(h) - m0b == expect_b)

	# ---- left: relics stay, and so does the translator.
	await h.until(_ready_to_pull, PULL_WAIT)
	var left: Array = ["relic"] if _vanilla() else ["translator", "relic"]
	var ld: Array = []
	for i in left.size():
		ld.append(_spawn(h, left[i], Vector2(-14 + 28 * i, -10)))
		await h.frames(2)
	var tr0: int = int(Data.ofOr("team1.inventory.translator", 0))
	var re0: int = int(Data.ofOr("team1.inventory.relic", 0))
	var sucked: Array = []
	var t_end: float = h.now() + 8.0
	while h.now() < t_end:
		if tp.currentlySuckedResource != null and not sucked.has(tp.currentlySuckedResource.type):
			sucked.append(tp.currentlySuckedResource.type)
		await h.wait(0.2)
	await h.shot("left_after")
	for i in left.size():
		var d = ld[i]
		h.check("left: the suction leaves the %s alone, pickable (%.0f px from the teleporter)" % [left[i], _row(d).get("to_tp", -1.0)], is_instance_valid(d) and not d.absorbed and not d.independent and d.canFocusCarry() and not sucked.has(left[i]), _row(d))
	h.check("left: nothing installed or socketed", int(Data.ofOr("team1.inventory.translator", 0)) == tr0 and int(Data.ofOr("team1.inventory.relic", 0)) == re0)
	h.speed(1.0)
	for d in ld:
		if is_instance_valid(d) and not d.absorbed:
			d.remove()
	await h.wait(0.5)
