extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #234: an online co-op run end to end, host half. Three instances: this host,
# the client (t234_mp_e2e_client) and a second client that buys the Teleporter
# from the gadget shop and leaves mid-run (t234_mp_e2e_leaver, -Client2). Then,
# host and client together: selling (host at the dome; client carrying iron
# and B1's bones home), a translator the client takes from the B2 chamber, the
# shop (each keeper's own drill, Heat Shielding and Suit Blaster; the team's
# Health Meter -> Sand Repair -> Second Weapon), the gadget shop (the client
# through the real shop panel, then host and client at once), a metal gate the
# client blasts, the Metal Bit, a monster wave fought from both stations, and
# Retire Rich bought by the client: the doom ending on both.
# Run: mp_playtest.ps1 t234_mp_e2e_host t234_mp_e2e_client -Client2 t234_mp_e2e_leaver -Timeout 1100
# The horror-defeated ending is t230_mp_boss_finale_* (a run ends only once).

const TIMEOUT := 1050
const GadgetShop = preload("res://mods-unpacked/flantor-StoryMode/gamemode/gadget_shop.gd")
const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
const Bones = preload("res://mods-unpacked/flantor-StoryMode/data/bones.gd")
const Metal = preload("res://mods-unpacked/flantor-StoryMode/data/metal.gd")
const Runes = preload("res://mods-unpacked/flantor-StoryMode/pleas/runes.gd")
const Endings = preload("res://mods-unpacked/flantor-StoryMode/data/endings.gd")

const MONEY := "team1.inventory.money"
const TP := "team1.teleporter"
# A room under the dome: where the client's keeper flies home from.
const UNDER := Vector2i(0, 3)

var _held: Dictionary = {}


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


static func money() -> int:
	return int(Data.ofOr(MONEY, 0))


static func cost(id: String) -> int:
	var c = GameWorld.upgrades.get(id, {}).get("cost", {})
	return int(c.get("money", -1)) if c is Dictionary else -1


static func gadgets_bought() -> Array:
	return GameWorld.boughtUpgrades.filter(func(k): return GameWorld.upgrades.get(k, {}).get("type", "") == "gadget")


# Per-keeper and team shop facts, the same on every instance.
static func shop_facts() -> Dictionary:
	var f := {}
	for pid in ["player1", "player2"]:
		f[pid + " drill1"] = GameWorld.boughtUpgrades.has(pid + ".drill1")
		f[pid + " drill strength"] = float(Data.ofOr(pid + ".keeper1.drillStrength", -1.0))
		f[pid + " heat shield"] = int(Data.ofOr(pid + ".suit.heatshield", 0))
		f[pid + " suit blaster"] = GameWorld.boughtUpgrades.has(pid + ".suitblaster")
	f["second weapon"] = bool(Data.ofOr("team1.dome.secondaryweapon", false))
	f["health meter"] = GameWorld.boughtUpgrades.has("team1.domehealthmeter")
	f["metal bit"] = GameWorld.boughtUpgrades.has("team1." + Metal.DRILL_UPGRADE)
	f["gadgets"] = gadgets_bought().size()
	f["new gadget entries"] = GadgetShop.entries("team1").filter(func(e): return GameWorld.boughtUpgrades.has(e)).size()
	return f


# Map children with a Synchronizer child, by name and script (an RPC path
# names them, so host and client must agree).
static func synced_map_nodes() -> Array:
	var out: Array = []
	for c in Level.map.get_children():
		if c.has_node("Synchronizer"):
			out.append([str(c.name), str(c.get_script().resource_path) if c.get_script() else c.get_class(), Level.map.getTileCoord(c.global_position) if c is Node2D else null])
	return out


# A pause menu found open (one came up on the host in a run, cause unknown)
# takes the laser keys: close it and say so.
static func close_pause(h, who: String) -> void:
	for i in 3:
		var menus: Array = h.get_tree().root.find_children("*", "", true, false).filter(func(n): return n.get_script() != null and n.get_script().resource_path == "res://content/pause/PauseMenu.gd" and n.is_visible_in_tree())
		if menus.is_empty():
			return
		h.note(who + ": a pause menu was open; closing it", i)
		await h.press("escape")
		await h.wait(1.0)


static func station(dome, i: int):
	return dome.stations[i] if dome.stations.size() > i else null


# Takes a dome station with keeper `k` (a choice may come up: ui_left as t230).
static func enter_station(h, st, k) -> bool:
	st.useHit(k)
	for i in 14:
		await h.wait(0.5)
		if not GameWorld.paused and k.isInsideStation and i > 0:
			break
		await h.press("ui_left")
	return k.isInsideStation


static func aim_point(m) -> Vector2:
	var box = m.get_node_or_null("HitboxDefault")
	return m.to_global(box.position) if box != null else m.global_position


static func monsters(h) -> Array:
	return h.get_tree().get_nodes_in_group("team1-monster").filter(func(m): return is_instance_valid(m) and not m.get("dead") and m.currentHealth > 0)


static func hold(h, held: Dictionary, action: String, on: bool) -> void:
	if on and not held.get(action, false):
		h.down(action)
	elif not on and held.get(action, false):
		h.up(action)
	held[action] = on


# One frame of aiming `gun` at the monster nearest its aim, firing when close.
static func fight_step(h, gun, held: Dictionary) -> void:
	var origin: Vector2 = gun.global_position
	var aim: Vector2 = Vector2.UP.rotated(gun.global_rotation)
	var best = null
	var best_a: float = 99.0
	for m in monsters(h):
		var a: float = aim.angle_to(aim_point(m) - origin)
		if absf(a) < absf(best_a):
			best = m
			best_a = a
	if best == null:
		for a in ["ui_left", "ui_right", "dome1_fire"]:
			hold(h, held, a, false)
		return
	var off: float = absf(best_a) * origin.distance_to(aim_point(best))
	hold(h, held, "ui_right", best_a > 0.0 and off > 4.0)
	hold(h, held, "ui_left", best_a < 0.0 and off > 4.0)
	hold(h, held, "dome1_fire", off < 14.0)


static func release(h, held: Dictionary) -> void:
	for a in ["ui_left", "ui_right", "dome1_fire"]:
		hold(h, held, a, false)


# Closes this player's beat boxes until the end screen is up.
static func to_end_screen(h, timeout: float) -> bool:
	var t0: float = h.now()
	while h.now() - t0 < timeout:
		if Level.stage.endingPanel != null:
			return true
		if h.beat_box() != null:
			await h.press("ui_select")
		await h.wait(0.7)
	return Level.stage.endingPanel != null


func _client_keeper():
	for k in Keepers.getAll():
		if k.peerId != 1:
			return k
	return null


func _near(k, tile: Vector2i, r: int = 2) -> bool:
	if k == null:
		return false
	var t: Vector2i = Level.map.getTileCoord(k.global_position)
	return absi(t.x - tile.x) <= r and absi(t.y - tile.y) <= r


# The client's keeper picked `drops` up where they were (checked on the
# client) and teleports to the room under the dome. That jump drops them on the
# host, so the host brings them along (the trip through the mine) and has the
# keeper pick them up again; then the client flies up into the dome.
func _bring_home(h, drops: Array, what: String) -> void:
	var there: bool = await h.until(func(): return _near(_client_keeper(), UNDER, 1), 40.0)
	h.check("%s: the client's keeper is under the dome" % what, there, keeper_rows(h))
	var ck = _client_keeper()
	h.note("%s: the host's copy of the client keeper carries" % what, ck.carriedCarryables.map(func(c): return c.type if is_instance_valid(c) else null))
	# The long teleport breaks the carry on the host (all or some of it): pick
	# up again what fell off.
	for d in drops:
		if is_instance_valid(d) and not d.absorbed:
			d.teleport(ck.global_position + Vector2(randf_range(-4, 4), 4))
			await h.frames(2)
			if not ck.carriedCarryables.has(d):
				Level.drops.network_pickup(d, ck.playerId)
	await h.wait(1.0)
	h.check("%s: the host's copy of the client keeper carries them" % what, ck.carriedCarryables.size() == drops.size(), ck.carriedCarryables.map(func(c): return c.type if is_instance_valid(c) else null))
	share("fly_" + what, true)


func _clear_of_hazards(c: Vector2i, r: int) -> bool:
	var lava = Level.map.get_node("StoryLavaField")
	var gas = Level.map.get_node("StoryGasField")
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var t := c + Vector2i(dx, dy)
			if lava.magma.has(t) or lava.mass.has(t) or gas.rock.has(t) or gas.mass.has(t):
				return false
	return true


func run(h) -> void:
	if not await host_start(h, 3):
		return
	var dome = Level.getDome("team1")
	Data.apply(MONEY, 100000)
	Data.apply("team1.inventory.water", 40)
	Data.apply("team1.inventory.sand", 5)
	await h.wait(2.0)
	h.note("start", shop_facts())

	# ---- 1. A second client buys the Teleporter (New Gadget I) and leaves.
	var cands: Array = GadgetShop.candidates("team1", "player1")
	h.check("the Teleporter is a gadget-shop candidate", cands.has(TP), cands)
	var others: Array = cands.filter(func(c): return c != TP)
	var n: int = GadgetShop.offer_count("team1")
	Data.apply("team1.story.gadgetoffers", ",".join([TP] + others.slice(0, n - 1)))
	var entries: Array = GadgetShop.entries("team1")
	var m0: int = money()
	share("leaver_go", true)
	var tp: bool = await h.until(func(): return GameWorld.boughtUpgrades.has(TP) and GameWorld.boughtUpgrades.has(entries[0]), 90.0)
	h.check("the second client bought the Teleporter with New Gadget I", tp and m0 - money() == cost(entries[0]), {"paid": m0 - money(), "price": cost(entries[0])})
	await h.shot("host_teleporter")
	var left: bool = await h.until(func(): return Network.clients.size() == 1, 60.0)
	h.check("the second client left; one client stays", left, Network.clients.size())
	await h.wait(4.0)
	h.note("keepers after the leave", keeper_rows(h))
	h.check("two keepers left in the run", Keepers.getAll().size() == 2, keeper_rows(h))
	var ck = _client_keeper()
	h.check("the staying client's keeper is player2", ck != null and ck.playerId == "player2", keeper_rows(h))
	h.check("the leaver's open shop choice is dropped on the host", not Level.stage.story_shop.has("player3"), Level.stage.story_shop)
	await h.shot("host_after_leave")

	# ---- 2. Selling as the host: iron at the dome.
	m0 = money()
	await h.deliver("iron", 3)
	var iron: int = Minerals.value_of("iron")
	var sold: bool = await h.until(func(): return money() - m0 == 3 * iron, 15.0)
	h.check("host sells 3 iron for $%d" % (3 * iron), sold, money() - m0)
	await h.wait(0.5)
	await h.shot("host_sale")
	share("host_sold", money())

	# ---- 3. Selling as the client: it carries iron and B1's bones home.
	var td = Level.map.tileData
	var bones_at = null
	for p in td.get_meta("story_bones", []):
		if int(p[2]) == 0:
			bones_at = Vector2i(int(p[0]), int(p[1]))
	h.check("B1 has bones", bones_at != null)
	if bones_at == null:
		return
	await h.dig_room(UNDER + Vector2i(-1, -2), UNDER + Vector2i(1, 1))
	await h.dig_room(bones_at + Vector2i(-2, -3), bones_at + Vector2i(2, -1))
	await h.reveal([bones_at])
	share("bones", [bones_at.x, bones_at.y])
	var there: bool = await h.until(func(): return _near(_client_keeper(), bones_at + Vector2i(0, -1)), 60.0)
	h.check("the client's keeper is at the bones", there, keeper_rows(h))
	m0 = money()
	Level.map.destroyTile("team1", "", Level.map.getTile(Vector2(bones_at)))
	await h.wait(0.5)
	var bones_drop = null
	for d in Level.drops.find_children("*", "", true, false):
		if d.get("type") == Bones.TYPE and not d.absorbed:
			bones_drop = d
	h.check("the bones drop", bones_drop != null)
	if bones_drop != null:
		Level.drops.network_pickup(bones_drop, "player2")
	var at_pos: Vector2 = _client_keeper().global_position
	var carried: Array = [bones_drop]
	for i in 3:
		carried.append(Level.drops.network_spawn({"type": "iron", "position": at_pos + Vector2(randf_range(-4, 4), -6), "carriers": ["player2"], "team": "team1"}))
		await h.frames(4)
	share("carry_home", true)
	await _bring_home(h, carried, "sale")
	var want: int = 3 * iron + Bones.value_for(0)
	sold = await h.until(func(): return money() - m0 >= want, 30.0)
	h.check("the client's keeper sells 3 iron and the bones for $%d" % want, sold and money() - m0 == want, {"got": money() - m0, "want": want})
	await h.wait(1.0)
	await h.shot("host_client_sale")
	share("client_sold", money())

	# ---- 4. A translator: the client opens the B2 chamber and carries it home.
	var chamber = null
	var chambers: Array = []
	for c in Level.map.find_children("*", "", true, false):
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("TranslatorChamber.gd"):
			chambers.append(c)
	chambers.sort_custom(func(a, b): return a.global_position.y < b.global_position.y)
	chamber = chambers[0] if chambers.size() > 0 else null
	h.check("a translator chamber", chamber != null, chambers.size())
	if chamber == null:
		return
	var ch_at: Vector2i = Level.map.getTileCoord(chamber.global_position + Vector2(12, 12))
	await h.dig_room(ch_at + Vector2i(-3, -3), ch_at + Vector2i(4, -1))
	var cover: Array = [ch_at, ch_at + Vector2i(1, 0), ch_at + Vector2i(0, 1), ch_at + Vector2i(1, 1)]
	await h.reveal(cover)
	share("chamber", [ch_at.x, ch_at.y])
	there = await h.until(func(): return _near(_client_keeper(), ch_at + Vector2i(0, -1)), 60.0)
	h.check("the client's keeper is at the chamber", there, keeper_rows(h))
	for c: Vector2i in cover:
		var t = Level.map.getTile(Vector2(c))
		if t != null:
			Level.map.destroyTile("team1", "", t)
	var opened: bool = await h.until(func(): return chamber.currentState == chamber.State.OPEN, 10.0)
	h.check("the chamber opens", opened, chamber.currentState)
	share("chamber_open", true)
	var tdrops: Array = []
	await h.until(func():
		tdrops.clear()
		tdrops.append_array(Level.drops.find_children("*", "", true, false).filter(func(d): return d.get("type") == "translator" and not d.absorbed))
		return tdrops.size() > 0, 30.0)
	h.check("the client's hit spawns the translator on the host", tdrops.size() == 1, tdrops.size())
	await _bring_home(h, tdrops, "translator")
	var installed: bool = await h.until(func(): return int(Data.ofOr("team1.inventory.translator", 0)) >= 1, 60.0)
	h.check("the client's translator is installed: plea stage 1", installed and Runes.stage() == 1, [Data.ofOr("team1.inventory.translator", 0), Runes.stage()])
	await h.wait(1.0)
	await h.shot("host_translator")
	share("translated", Runes.stage())

	# ---- 5. The shop: the host's own drill; the client buys the rest.
	Data.apply(MONEY, 200000)
	await h.wait(1.0)
	var before: Dictionary = shop_facts()
	m0 = money()
	var ok: bool = await h.buy("drill1")
	await h.wait(1.0)
	var after: Dictionary = shop_facts()
	h.check("the host's drill upgrade is the host's keeper's only", ok and after["player1 drill1"] and not after["player2 drill1"] and after["player1 drill strength"] > before["player1 drill strength"] and after["player2 drill strength"] == before["player2 drill strength"], [before, after])
	h.check("and costs its price", m0 - money() == cost("player1.drill1"), [m0 - money(), cost("player1.drill1")])
	share("shop_go", after)
	var done: bool = await h.until(func(): return GameWorld.boughtUpgrades.has("team1.domesecondweapon") and GameWorld.boughtUpgrades.has("player2.storyheatshield4"), 120.0)
	await h.wait(2.0)
	var f: Dictionary = shop_facts()
	h.note("shop facts on the host", f)
	h.check("the client's buys landed", done, f)
	h.check("the client's drill is the client's keeper's only", f["player2 drill1"] and f["player2 drill strength"] > after["player2 drill strength"] and f["player1 drill strength"] == after["player1 drill strength"], [after, f])
	h.check("Heat Shielding IV is the client's keeper's, none for the host's", f["player2 heat shield"] == 4 and f["player1 heat shield"] == 0, f)
	h.check("the Suit Blaster is the client's keeper's only", f["player2 suit blaster"] and not f["player1 suit blaster"], f)
	h.check("the team's Health Meter and Second Weapon: the secondary station has a laser", f["health meter"] and f["second weapon"] and station(dome, 1) != null and station(dome, 1).getControlledWeapons().size() >= 1, f)
	share("shop_facts", f)

	# ---- 6. The gadget shop: the client through the shop panel (New Gadget II).
	var g0: int = gadgets_bought().size()
	m0 = money()
	share("panel_go", true)
	var panel_ok: bool = await h.until(func(): return GameWorld.boughtUpgrades.has(entries[1]), 90.0)
	await h.wait(2.0)
	h.check("the client's shop-panel pick bought New Gadget II and one gadget", panel_ok and m0 - money() == cost(entries[1]) and gadgets_bought().size() == g0 + 1, {"paid": m0 - money(), "price": cost(entries[1]), "gadgets": gadgets_bought()})
	# Host and client at once (New Gadget III; IV is left).
	var shop_done: bool = await h.until(func(): return Level.stage.story_shop.is_empty(), 30.0)
	h.check("the client's panel choice is closed on the host", shop_done, Level.stage.story_shop)
	g0 = gadgets_bought().size()
	m0 = money()
	share("both_go", true)
	Level.stage.openStoryGadgetChoice("team1", "player1")
	var both: bool = await h.until(func(): return Level.stage.story_shop.has("player1") and Level.stage.story_shop.has("player2") and _host_popup_shown().size() > 0, 30.0)
	await h.wait(2.0)
	var offers: Array = Array(str(Data.ofOr("team1.story.gadgetoffers", "")).split(",", false))
	h.check("both gadget choices are open at once, one set of offers", both and _sorted(_host_popup_shown()) == _sorted(offers), {"shop": Level.stage.story_shop, "host shown": _host_popup_shown(), "offers": offers})
	share("both_offers", offers)
	await h.wait(2.0)
	await h.shot("host_both_open")
	var pick: String = offers[0] if offers.size() > 0 else ""
	Level.stage.onGadgetSelected(pick, CONST.GADGET, "player1", "team1")
	var picked: bool = await h.until(func(): return GameWorld.boughtUpgrades.has(pick) and GameWorld.boughtUpgrades.has(entries[2]), 10.0)
	h.check("the host's pick buys New Gadget III", picked, pick)
	share("host_picked", pick)
	# The client then picks another of the same offers.
	await h.until(func(): return not Level.stage.story_shop.has("player2"), 30.0)
	await h.wait(3.0)
	var spent: int = m0 - money()
	var new_entries: Array = entries.slice(2).filter(func(e): return GameWorld.boughtUpgrades.has(e))
	var priced: int = 0
	for e in new_entries:
		priced += cost(e)
	var g_new: int = gadgets_bought().size() - g0
	h.note("both at once", {"spent": spent, "entries": new_entries, "gadgets added": g_new, "offers now": Data.ofOr("team1.story.gadgetoffers", "")})
	h.check("both at once: every gadget added was paid for by one entry, nothing charged twice", spent == priced and g_new == new_entries.size(), {"spent": spent, "priced": priced, "gadgets": g_new, "entries": new_entries})
	h.check("both choices closed on the host", Level.stage.story_shop.is_empty(), Level.stage.story_shop)
	share("both_result", {"entries": new_entries.size(), "gadgets": gadgets_bought().size(), "money": money()})

	# ---- 7. A metal gate: the client's keeper blasts it. Then the Metal Bit.
	var gate = null
	var gcells: Array = td.get_resource_cells_by_id(Metal.GATE_ID)
	gcells.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and absi(a.x) < absi(b.x)))
	for c0 in gcells:
		var c := Vector2i(c0)
		if absi(c.x) > 2 and td.get_resourcev(c + Vector2i(0, -1)) != Metal.GATE_ID and _clear_of_hazards(c, 4):
			gate = c
			break
	h.check("a gate cell clear of lava and gas", gate != null, gcells.size())
	if gate != null:
		await h.dig_room(gate + Vector2i(-1, -3), gate + Vector2i(1, -1))
		await h.reveal([gate])
		share("gate", [gate.x, gate.y])
		there = await h.until(func(): return _near(_client_keeper(), gate + Vector2i(0, -1)), 60.0)
		h.check("the client's keeper stands on the gate", there, keeper_rows(h))
		var broke: bool = await h.until(func(): return td.get_resourcev(gate) != Metal.GATE_ID, 40.0)
		h.check("the client's Suit Blaster breaks the gate tile on the host", broke, td.get_resourcev(gate))
		await h.wait(1.0)
		h.note("map nodes with a Synchronizer (host)", synced_map_nodes())
		share("gate_broken", broke)
	GameWorld.serverAddUpgrade("drill", "team1")
	await h.wait(3.0)
	m0 = money()
	share("metalbit_go", true)
	var bit: bool = await h.until(func(): return GameWorld.boughtUpgrades.has("team1." + Metal.DRILL_UPGRADE), 40.0)
	h.check("the client bought the Metal Bit for the Mine Driller", bit and m0 - money() == cost("team1." + Metal.DRILL_UPGRADE), [m0 - money(), cost("team1." + Metal.DRILL_UPGRADE)])

	# ---- 8. A monster wave, fought from both stations.
	await h.until(func(): return _client_keeper().isInsideDome, 60.0)
	h.keeper().teleport(dome.global_position + Vector2(0, -8))
	h.snap_camera()
	await h.wait(1.0)
	var st0 = station(dome, 0)
	await close_pause(h, "host")
	var in0: bool = await enter_station(h, st0, h.keeper())
	h.check("the host's keeper takes the main station", in0)
	share("wave_go", true)
	var cin: bool = await h.until(func(): return _client_keeper() != null and _client_keeper().isInsideStation, 40.0)
	h.check("the client's keeper is in the secondary station (on the host)", cin, keeper_rows(h))
	Data.apply("team1.dome.maxHealth", 1000000)
	Data.apply("team1.dome.health", 1000000)
	h.enable_waves()
	GameWorld.runStarted = true
	Data.apply("team1.monsters.wavecooldown", 2)
	var came: bool = await h.until(func(): return Data.ofOr("team1.monsters.wavepresent", false) and monsters(h).size() > 0, 90.0)
	h.check("a wave comes", came)
	share("wave_on", true)
	# The client fires alone first: the host's keeper sits at its laser idle.
	var hp: Dictionary = {}
	var dmg := 0.0
	var t0: float = h.now()
	while h.now() - t0 < 60.0 and dmg <= 0.0:
		for m in monsters(h):
			var u: int = m.UID
			if hp.has(u) and m.currentHealth < hp[u]:
				dmg += hp[u] - m.currentHealth
			hp[u] = m.currentHealth
		await h.frames(1)
		if h.now() - t0 > 2.0 and not _held.get("shot", false):
			_held["shot"] = true
			await h.shot("host_wave_client_fires")
	h.check("the client's laser hurts the wave on the host (the host's laser idle)", dmg > 0.0, dmg)
	# Then both fire until the wave is gone.
	await close_pause(h, "host")
	share("host_fires", true)
	var gun0 = st0.getControlledWeapons()[0] if st0.getControlledWeapons().size() > 0 else null
	t0 = h.now()
	var killed0: int = monsters(h).size()
	while h.now() - t0 < 50.0 and Data.ofOr("team1.monsters.wavepresent", false):
		if gun0 != null:
			fight_step(h, gun0, _held)
		await h.frames(2)
		if h.now() - t0 > 1.0 and not _held.get("shot2", false):
			_held["shot2"] = true
			await h.shot("host_wave_both_fire")
	release(h, _held)
	var by_lasers: bool = not Data.ofOr("team1.monsters.wavepresent", false)
	h.note("wave", {"monsters at start": killed0, "left": monsters(h).size(), "cleared by the lasers": by_lasers})
	if not by_lasers:
		for mm in h.get_tree().get_nodes_in_group("monster-manager"):
			mm.instantlyKillWave()
	var gone: bool = await h.until(func(): return not Data.ofOr("team1.monsters.wavepresent", false), 40.0)
	h.check("the wave ends", gone)
	h.disable_waves()
	share("wave_over", {"health": float(Data.ofOr("team1.dome.health", 0))})
	await h.wait(2.0)
	st0.useHit(h.keeper())
	await h.wait(1.0)

	# ---- 9. Retire Rich, bought by the client: the doom ending on both.
	Data.apply(MONEY, 1000000)
	share("rich", true)
	var ending: bool = await h.until(func(): return Level.mode.is_ending(), 40.0)
	h.check("the client's Retire Rich starts the ending on the host", ending)
	var panel: bool = await to_end_screen(h, 180.0)
	h.check("end screen on the host, the doom ending's", panel and GameWorld.won and Level.stage.endingPanel.titleLabel.text == Endings.DOOM_TITLE, [GameWorld.won, Level.stage.endingPanel.titleLabel.text if panel else null])
	await h.wait(2.0)
	await h.shot("host_end_screen")
	h.check("one end screen here", Level.mode.end_screens == 1, Level.mode.end_screens)
	await host_wait_clients_left(h, 120.0)


func _host_popup_shown() -> Array:
	var p = Level.stage.currentGadgetPopupByPlayerId.get("player1", null)
	return p.offersById.keys() if p != null and is_instance_valid(p) and p.is_inside_tree() else []


static func _sorted(a: Array) -> Array:
	var out: Array = a.duplicate()
	out.sort()
	return out
