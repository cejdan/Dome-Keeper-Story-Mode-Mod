extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# #297: a Story run with the Assessor (keeper2); t297_keeper3 and t297_keeper4
# extend this with another keeper (`-Extra "--keeper=keeper1"` runs it with the
# Engineer). The shop shows this keeper's own tree in money, with Story Mode's
# Heat Shielding and Suit Blaster in it and no other keeper's entries; the
# keeper buys its first mining upgrade, Heat Shielding I and the Suit Blaster
# with money, digs down with its own tools, blasts a metal gate open and gets
# through it. Then a note on how it climbs out of a deep shaft (a finding for
# the user, not a check).

const TIMEOUT := 300
const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")
const Prices = preload("res://mods-unpacked/cejdan-StoryMode/data/prices.gd")
const LavaData = preload("res://mods-unpacked/cejdan-StoryMode/data/lava.gd")
const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")

const KEEPERS := ["keeper1", "keeper2", "keeper3", "keeper4"]
# Each keeper's first mining upgrade (off its root, limit `mining`).
const FIRST_MINING := {
	"keeper1": "drill1", "keeper2": "keeper2pinballdamage1",
	"keeper3": "keeper3kunaidamage4", "keeper4": "keeper4punch1",
}
const STORY_ENTRIES := ["storyheatshield1", "storysuitblaster"]


func keeper_id() -> String:
	return "keeper2"


func boot() -> Dictionary:
	return {"seed": 12345, "keeper": keeper_id()}


# ---------------------------------------------------------------- shared helpers
# (t297_mp_host / t297_mp_client use these too)

static func short(id: String) -> String:
	var i: int = id.find(".")
	return id.substr(i + 1) if i >= 0 else id


# The open shop popup of player `pid`.
static func shop_of(h, pid: String):
	for n in h.get_tree().root.find_children("*", "", true, false):
		if is_instance_valid(n) and n.has_method("buyUpgrade") and n.has_method("updateCostLabels") and n.get("playerId") == pid and n.get("isIn") == true and n.find_child("TechTree") != null:
			return n
	return null


static func open_shop(h, k):
	Level.stage.startUpgradesInput(k)
	await h.until(func():
		var s = shop_of(h, k.playerId)
		return s != null and s.animationDone, 5.0)
	await h.wait(0.5)
	return shop_of(h, k.playerId)


static func tracks(shop) -> Array:
	return [] if shop == null else shop.find_child("TechTree").get_node("Tracks").get_children()


# The Story Mode price of a tree entry (its short id): Heat Shielding from the
# lava data, the Suit Blaster entry from the yaml, the rest from prices.gd.
static func story_price(raw: String) -> int:
	if raw.begins_with("storyheatshield"):
		return int(LavaData.HEAT_SHIELD_PRICES[int(raw.substr(15)) - 1])
	if raw.begins_with("story"):
		return int(Data.upgrades[raw]["cost"].get("money", -1))
	return int(Prices.PRICES.get(raw, -1))


# Checks player `k`'s open shop: one keeper track, rooted on k's keeper, with
# the Story Mode entries in it, every entry priced in money at its Story price,
# no other keeper's entries anywhere. Returns what it saw.
static func check_keeper_shop(h, k, shop, who: String = "") -> Dictionary:
	var kid: String = k.techId
	var root: String = k.playerId + "." + kid
	var roots: Array = tracks(shop).map(func(t): return str(t.rootTechId))
	var track = null
	for t in tracks(shop):
		if t.rootTechId == root:
			track = t
	var panels: Array = [] if track == null else track.techPanels.keys().map(func(x): return str(x))
	var out := {"roots": roots, "keeper track": panels}
	h.note(who + "shop tracks", roots)
	h.note(who + "keeper track (%s)" % root, panels)
	h.check(who + "the shop has a track for this player's %s" % kid, track != null, roots)
	h.check(who + "no track for another keeper", roots.filter(func(r): return short(r) in KEEPERS and r != root).is_empty(), roots)
	for raw in STORY_ENTRIES:
		h.check(who + "%s sits in the %s track" % [raw, kid], panels.has(k.playerId + "." + raw), panels)
	h.check(who + "%s's first mining upgrade is in it" % kid, panels.has(k.playerId + "." + FIRST_MINING[kid]), panels)
	var all_ids: Array = []
	for t in tracks(shop):
		all_ids.append_array(t.techPanels.keys().map(func(x): return str(x)))
	h.check(who + "no other player's entries in this shop", not all_ids.any(func(i): return i.begins_with("player") and not i.begins_with(k.playerId + ".")), all_ids.filter(func(i): return i.begins_with("player")))
	# Prices, panel by panel.
	var wrong: Array = []
	var prices: Dictionary = {}
	for id: String in panels:
		if id == root:
			continue
		var cost: Dictionary = GameWorld.upgrades.get(id, {}).get("cost", {})
		var raw: String = short(id)
		prices[raw] = cost
		if not cost.has("money") or cost.has("iron") or int(cost["money"]) != story_price(raw):
			wrong.append([raw, cost, story_price(raw)])
	out["prices"] = prices
	h.note(who + "keeper track prices", prices)
	h.check(who + "every entry in the %s track costs its Story Mode money price (%d entries)" % [kid, prices.size()], wrong.is_empty() and prices.size() >= 3, wrong)
	return out


# Focuses panel `id` in `shop` (the view scrolls to it).
static func focus(h, shop, id: String) -> bool:
	for t in tracks(shop):
		if t.techPanels.has(id):
			InputSystem.grabFocus(t.techPanels[id])
			await h.wait(0.6)
			return true
	return false


# Breaks rock towards `dir` the keeper's own way for `sec` seconds: the
# Engineer drills and keeper4 punches by pushing into it, the Assessor shoots
# spheres, keeper3 throws its kunai.
static func dig(h, k, dir: String, sec: float) -> void:
	var t_end: float = h.now() + sec
	h.down(dir)
	match k.techId:
		"keeper2":
			while h.now() < t_end:
				h.down("keeper2_gravityball")
				await h.wait(0.6)
				h.up("keeper2_gravityball")
				await h.wait(0.4)
		"keeper3":
			# On the keyboard it throws where the mouse points, and only a held
			# throw keeps throwing (a tap drops what it carries).
			var v: Vector2 = {"ui_down": Vector2.DOWN, "ui_up": Vector2.UP, "ui_left": Vector2.LEFT, "ui_right": Vector2.RIGHT}[dir]
			h.aim_mouse(k.global_position + v * 40.0, k)
			h.down("keeper3_throw")
			while h.now() < t_end:
				await h.wait(0.2)
				h.aim_mouse(k.global_position + v * 40.0, k)
			h.up("keeper3_throw")
		_:
			await h.wait(sec)
	h.up(dir)


# Confirms any open full-screen video tutorial (vanilla shows keeper4's
# Beastmaster intro on its first run even with tutorials off, and it pauses
# the game). Returns the ids it closed.
static func close_tutorials(h) -> Array:
	var closed: Array = []
	for i in 6:
		var open: Array = h.get_tree().root.find_children("*", "", true, false).filter(func(n): return is_instance_valid(n) and n.has_method("_on_Button_pressed") and n.has_method("confirm") and n.is_visible_in_tree())
		if open.is_empty():
			break
		for n in open:
			closed.append(str(n.get("id")))
			n.confirm()
		await h.wait(0.8)
	if not closed.is_empty():
		h.note("closed vanilla tutorials", closed)
	return closed


# How many of `cells` still hold a tile.
static func standing(cells: Array) -> int:
	return cells.filter(func(c): return Level.map.getTile(Vector2(c)) != null).size()


# Carves a 3-wide shaft `depth` tiles tall with its bottom middle at
# `bottom`: plain rock first (no metal), then cleared, with any lava or gas in
# and around it taken out and the lava's flow frozen.
static func carve_shaft(h, bottom: Vector2i, depth: int) -> void:
	var td = Level.map.tileData
	var lava = Level.map.get_node_or_null("StoryLavaField")
	var gas = Level.map.get_node_or_null("StoryGasField")
	if lava != null:
		lava.freeze_flow = true
	var cells: Array = []
	for y in range(bottom.y - depth + 1, bottom.y + 1):
		for x in range(bottom.x - 1, bottom.x + 2):
			cells.append(Vector2i(x, y))
	for y in range(bottom.y - depth - 1, bottom.y + 3):
		for x in range(bottom.x - 3, bottom.x + 4):
			var t := Vector2i(x, y)
			if Metal.is_metal_id(td.get_resourcev(t)):
				td.set_resourcev(t, Data.TILE_DIRT_START)
			if lava != null:
				lava.mass.erase(t)
			if gas != null:
				gas.mass.erase(t)
	await h.reveal(cells)
	await h.clear_tiles(cells)


# Climbs out of a 3-wide shaft `depth` tiles deep, the keeper's own way, for
# `sec` seconds. Returns how many tiles it rose.
static func climb(h, k, bottom: Vector2i, sec: float) -> int:
	await h.teleport_tile(bottom, k)
	await h.wait(1.0)
	var y0: int = Level.map.getTileCoord(k.global_position).y
	var best: int = 0
	var t_end: float = h.now() + sec
	h.down("ui_up")
	while h.now() < t_end:
		if k.techId == "keeper3":
			# Jumps, and the rope shot straight up at the mouse.
			h.aim_mouse(k.global_position + Vector2(0, -120), k)
			h.down("keeper3_rope")
			h.down("keeper3_jump")
			await h.wait(0.25)
			h.up("keeper3_jump")
			await h.wait(0.15)
			h.up("keeper3_rope")
		else:
			await h.wait(0.2)
		best = maxi(best, y0 - Level.map.getTileCoord(k.global_position).y)
	h.up("ui_up")
	return best


# ---------------------------------------------------------------- the run

func run(h) -> void:
	h.disable_waves()
	var k = h.keeper()
	var kid: String = keeper_id()
	if Story.has_user_arg("keeper"):
		kid = Story.user_arg("keeper")
	h.check("the run's keeper is the %s" % kid, k != null and k.techId == kid, k.techId if k else null)
	h.check("this player has the storykeeper limit", GameWorld.isUpgradeLimitAvailable(k.playerId + ".storykeeper"))
	h.snap_camera()
	await h.wait(1.0)
	await close_tutorials(h)
	await h.shot("start")

	# ---- the shop
	h.set_inv("money", 3000)
	var shop = await open_shop(h, k)
	h.check("the shop opens", shop != null)
	if shop == null:
		return
	await close_tutorials(h)
	check_keeper_shop(h, k, shop)
	await focus(h, shop, k.playerId + "." + FIRST_MINING[kid])
	await h.shot("shop_keeper_track")
	await focus(h, shop, k.playerId + ".storyheatshield1")
	await h.shot("shop_heat_shielding")
	# The deepest panel of the track, for the rest of the tree.
	for t in tracks(shop):
		if t.rootTechId == k.playerId + "." + kid and t.panelsByTier.size() > 0:
			InputSystem.grabFocus(t.panelsByTier.back().front())
			await h.wait(0.6)
	await h.shot("shop_keeper_track_end")
	await close_tutorials(h)
	await h.press("ui_cancel")
	await h.wait(1.0)
	await close_tutorials(h)
	h.check("the game is not paused", not GameWorld.paused)

	# ---- buying with money
	var m0: int = int(h.inv("money"))
	var spent: int = 0
	for raw in [FIRST_MINING[kid], "storyheatshield1", "storysuitblaster"]:
		var id: String = k.playerId + "." + raw
		var price: int = story_price(raw)
		var ok: bool = await h.buy(id, k)
		await h.wait(0.5)
		h.check("bought %s for $%d" % [raw, price], ok and GameWorld.boughtUpgrades.has(id), GameWorld.upgrades.get(id, {}).get("cost", {}))
		spent += price
	h.check("the team paid $%d" % spent, int(h.inv("money")) == m0 - spent, [m0, h.inv("money")])
	h.check("this keeper is at Heat Shielding I", LavaData.shield_tier(k) == 1, Data.ofOr(k.playerId + ".suit.heatshield", null))
	var granted: bool = await h.until(func(): return GameWorld.boughtUpgrades.has(k.playerId + ".suitblaster"), 5.0)
	h.check("the Suit Blaster entry granted this keeper the Suit Blaster", granted)

	# ---- digging, its own way
	var room_a := Vector2i(-2, 6)
	var room_b := Vector2i(2, 8)
	await h.dig_room(room_a, room_b)
	var below: Array = []
	for y in range(room_b.y + 1, room_b.y + 6):
		for x in range(room_a.x, room_b.x + 1):
			below.append(Vector2i(x, y))
	await h.reveal(below)
	await h.teleport_tile(Vector2i(0, room_b.y), k)
	await h.wait(1.5)
	var before: int = standing(below)
	await dig(h, k, "ui_down", 12.0)
	await h.wait(1.0)
	var broken: int = before - standing(below)
	await h.shot("after_dig")
	h.note("dig", {"tiles below before": before, "broken": broken, "keeper": h.keeper_tile()})
	h.check("the keeper breaks rock below it in 12 s (%d tiles)" % broken, broken >= 2, broken)

	# ---- the gate (as t21_gate): drilling does nothing, one blast opens it
	var td = Level.map.tileData
	var gate: Array = td.get_resource_cells_by_id(Metal.GATE_ID)
	var x: int = 2
	var col: Array = []
	for c: Vector2i in gate:
		if c.x == x:
			col.append(c.y)
	col.sort()
	h.check("the run's map has a gate", not col.is_empty(), gate.size())
	if col.is_empty():
		return
	var top: int = int(col.front())
	await h.dig_room(Vector2i(x - 3, top - 3), Vector2i(x + 3, top - 1))
	var around: Array = []
	for yy in range(top - 4, top + 4):
		for xx in range(x - 6, x + 7):
			around.append(Vector2i(xx, yy))
	await h.reveal(around)
	await h.teleport_tile(Vector2i(x, top - 1), k)
	await h.wait(3.0)
	await h.shot("gate_from_above")
	await dig(h, k, "ui_down", 4.0)
	h.check("its own tools leave the gate", td.get_resourcev(Vector2i(x, top)) == Metal.GATE_ID)
	Data.apply(k.playerId + ".suitblaster.charge", 1.0)
	await h.teleport_tile(Vector2i(x, top - 1), k)
	await h.wait(1.0)
	await h.press("keeper_gadget1")
	await h.burst("blast", 16, 3)
	await h.wait(2.5)
	await h.shot("after_blast")
	var left: Array = col.filter(func(y): return td.get_resourcev(Vector2i(x, y)) == Metal.GATE_ID)
	h.check("one blast clears the gate in the keeper's column", left.is_empty(), {"column": col, "still metal": left})
	# Through it, with the keeper's own tools.
	var y_before: int = h.keeper_tile().y
	await dig(h, k, "ui_down", 30.0)
	var kt: Vector2i = h.keeper_tile()
	await h.shot("below_gate")
	h.note("through the gate", {"keeper": kt, "gate bottom": col.back(), "keeper y before": y_before})
	h.check("the keeper gets below the gate", kt.y > int(col.back()), {"keeper": kt, "gate bottom": col.back()})

	# ---- a finding, not a check: climbing out of a deep shaft
	var bottom := Vector2i(-14, 36)
	await carve_shaft(h, bottom, 16)
	var rose: int = await climb(h, k, bottom, 8.0)
	await h.shot("shaft_climb")
	h.note("climbing a 3-wide shaft 16 tiles deep in 8 s (finding)", {"rose tiles": rose, "keeper": h.keeper_tile()})
	h.snap("end", [])
