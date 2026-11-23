extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t231_split_restart.gd"

# #316: in splitscreen a story beat pauses the game as it does in single player
# and online: the wave countdown holds and keeper 2 (gamepad) stays put while
# the box is open, and both run again once it closes. Then the pause menu still
# pauses splitscreen and lets go when it closes.

const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
static var _StoryBeats = StoryBeats  # calls go through this: lazy_preload makes const-preload calls slow
const CD := "team1.monsters.wavecooldown"
const BEAT := "translator_2"


func boot() -> Dictionary:
	return {"loadout": true, "splitscreen": true}


func _cd() -> float:
	return float(Data.of(CD))


# Wave cooldown every 0.25 s for `sec` seconds.
func _samples(h, sec: float) -> Array:
	var out: Array = []
	for i in int(sec / 0.25):
		out.append(snappedf(_cd(), 0.001))
		await h.wait(0.25)
	return out


func _falling(s: Array) -> bool:
	for i in range(1, s.size()):
		if s[i] >= s[i - 1]:
			return false
	return s.size() > 1


func _still(s: Array) -> bool:
	for v in s:
		if not is_equal_approx(v, s[0]):
			return false
	return s.size() > 1


func run(h) -> void:
	if not await start_split(h):
		return
	h.enable_waves()
	GameWorld.runStarted = true
	Data.apply("team1.monsters.wavedelay", 0.0)
	Data.apply(CD, 300.0)
	var before: Array = await _samples(h, 1.5)
	h.check("the countdown runs before the beat", _falling(before), before)

	# The harness marked every beat played; let this one play again.
	var played: Array = Array(str(Data.ofOr(_StoryBeats.PLAYED, "")).split(",", false))
	played.erase(BEAT)
	Data.apply(_StoryBeats.PLAYED, ",".join(PackedStringArray(played)))
	h.check("fire(%s) queues it" % BEAT, _StoryBeats.fire(BEAT))
	var opened: bool = await h.until(func(): return _StoryBeats.is_open(), 5.0)
	h.check("the beat box opens", opened and _StoryBeats.instance().open_id == BEAT)
	await h.wait(0.5)
	h.check("the game is paused while the beat is open", GameWorld.paused)
	var k2: Keeper = h.local_keepers()[1]
	var p2: Vector2 = k2.global_position
	var during: Array = await _samples(h, 2.0)
	await h.pad_stick(1, Vector2(1, 0), 1.0)
	await h.shot("beat_open")
	h.check("the countdown holds while the beat is open", _still(during), during)
	h.check("keeper 2 stays put while the beat is open", k2.global_position.distance_to(p2) < 2.0, [p2, k2.global_position])

	h.check("the beat closes", await h.read_beat("beat", 5.0) == BEAT)
	await h.wait(0.5)
	h.check("the game runs again after the beat", not GameWorld.paused)
	var after: Array = await _samples(h, 1.5)
	h.check("the countdown runs after the beat", _falling(after), after)
	p2 = k2.global_position
	await h.pad_stick(1, Vector2(1, 0), 1.0)
	h.check("keeper 2 moves after the beat", k2.global_position.distance_to(p2) > 4.0, [p2, k2.global_position])

	# The pause menu (keeper 1, keyboard) still pauses splitscreen.
	await h.press("escape")
	await h.wait(0.8)
	h.check("the pause menu opens", Level.stage.pauseMenuOpen)
	h.check("the pause menu pauses the game", GameWorld.paused)
	var menu: Array = await _samples(h, 1.0)
	h.check("the countdown holds in the pause menu", _still(menu), menu)
	await h.shot("pause_menu")
	await h.press("escape")
	await h.wait(0.8)
	h.check("the pause menu closes", not Level.stage.pauseMenuOpen)
	h.check("the game runs again after the pause menu", not GameWorld.paused)
	var resumed: Array = await _samples(h, 1.0)
	h.check("the countdown runs after the pause menu", _falling(resumed), resumed)
