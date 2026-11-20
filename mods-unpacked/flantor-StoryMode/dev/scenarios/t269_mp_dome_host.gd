extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #269 online: a Story run with the Artillery Dome. The host picks it in the
# loadout, sells Story minerals at its shredder; the client buys the weapon's
# first upgrade (team-wide, as in vanilla), takes the station and fights a
# wave, which the host sees hurt. Pair: t269_mp_dome_client.

const TIMEOUT := 420
const Host = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t234_mp_e2e_host.gd")
const DOME := "dome3"
const UP := "team1.artillerydirecthit1"
const KEY := "team1.artillery.grenadedamage"


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func _client_keeper():
	for k in Keepers.getAll():
		if k.playerId != "player1":
			return k
	return null


func run(h) -> void:
	if not await host_start(h, 2, "storymode", DOME):
		return
	var dome = Level.getDome("team1")
	h.check("the run has the Artillery Dome", str(dome.scene_file_path).ends_with("Dome3.tscn"), dome.scene_file_path)
	share("dome", str(dome.scene_file_path))
	var m0: int = Host.money()
	await h.deliver("bronze", 10)
	var paid: bool = await h.until(func(): return Host.money() >= m0 + 10, 30.0)
	h.check("Story minerals at its shredder pay", paid, [m0, Host.money()])
	share("sold", Host.money())
	var k0 = Data.ofOr(KEY, null)
	var bought: bool = await h.until(func(): return GameWorld.boughtUpgrades.has(UP), 90.0)
	h.check("the client's purchase lands on the host", bought and str(Data.ofOr(KEY, null)) != str(k0), [k0, Data.ofOr(KEY, null)])
	var ck = _client_keeper()
	var inside: bool = await h.until(func(): return ck != null and ck.isInsideStation, 60.0)
	h.check("the client's keeper is at the station", inside)
	Data.apply("team1.dome.maxHealth", 1000000)
	Data.apply("team1.dome.health", 1000000)
	h.enable_waves()
	GameWorld.runStarted = true
	Data.apply("team1.monsters.wavecooldown", 2)
	var came: bool = await h.until(func(): return Data.ofOr("team1.monsters.wavepresent", false) and Host.monsters(h).size() > 0, 90.0)
	h.check("a wave comes", came)
	share("wave_on", true)
	var hp: Dictionary = {}
	var dmg := 0.0
	var t0: float = h.now()
	var shot := false
	var grenades: Dictionary = {}
	while h.now() - t0 < 50.0 and Data.ofOr("team1.monsters.wavepresent", false):
		for c in Level.map.get_children():
			if c.get_script() != null and str(c.get_script().resource_path).ends_with("artillery/Grenade.gd"):
				grenades[c.get_instance_id()] = true
		for m in Host.monsters(h):
			if hp.has(m.UID) and m.currentHealth < hp[m.UID]:
				dmg += hp[m.UID] - m.currentHealth
			hp[m.UID] = m.currentHealth
		await h.frames(1)
		if not shot and h.now() - t0 > 4.0:
			shot = true
			await h.shot("host_wave")
	var alive: Array = Host.monsters(h).map(func(m): return m.UID)
	var killed: int = hp.keys().filter(func(u): return not alive.has(u)).size()
	h.note("wave", {"damage": dmg, "killed": killed, "left": alive.size(), "grenades": grenades.size()})
	h.check("the client's artillery fires on the host", grenades.size() > 0, grenades.size())
	h.check("and hurts the wave there", dmg > 0.0 or killed > 0, [dmg, killed])
	for mm in h.get_tree().get_nodes_in_group("monster-manager"):
		mm.instantlyKillWave()
	var gone: bool = await h.until(func(): return not Data.ofOr("team1.monsters.wavepresent", false), 40.0)
	h.check("the wave ends", gone)
	h.disable_waves()
	share("wave_over", true)
	await host_wait_clients_left(h)
