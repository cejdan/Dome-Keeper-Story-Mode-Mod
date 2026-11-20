extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #269 online, the client half of t269_mp_dome_host (the Artillery Dome).

const TIMEOUT := 420
const Host = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t234_mp_e2e_host.gd")
const UP := "team1.artillerydirecthit1"
const KEY := "team1.artillery.grenadedamage"

var _held: Dictionary = {}


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	var me: String = Keepers.first().playerId
	h.check("this is a client", not h.multiplayer.is_server(), me)
	var scene = await shared(h, "dome", 120.0)
	var dome = Level.getDome("team1")
	h.check("the client has the Artillery Dome too", dome != null and str(dome.scene_file_path) == str(scene), [dome.scene_file_path if dome else null, scene])
	var sold = await shared(h, "sold", 60.0)
	h.check("the host's sale: the same money here", sold != null and await h.until(func(): return Host.money() == int(sold), 10.0), [Host.money(), sold])
	var k0 = Data.ofOr(KEY, null)
	var price: int = Host.cost(UP)
	GameWorld.buyUpgrade(UP, "team1", me)
	var ok: bool = await h.until(func(): return GameWorld.boughtUpgrades.has(UP) and Host.money() == int(sold) - price, 15.0)
	h.check("the client buys Artillery Direct Hit I for $%d" % price, ok and price > 0, [Host.money(), sold, price])
	h.check("it applies here", await h.until(func(): return str(Data.ofOr(KEY, null)) != str(k0), 10.0), [k0, Data.ofOr(KEY, null)])
	h.snap_camera()
	var st = Host.station(dome, 0)
	var inside: bool = await Host.enter_station(h, st, Keepers.first())
	h.check("the client's keeper takes the station", inside)
	await shared(h, "wave_on", 120.0)
	var t0: float = h.now()
	var shot := false
	while h.now() - t0 < 60.0 and await shared(h, "wave_over", 0.0) == null:
		var t: float = h.now() - t0
		# Sweep the barrel; the mortar throws farther the longer fire is held,
		# so the charge grows from shot to shot (0.3 s .. 1.5 s).
		Host.hold(h, _held, "ui_left", fmod(t, 4.0) < 0.6)
		Host.hold(h, _held, "ui_right", fmod(t, 4.0) >= 2.0 and fmod(t, 4.0) < 2.6)
		var cyc: float = 0.3 + fmod(floor(t / 2.0), 5.0) * 0.3
		Host.hold(h, _held, "dome3_fire", fmod(t, 2.0) < cyc)
		await h.frames(1)
		if not shot and t > 4.0:
			shot = true
			await h.shot("client_wave")
	for a in ["ui_left", "ui_right", "dome3_fire"]:
		Host.hold(h, _held, a, false)
	h.check("the host saw the wave through", await shared(h, "wave_over", 30.0) == true)
	st.useHit(Keepers.first())
	await h.wait(1.0)
	await h.shot("client_end")
