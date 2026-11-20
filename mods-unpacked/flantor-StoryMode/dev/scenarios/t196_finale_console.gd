extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t196_finale_breath.gd"

# Ticket 196: the keeper sits at the console and leaves its menu alone. The
# menu pauses the game, as in any wave, so the bells wait however long it
# stays open; they start when the player picks Battle.


func run(h) -> void:
	var boss = await start(h)
	var fin = boss.finale
	var m = boss.music
	var k = h.keeper()
	var st = _station(Level.getDome("team1"))
	st.useHit(k)
	await h.until(func(): return fin.activity() == "console", 3.0)
	await h.wait(1.0)
	await h.shot("idle_at_the_console")
	await h.wait(Boss.FINALE_BREATH + 3.0)
	h.check("idle in the console's menu (%.0f s), the bells wait" % (Boss.FINALE_BREATH + 4.0), fin.step == "breath" and fin.activity() == "console" and GameWorld.paused and m.intro_time() < 0.0, [fin.step, fin.activity(), GameWorld.paused])
	var b0: float = h.now()
	await h.press("dome_battle")
	await h.until(func(): return fin.step == "rumble", 2.0)
	h.check("Battle starts them", fin.step == "rumble" and fin.bells_by == "battle" and h.now() - b0 < 0.5, [fin.bells_by, snappedf(h.now() - b0, 0.01)])
	await h.wait(0.5)
	h.check("at the weapon, the world running", fin.activity() == "battle" and not GameWorld.paused and k.isInsideStation, [fin.activity(), GameWorld.paused])
	h.check("the bell intro plays", m.intro_time() >= 0.0, m.playing())
	await h.shot("bells_at_the_weapon")
