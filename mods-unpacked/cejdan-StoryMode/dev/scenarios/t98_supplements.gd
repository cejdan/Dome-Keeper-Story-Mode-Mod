extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 98: vanilla supplement chambers in Story Mode. A 20-seed map check
# (with vanilla's supplement cap applied, as GameWorld.prepareLevelStart does)
# counts min(4, cap) five-cell chambers per map, none touching the gate. In
# the running game the keeper opens one with water, carries the power core
# home, the vanilla supplement choice opens, and the pick applies.

const MapConfig = preload("res://mods-unpacked/cejdan-StoryMode/data/map_config.gd")
const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


# Vanilla's cap (game/GameWorld.gd prepareLevelStart).
func _cap() -> int:
	var cap: int = 1
	var r: Dictionary = GameWorld.assignmentRewardStatus
	if r.get("rewardweaponsupplements", 0) == 2:
		cap += 1
	if r.get("rewardkeepersupplements", 0) == 2:
		cap += 1
	if r.get("rewardgadgetsupplements", 0) == 2:
		cap += 5
	return cap


func _clusters(td) -> Array:
	var left: Dictionary = {}
	for c: Vector2i in td.get_resource_cells_by_id(Data.TILE_SUPPLEMENT):
		left[c] = true
	var out: Array = []
	while left.size() > 0:
		var s: Vector2i = left.keys()[0]
		left.erase(s)
		var open: Array = [s]
		var grp: Array = []
		while open.size() > 0:
			var c: Vector2i = open.pop_back()
			grp.append(c)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if left.has(c + d):
					left.erase(c + d)
					open.append(c + d)
		out.append(grp)
	return out


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	var cap: int = _cap()
	var want: int = mini(4, cap)
	var bad: Array = []
	var counts: Array = []
	for s in 20:
		var a = MapConfig.make_archetype()
		a.powercores = mini(a.powercores, cap)
		var td = h.generate_map(a, 4000 + s)
		if td == null:
			bad.append([4000 + s, "no map"])
			continue
		var cl: Array = _clusters(td)
		counts.append(cl.size())
		if cl.size() != want:
			bad.append([4000 + s, "chambers", cl.size()])
		for g in cl:
			if g.size() != 5:
				bad.append([4000 + s, "cells", g.size()])
			for c: Vector2i in g:
				for ox in range(-1, 2):
					for oy in range(-1, 2):
						if td.get_resourcev(c + Vector2i(ox, oy)) == Metal.GATE_ID:
							bad.append([4000 + s, "touches gate", c])
		td.queue_free()
		await h.frames(1)
	h.note("supplement chambers per map", {"cap": cap, "want": want, "counts": counts})
	h.check("20 seeds: min(4, cap) = %d five-cell supplement chambers a map, none touching the gate" % want, bad.is_empty(), bad)

	# ---- the run's chamber
	var ch = null
	for c in Level.map.find_children("*", "", true, false):
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("PowerCoreChamber.gd"):
			ch = c
	h.check("the run has a supplement chamber", ch != null)
	if ch == null:
		return
	# The chamber's own cells (Chamber.place: coord plus its tile cover).
	var cover: Array = []
	for c in ch.tileCoords:
		cover.append(Vector2i(ch.coord + Vector2(c)))
	var at: Vector2i = cover[0]
	for c: Vector2i in cover:
		at = Vector2i(mini(at.x, c.x), mini(at.y, c.y))
	await h.dig_room(at + Vector2i(-3, -3), at + Vector2i(4, -1))
	await h.reveal(cover)
	await h.teleport_tile(at + Vector2i(0, -1))
	for c: Vector2i in cover:
		var t = Level.map.getTile(Vector2(c))
		if t != null:
			Level.map.destroyTile("team1", "", t)
	await h.wait(2.0)
	await h.shot("supplement_chamber_dug")
	h.check("the chamber's cells are dug out", ch.tileCover == null or not is_instance_valid(ch.tileCover) or ch.tileCover.get_used_cells(MapData.DEFAULT_LAYER).is_empty(), cover)
	# Feed it water. The grabber only takes a drop that has a team.
	var grab = ch.get_node("ResourceGrabber")
	Level.drops.network_spawn({"type": "water", "position": grab.global_position + Vector2(0, -6), "impulse": Vector2.ZERO, "team": "team1"})
	var opened: bool = await h.until(func(): return ch.currentState == ch.State.OPEN, 15.0)
	await h.shot("supplement_chamber_open")
	h.check("water opens the supplement chamber", opened, ch.currentState)
	ch.registerHit("player1")
	await h.wait(0.8)
	var core = null
	for c in h.keeper().carriedCarryables:
		if is_instance_valid(c) and c.type == "powercore":
			core = c
	h.check("the keeper carries a power core", core != null)
	if core == null:
		return
	var dome = Level.getDome("team1")
	h.keeper().teleport(dome.global_position + Vector2(0, -20))
	h.snap_camera()
	var popped: bool = await h.until(func(): return Level.stage.currentOfferTypeByPlayerId.get("player1", "") == CONST.POWERCORE, 12.0)
	if not popped and is_instance_valid(core):
		core.global_position = dome.getDropTarget("powercore").global_position
		popped = await h.until(func(): return Level.stage.currentOfferTypeByPlayerId.get("player1", "") == CONST.POWERCORE, 8.0)
	await h.wait(2.0)
	await h.shot("supplement_choice")
	h.check("the vanilla supplement choice opens", popped)
	var offers: Array = Level.stage.currentOffersByPlayerId.get("player1", [])
	h.check("it offers supplements", offers.size() > 0, offers.map(func(o): return o.get("id", "")))
	if offers.size() > 0:
		var pick: String = offers[0]["id"]
		Level.stage.onGadgetSelected(pick, CONST.POWERCORE, "player1", "team1")
		await h.wait(2.0)
		await h.shot("after_pick")
		h.check("the picked supplement applies (%s)" % pick, GameWorld.boughtUpgrades.has(pick), pick)
