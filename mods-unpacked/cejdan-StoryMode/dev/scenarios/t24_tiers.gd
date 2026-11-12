extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 24: the horror's four style tiers. Opens one beat per tier, shoots it
# while the text types out and once it is shown, and takes a frame burst of the
# wave and glitch motion. Checks that a press during typing finishes the text
# instead of closing, and that vanilla's "Paused" label stays hidden.

const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const Glitch = preload("res://mods-unpacked/cejdan-StoryMode/beats/fx_glitch.gd")

const BY_TIER := {1: "first_gem", 2: "gate_broken", 3: "biome_b7", 4: "unobtainium_10"}


func boot() -> Dictionary:
	return {"seed": 12345, "beats": true}


func _box(h):
	return Level.stage.find_child("StoryBeatPopup", true, false)


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	# Somewhere with rock and light around the keeper, not the dome's backdrop.
	await h.dig_room(Vector2i(-3, 6), Vector2i(3, 9))
	await h.teleport_tile(Vector2i(0, 9))
	await h.wait(1.0)
	for tier: int in [1, 2, 3, 4]:
		var id: String = BY_TIER[tier]
		h.check("tier %d beat %s queues" % [tier, id], StoryBeats.fire(id))
		await h.until(func(): return StoryBeats.is_open(), 5.0)
		await h.wait(0.6 if tier < 4 else 0.95)
		var box = _box(h)
		h.check("tier %d: the box is up with tier %d" % [tier, tier], box != null and box.tier == tier)
		h.check("tier %d: the text types out" % tier, box != null and box.is_revealing())
		await h.shot("tier%d_typing" % tier)
		await h.press("ui_select")
		await h.frames(2)
		h.check("tier %d: select while typing shows all the text, keeps the box" % tier, StoryBeats.is_open() and not box.is_revealing())
		await h.wait(0.8)
		var labels: Array = h.get_tree().get_nodes_in_group("pauseL").filter(func(n): return n.name == "PauseLabel")
		h.check("tier %d: vanilla's Paused label is hidden" % tier, labels.all(func(n): return not n.isIn), labels.size())
		await h.shot("tier%d_%s" % [tier, id])
		if tier >= 2:
			await h.burst("tier%d_motion" % tier, 16, 4)
		if tier >= 3:
			# Catch a glitch moment (rare by design) and shoot it.
			var rate: float = 0.25 if tier == 3 else 0.7
			var caught: bool = await h.until(func(): return Glitch.burst(box._time, rate), 15.0)
			h.check("tier %d: a glitch flicker happens within 15 s" % tier, caught)
			if caught:
				await h.shot("tier%d_glitch" % tier)
		h.note("tier %d text" % tier, box.text())
		await h.press("ui_select")
		h.check("tier %d: the next select closes it" % tier, await h.until(func(): return not StoryBeats.is_open(), 3.0))
		await h.wait(1.2)
	await h.shot("after_all")
	h.check("the game runs again", not GameWorld.paused)
