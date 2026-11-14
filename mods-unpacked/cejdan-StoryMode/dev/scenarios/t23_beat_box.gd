extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 23: a story beat opens, holds the wave countdown still while it is
# open (and the keeper too), closes on select, and never plays twice. Ends by
# saving the run (slot 11) with one beat open; t23_beat_reload loads that save
# in a fresh process and checks what comes back.

const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const CD := "team1.monsters.wavecooldown"
const SLOT := 11


func boot() -> Dictionary:
	return {"seed": 12345}


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


# Select until the beat is gone: the first press may only finish the typing.
func _close(h, id: String) -> bool:
	await h.wait(1.0)
	for i in 3:
		await h.press("ui_select")
		if await h.until(func(): return StoryBeats.instance().open_id != id, 0.8):
			return true
	return false


func run(h) -> void:
	# Let the level start finish (it resets the wave clock), then: waves on (dev
	# mode turns them off), clock running, no wave for a while.
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.enable_waves()
	GameWorld.runStarted = true
	Data.apply("team1.monsters.wavedelay", 0.0)
	Data.apply(CD, 300.0)
	h.check("the beats node is in the run", StoryBeats.instance() != null)
	var before: Array = await _samples(h, 2.0)
	h.note("countdown before", before)
	h.check("the countdown runs before any beat", _falling(before), before)
	await h.shot("before_beat")

	# One beat, by id. The keeper holds Right the whole time it is open.
	var kp0: Vector2 = h.keeper().global_position
	h.check("fire(first_gem) queues it", StoryBeats.fire("first_gem"))
	var opened: bool = await h.until(func(): return StoryBeats.is_open(), 5.0)
	h.check("the beat box opens", opened and StoryBeats.instance().open_id == "first_gem")
	# A select pressed the moment it opens (a key already in use) doesn't close it.
	await h.press("ui_select")
	await h.frames(3)
	h.check("the box ignores select in its first moment", StoryBeats.is_open())
	h.down("ui_right")
	var open_t0: float = h.now()
	await h.wait(0.5)
	await h.shot("beat_open")
	var box = Level.stage.find_child("StoryBeatPopup", true, false)
	h.check("the box shows the beat's lines", box != null and box.text() == "\n".join(PackedStringArray(load("res://mods-unpacked/cejdan-StoryMode/data/beats.gd").by_id("first_gem")["lines"])), box.text() if box else null)
	var during: Array = await _samples(h, 5.0)
	h.up("ui_right")
	h.snap("beat open", ["team1.story.beatsqueued", "team1.story.beatsplayed"])
	h.note("countdown while open", {"samples": during, "seconds": h.now() - open_t0})
	h.check("wavecooldown unchanged the whole time the box is open", during.min() == during.max(), during)
	h.check("the game is paused while the box is open", GameWorld.paused)
	var moved: float = h.keeper().global_position.distance_to(kp0)
	h.check("the keeper stays put while the box is open (Right held)", moved < 1.0, moved)
	h.check("first_gem is closed on select", await _close(h, "first_gem"))
	await h.wait(0.3)
	await h.shot("after_close")
	var after: Array = await _samples(h, 2.0)
	h.note("countdown after", after)
	h.check("the countdown runs again after the box closes", _falling(after) and not GameWorld.paused, after)
	h.check("first_gem is marked played", StoryBeats.has_played("first_gem"))

	# Once per run.
	h.check("fire(first_gem) again is refused", not StoryBeats.fire("first_gem"))
	await h.wait(1.0)
	h.check("and nothing opens", not StoryBeats.is_open())
	h.check("an unknown id is refused", not StoryBeats.fire("no_such_beat"))

	# A trigger name, plus a second beat fired while the first is open: it waits.
	h.check("trigger(biome:B2) queues one beat", StoryBeats.trigger("biome:B2") == 1)
	await h.until(func(): return StoryBeats.is_open(), 5.0)
	h.check("biome_b2 opens", StoryBeats.instance().open_id == "biome_b2")
	h.check("fire(gate_broken) while a beat is open queues it", StoryBeats.fire("gate_broken"))
	await h.wait(0.5)
	h.check("the open beat stays on screen", StoryBeats.instance().open_id == "biome_b2")
	h.check("biome_b2 closes", await _close(h, "biome_b2"))
	var next: bool = await h.until(func(): return StoryBeats.instance().open_id == "gate_broken", 5.0)
	h.check("gate_broken opens after it", next)
	await h.wait(0.5)
	await h.shot("second_beat")
	h.check("gate_broken closes", await _close(h, "gate_broken"))
	h.check("trigger(biome:B2) again queues nothing", StoryBeats.trigger("biome:B2") == 0)

	# Save with translator_1 open; t23_beat_reload loads it.
	StoryBeats.fire("translator_1")
	await h.until(func(): return StoryBeats.is_open(), 5.0)
	await h.wait(0.5)
	var cd_saved: float = _cd()
	await SaveGame.saveGame("singleplayer", SLOT, true)
	await h.wait(1.0)
	h.snap("saved", ["team1.story.beatsqueued", "team1.story.beatsplayed"])
	h.check("the save holds the played and queued beats",
			str(Data.serialize()).contains("first_gem,biome_b2,gate_broken") and str(Data.ofOr("team1.story.beatsqueued", "")) == "translator_1",
			[Data.ofOr("team1.story.beatsplayed", ""), Data.ofOr("team1.story.beatsqueued", "")])
	h.note("saved slot", {"slot": SLOT, "cooldown": cd_saved})
