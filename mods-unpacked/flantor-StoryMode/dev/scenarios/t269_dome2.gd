extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 269: a Story run with the Sword Dome (t269_dome3..5 extend this with
# another dome). Start with that dome, deliver Story minerals at its shredder,
# buy the weapon's first upgrade with the money, check it applied, fight one
# wave from the station, check the dome gas haze takes this dome's shape, then
# save and load in the run (as t13_bronze) and check the dome, the upgrade and
# the money came back.

const TIMEOUT := 240
const Host = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t234_mp_e2e_host.gd")
static var _Host = Host  # calls go through this: lazy_preload makes const-preload calls slow
const Prices = preload("res://mods-unpacked/flantor-StoryMode/data/prices.gd")

# dome -> [first weapon upgrade, a Data key it changes, the scene]
const DOMES := {
	"dome1": ["laserstrength1", "laser.dps", "Dome1.tscn"],
	"dome2": ["swordblade1", "sword.slicedamage", "Dome2.tscn"],
	"dome3": ["artillerydirecthit1", "artillery.grenadedamage", "Dome3.tscn"],
	"dome4": ["teslapower1", "tesla.damage", "Dome4.tscn"],
	"dome5": ["turretslot1machinegun", "turrets.weapon1", "Dome5.tscn"],
}

var _held: Dictionary = {}


func dome_id() -> String:
	return "dome2"


func boot() -> Dictionary:
	return {"seed": 12345, "dome": dome_id()}


func _key() -> String:
	return "team1." + DOMES[dome_id()][1]


func _dome():
	return Level.domesByTeamId.get("team1")


# The Tesla Dome aims a reticle in two dimensions and shoots when a held
# charge is let go.
func _tesla(dome):
	for w in dome.find_children("*", "", true, false):
		if w.get_script() != null and str(w.get_script().resource_path).ends_with("weapons/tesla/Tesla.gd"):
			return w
	return null


func _tesla_step(h, tesla, fire: String) -> void:
	var r: Vector2 = tesla.reticle.global_position
	var best = null
	for m in _Host.monsters(h):
		if best == null or r.distance_to(_Host.aim_point(m)) < r.distance_to(_Host.aim_point(best)):
			best = m
	if best == null:
		return
	var off: Vector2 = _Host.aim_point(best) - r
	_Host.hold(h, _held, "ui_left", off.x < -4.0)
	_Host.hold(h, _held, "ui_right", off.x > 4.0)
	_Host.hold(h, _held, "ui_up", off.y < -4.0)
	_Host.hold(h, _held, "ui_down", off.y > 4.0)
	# Charge until full, then let go once the reticle is on it.
	_Host.hold(h, _held, fire, tesla.shotCharge < tesla.maxCharge or off.length() > 10.0)


func run(h) -> void:
	var d: String = dome_id()
	var up: String = DOMES[d][0]
	h.disable_waves()
	var dome = _dome()
	h.check("the run has the %s" % d, dome != null and str(dome.scene_file_path).ends_with(DOMES[d][2]), dome.scene_file_path if dome else null)
	h.snap_camera()
	await h.wait(1.0)
	await h.shot("start")

	# Story minerals at this dome's shredder pay money.
	var m0: int = int(h.inv("money"))
	await h.deliver("bronze", 10)
	await h.until(func(): return int(h.inv("money")) >= m0 + 10, 30.0)
	await h.wait(0.5)
	h.check("10 bronze at the shredder pay $10", int(h.inv("money")) == m0 + 10, [m0, h.inv("money")])

	# The weapon's first upgrade, bought with that money.
	var tid: String = "team1." + up if GameWorld.upgrades.has("team1." + up) else up
	var price: int = _Host.cost(tid)
	h.check("%s costs its Story price ($%d)" % [up, Prices.PRICES.get(up, -1)], price == int(Prices.PRICES.get(up, -2)), [tid, price])
	var before = Data.ofOr(_key(), null)
	var m1: int = int(h.inv("money"))
	var bought: bool = await h.buy(tid)
	await h.wait(0.5)
	var after = Data.ofOr(_key(), null)
	h.check("bought %s with money" % up, bought and GameWorld.boughtUpgrades.has(tid) and int(h.inv("money")) == m1 - price, [bought, m1, h.inv("money")])
	h.check("it applied (%s %s -> %s)" % [_key(), str(before), str(after)], after != null and str(after) != str(before), [before, after])

	# Dome gas (#213) draws its haze from this dome's own sprites.
	var gf = Level.map.get_node_or_null("StoryGasField")
	if gf != null and gf.dome != null:
		var keep: float = gf.dome.amount
		gf.dome.amount = 60.0 * load("res://mods-unpacked/flantor-StoryMode/data/gas.gd").DOME_POCKET_MASS
		await h.wait(3.0)
		h.check("the dome gas haze takes this dome's shape", gf.dome._sprites.size() >= 1 and gf.dome.shown > 0.1, [gf.dome._sprites.size(), gf.dome.shown])
		await h.shot("dome_gas")
		gf.dome.amount = keep
		await h.wait(2.5)

	# One wave, fought from the main station.
	var st = _Host.station(dome, 0)
	var inside: bool = await _Host.enter_station(h, st, h.keeper())
	h.check("the keeper takes the station", inside)
	Data.apply("team1.dome.maxHealth", 1000000)
	Data.apply("team1.dome.health", 1000000)
	h.enable_waves()
	GameWorld.runStarted = true
	Data.apply("team1.monsters.wavecooldown", 2)
	var came: bool = await h.until(func(): return Data.ofOr("team1.monsters.wavepresent", false) and _Host.monsters(h).size() > 0, 90.0)
	h.check("a wave comes", came)
	var fire: String = d + "_fire"
	var has_fire: bool = InputMap.has_action(fire)
	var hp: Dictionary = {}
	var dmg := 0.0
	var t0: float = h.now()
	var shots: int = 0
	while h.now() - t0 < 45.0 and Data.ofOr("team1.monsters.wavepresent", false):
		var t: float = h.now() - t0
		var tesla = _tesla(dome)
		if tesla != null:
			_tesla_step(h, tesla, fire)
		else:
			# Sweep left and right, firing in bursts (the sword stabs on release).
			_Host.hold(h, _held, "ui_left", fmod(t, 3.0) < 1.5)
			_Host.hold(h, _held, "ui_right", fmod(t, 3.0) >= 1.5)
			if has_fire:
				_Host.hold(h, _held, fire, fmod(t, 0.8) < 0.5)
		for m in _Host.monsters(h):
			var u: int = m.UID
			if hp.has(u) and m.currentHealth < hp[u]:
				dmg += hp[u] - m.currentHealth
			hp[u] = m.currentHealth
		await h.frames(1)
		if t > 3.0 + shots * 8.0 and shots < 3:
			shots += 1
			await h.shot("wave_%d" % shots)
	for a in ["ui_left", "ui_right", "ui_up", "ui_down", fire]:
		_Host.hold(h, _held, a, false)
	var by_weapon: bool = not Data.ofOr("team1.monsters.wavepresent", false)
	# A monster killed in one hit leaves between two frames: count what went.
	var alive: Array = _Host.monsters(h).map(func(m): return m.UID)
	var killed: int = hp.keys().filter(func(u): return not alive.has(u)).size()
	h.note("wave", {"damage": dmg, "killed": killed, "cleared by the weapon": by_weapon, "left": alive.size()})
	h.check("the %s's weapon hurts the wave" % d, dmg > 0.0 or killed > 0, [dmg, killed])
	if not by_weapon:
		for mm in h.get_tree().get_nodes_in_group("monster-manager"):
			mm.instantlyKillWave()
	var gone: bool = await h.until(func(): return not Data.ofOr("team1.monsters.wavepresent", false), 40.0)
	h.check("the wave ends", gone)
	h.disable_waves()
	st.useHit(h.keeper())
	await h.wait(1.0)

	# Save and load.
	var money: int = int(h.inv("money"))
	var val = Data.ofOr(_key(), null)
	var slot: int = 30 + int(d.substr(4))
	SaveGame.saveGame(SaveGame.get_run_folder(), slot, true)
	await h.wait(1.5)
	SaveGame.loadGame(SaveGame.get_run_folder(), slot)
	await h.wait(1.0)
	await h.until(func(): return Level.stage != null and Level.stage.get("keeperInputStarted") == true and Level.map != null and Level.map.isMapReady(), 30.0)
	await h.wait(2.0)
	h.disable_waves()
	var dome2 = _dome()
	h.check("the %s comes back after the load" % d, dome2 != null and str(dome2.scene_file_path).ends_with(DOMES[d][2]), dome2.scene_file_path if dome2 else null)
	h.check("the upgrade comes back", GameWorld.boughtUpgrades.has(tid) and str(Data.ofOr(_key(), null)) == str(val), [val, Data.ofOr(_key(), null)])
	h.check("the money comes back", int(h.inv("money")) == money, [money, h.inv("money")])
	h.snap_camera()
	await h.wait(1.0)
	await h.shot("after_load")
	# Still takes Story minerals after the load.
	var m2: int = int(h.inv("money"))
	await h.deliver("bronze", 3)
	var paid: bool = await h.until(func(): return int(h.inv("money")) >= m2 + 3, 30.0)
	h.check("the shredder still pays after the load", paid, [m2, h.inv("money")])
