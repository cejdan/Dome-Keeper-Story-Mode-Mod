extends RefCounted

# Dev-only helpers for the `--boss` commands (#170): the gear a keeper really
# has by the time the boss is reached, and a drilled way home for the chase.

# Every upgrade a keeper at the boss has bought: all of the drill and the
# jetpack (or the other keepers' like lines), and a dome that can fight (DOME_GEAR: Laser IV, faster aim, more
# health on the laser dome; the same kind of thing on the others).
const GEAR: Array = [
	"drill1", "drill2", "drill3", "drill4",
	"jetpackspeed1", "jetpackspeed2", "jetpackspeed3", "jetpackspeed4",
	"jetpackstrength1", "jetpackstrength2", "jetpackstrength3", "jetpackstrength4",
	# The other keepers' mining, movement and carry lines (#297); each keeper
	# gets only its own tree's (the ids are per keeper).
	"keeper2pinballdamage1", "keeper2pinballdamage2", "keeper2pinballdamage3", "keeper2pinballdamage4",
	"keeper2movement1", "keeper2movement2", "keeper2movement3", "keeper2movement4",
	"keeper2bundle1", "keeper2bundle2", "keeper2bundle3", "keeper2bundle4",
	"keeper2rotationalmining1", "keeper2rotationalmining2",
	"keeper3kunaidamage4", "keeper3kunaicooldown1", "keeper3kunaicooldown2", "keeper3kunaicooldown3",
	"keeper3doublejump", "keeper3slidecontrol", "keeper3quadjump", "keeper3aerialmastery",
	"keeper3carrylimit1", "keeper3carrylimit2", "keeper3carrylimit3",
	"keeper4punch1", "keeper4punch2", "keeper4punch3", "keeper4punch4",
	"keeper4speed1", "keeper4speed2", "keeper4speed3",
	"domehealthmeter",
]

# The dome's own share of GEAR, by dome (#269): its weapon's strength tiers and
# aim, and its health upgrades. The laser dome's is the original (Laser IV).
const DOME_GEAR: Dictionary = {
	"dome1": ["laserstrength1", "laserstrength2", "laserstrength3", "laserstrength4",
		"lasermove1", "lasermove2", "laseraimline", "dome1health1", "dome1health2"],
	"dome2": ["swordblade1", "swordlargeblade1", "swordlargeblade2", "swordlargeblade3",
		"swordstabfast1", "swordstabfast2", "swordaimline", "dome2health1", "dome2health2"],
	"dome3": ["artillerydirecthit1", "artillerydirecthit2", "artillerydirecthit3", "artillerydirecthit4",
		"artillerysplash1", "artillerysplash2", "artillerymachinegun1", "dome3health1", "dome3health2"],
	"dome4": ["teslapower1", "teslapower2", "teslapower3", "teslapower4",
		"teslaspeed1", "teslaspeed2", "teslaautoaim", "dome4health1", "dome4health2"],
	"dome5": ["turretslot1machinegun", "turretslot2machinegun", "dome5health1", "dome5health2"],
}


static func dome_id() -> String:
	if Level.loadout != null and Level.loadout.domes.size() > 0:
		return Level.loadout.domes.front().domeId
	return "dome1"


# Gives every keeper GEAR for free (#265: the keeper upgrades are per player,
# so each keeper gets its own drill, jetpack, Heat Shielding IV and Suit
# Blaster; the team's dome upgrades once). Returns the ids that were added.
# `laser_level` 0..4 stops the laser's strength there (playtests of weaker domes).
static func give_gear(extra: Array = [], laser_level: int = 4) -> Array:
	var KeeperUpgrades = load("res://mods-unpacked/flantor-StoryMode/gamemode/keeper_upgrades.gd")
	var keepers: Array = Keepers.getAll().filter(func(k): return k != null and is_instance_valid(k))
	var given: Array = []
	for raw: String in GEAR + DOME_GEAR.get(dome_id(), DOME_GEAR["dome1"]) + extra:
		if raw.begins_with("laserstrength") and int(raw.substr(13)) > laser_level:
			continue
		for keeper in keepers:
			var id: String = raw
			if not GameWorld.upgrades.has(id):
				for prefix: String in [keeper.teamId + ".", keeper.playerId + "."]:
					if GameWorld.upgrades.has(prefix + raw):
						id = prefix + raw
						break
			if not GameWorld.upgrades.has(id) or GameWorld.boughtUpgrades.has(id):
				continue
			GameWorld.serverAddUpgrade(id, keeper.teamId)
			if not given.has(raw):
				given.append(raw)
	for keeper in keepers:
		if not KeeperUpgrades.give_heat_shield(keeper.playerId, KeeperUpgrades.TIERS).is_empty() and not given.has("heatshield4"):
			given.append("heatshield4")
		# The Suit Blaster is a keeper gadget, kept under the player's own id.
		var blaster: String = keeper.playerId + ".suitblaster"
		if not GameWorld.boughtUpgrades.has(blaster):
			GameWorld.serverAddUpgrade(blaster, keeper.teamId)
			if not given.has("suitblaster"):
				given.append("suitblaster")
	KeeperUpgrades.mark_blaster_entries()
	return given


# The cells of a winding shaft, two tiles wide, from the top of the boss
# chamber `ch` up to the dome's own shaft: the way a player would have drilled
# down. Bottom to top. The same seed gives the same path. It keeps clear of
# the cells in `avoid` (the enclosed lava pools, which would flood it).
static func path_cells(ch: Rect2i, path_seed: int, avoid: Dictionary = {}) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = path_seed
	var cells: Array = []
	var x: int = ch.position.x + ch.size.x / 2 - 4
	var y: int = ch.position.y - 1
	var reach: int = maxi(3, ch.size.x / 2 - 2)
	var run: int = rng.randi_range(5, 10)
	while y >= 1:
		cells.append(Vector2i(x, y))
		cells.append(Vector2i(x + 1, y))
		run -= 1
		var to: int = x
		if y <= 12:
			# The last stretch comes in under the dome.
			if run <= 0:
				to = 0
		elif not _clear(x, y - 1, avoid):
			# A pool ahead: step aside to the nearest clear column.
			for d in range(1, reach * 2):
				var found: bool = false
				for side: int in [1, -1]:
					var nx: int = x + d * side
					if nx >= -reach and nx < reach and _clear(nx, y - 1, avoid) and _row_clear(x, nx, y, avoid):
						to = nx
						found = true
						break
				if found:
					break
			run = rng.randi_range(5, 12)
		elif run <= 0:
			run = rng.randi_range(5, 12)
			var want: int = clampi(x + rng.randi_range(2, 6) * (1 if rng.randf() < 0.5 else -1), -reach, reach - 1)
			if _clear(want, y - 1, avoid) and _row_clear(x, want, y, avoid):
				to = want
		var step: int = signi(to - x)
		while x != to:
			x += step
			cells.append(Vector2i(x, y))
			cells.append(Vector2i(x + 1, y))
		y -= 1
	return cells


# Is the two-wide column at x free of `avoid` for the next rows up from y?
static func _clear(x: int, y: int, avoid: Dictionary) -> bool:
	for dy in 5:
		for dx in range(-1, 3):
			if avoid.has(Vector2i(x + dx, y - dy)):
				return false
	return true


static func _row_clear(x0: int, x1: int, y: int, avoid: Dictionary) -> bool:
	for x in range(mini(x0, x1) - 1, maxi(x0, x1) + 3):
		for dy in range(-1, 2):
			if avoid.has(Vector2i(x, y + dy)):
				return false
	return true


# Every cell of the map's enclosed lava pools, as a set.
static func pool_cells() -> Dictionary:
	var out: Dictionary = {}
	for pool in Level.map.tileData.get_meta("story_pools", []):
		for c in pool:
			out[Vector2i(c)] = true
	return out


# Opens `cells` in the live map.
static func carve(cells: Array) -> void:
	var map = Level.map
	map.tileCoordsToReveal.append_array(cells)
	map.floodRevealTiles()
	if map.has_method("finish_flood"):
		map.finish_flood()
	var v: Array = []
	for c: Vector2i in cells:
		v.append(Vector2(c))
	# Online, a client breaks only tiles it has made: reveal them there first (#230).
	if Network.multiplayer_mode != Network.MultiplayerMode.OFFLINE_SINGLEPLAYER and map.multiplayer.is_server():
		for c: Vector2 in v:
			map.networkRevealTile(c, 0.0)
	map.freeTiles(v)


# Anything freeTiles would not take: metal and the gate (broken the way a
# Suit Blaster blast breaks them) and special tiles (destroyed outright).
# Call a few frames after carve().
static func carve_leftovers(cells: Array) -> int:
	var metal = load("res://mods-unpacked/flantor-StoryMode/data/metal.gd")
	var n: int = 0
	for c: Vector2i in cells:
		var t = Level.map.getTile(Vector2(c))
		if t == null or not is_instance_valid(t) or Level.map.is_tile_empty(c):
			continue
		n += 1
		if metal.is_metal(t.type):
			metal.record_circle(Vector2(c), 0.5)
			t.exploded = true
			t.hit(Vector2.UP, t.health + 1.0, "team1")
		else:
			Level.map.destroyTile("team1", "", t)
	return n


# The path's cells that are still rock.
static func blocked(cells: Array) -> Array:
	return cells.filter(func(c): return not Level.map.is_tile_empty(c))
