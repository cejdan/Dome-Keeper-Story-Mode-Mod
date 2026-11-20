extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 157: lava deaths fire lava_death:1 .. :5 (the 5th on every death
# after). Since the user's script pass (#285) only the first death has a beat,
# the narrator's; the later triggers still fire and play nothing. The keeper
# overheats seven times and must see lava_death_1, then nothing.

const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const BeatData = preload("res://mods-unpacked/cejdan-StoryMode/data/beats.gd")


func boot() -> Dictionary:
	return {"seed": 12345, "beats": true}


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	var field = Level.map.get_node_or_null("StoryLavaField")
	h.check("lava field is in the run", field != null)
	if field == null:
		return
	var room: Vector2i = Vector2i(0, 6)
	await h.dig_room(room + Vector2i(-1, -1), room + Vector2i(1, 1))
	h.check("one lava death beat, on the first death (2 to 5 cut, #285)", BeatData.ids_for("lava_death:1") == ["lava_death_1"] and range(2, 6).all(func(n): return BeatData.ids_for("lava_death:%d" % n).is_empty()))

	var want: Array = ["lava_death_1", "", "", "", "", "", ""]
	var got: Array = []
	for i in want.size():
		await h.teleport_tile(room)
		await h.wait(0.5)
		var r0: int = field.recalls
		field.heat = field.HEAT_MAX + 5.0
		var died: bool = await h.until(func(): return field.recalls > r0, 5.0)
		h.check("death %d recalls the keeper" % (i + 1), died, field.recalls)
		got.append(await h.read_beat("death%d" % (i + 1), 6.0, i == 0 or i >= 4))
		await h.wait(0.8)
	h.note("beats per death", got)
	h.check("death 1 plays lava_death_1, deaths 2-7 play nothing", got == want, got)
	h.check("the saved recall count is 7", field.recalls == 7, field.recalls)
