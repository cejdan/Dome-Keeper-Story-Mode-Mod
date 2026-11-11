extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 53: Story Mode waves use Relic Hunt's run weight with every mineral
# piece counted as one iron. Run with -Extra "--mode=relichunt" for the vanilla
# comparison (10 iron) and "--difficulty=2" for a harder run.


func boot() -> Dictionary:
	return {"seed": 12345}


func _w() -> float:
	return Level.mode.getRunWeight("team1")


func _mods() -> float:
	return (1.0 + Level.difficulty("team1") * 0.1) * Data.of("team1.monsters.strengthmodfromplayercount") * Data.of("team1.monstermodifiers.totalrunweightmodifier")


func run(h) -> void:
	h.disable_waves()
	# Run weight never drops below 15; lift the base so each step shows.
	Data.apply("team1.monsters.additionalwaveweight", 20)
	var story: bool = Level.loadout.modeId == "storymode"
	var want: float = 6.0 * _mods()
	h.note("setup", {"mode": Level.loadout.modeId, "difficulty": Level.difficulty("team1"), "per 10 pieces": want})
	var w0: float = _w()
	var types: Array = ["bronze", "gold"] if story else ["iron"]
	var deltas: Array = []
	for t: String in types:
		var before: float = _w()
		var inv0: int = int(h.inv(t))
		await h.deliver(t, 10)
		await h.until(func(): return int(h.inv(t)) >= inv0 + 10, 30.0)
		await h.wait(0.5)
		h.note("delivered " + t, int(h.inv(t)) - inv0)
		deltas.append(_w() - before)
	h.note("run weight", {"start": w0, "end": _w(), "deltas": deltas})
	for i in types.size():
		h.check("10 %s raise the run weight by %.2f" % [types[i], want], absf(deltas[i] - want) < 0.01, deltas[i])

	# Five waves, cleared by the cheat menu's kill-wave call (no one is at the laser).
	Data.apply("team1.dome.maxHealth", 1000000)
	Data.apply("team1.dome.health", 1000000)
	h.enable_waves()
	# Vanilla starts the wave clock after 8 dug tiles or the first iron; this
	# run has dug none.
	GameWorld.runStarted = true
	h.speed(3.0)
	var waves: int = 0
	for i in 5:
		Data.apply("team1.monsters.wavecooldown", 2)
		var came: bool = await h.until(func(): return Data.of("team1.monsters.wavepresent"), 40.0)
		if not came:
			break
		h.snap("wave %d" % (i + 1), [])
		await h.wait(4.0)
		if i == 0:
			await h.shot("first_wave")
		for mm in h.get_tree().get_nodes_in_group("monster-manager"):
			mm.instantlyKillWave()
		var gone: bool = await h.until(func(): return not Data.of("team1.monsters.wavepresent"), 60.0)
		if gone:
			waves += 1
	h.speed(1.0)
	h.check("5 waves came and ended", waves == 5, waves)
	h.snap("end", ["team1.story.pieces"])
