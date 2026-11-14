extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 157: each of the first five lava deaths in a run plays its own horror
# beat; the 5th plays again on every death after. The keeper overheats seven
# times and must see lava_death_1 .. _5, then _5, _5.

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
	h.check("five lava death beats, only the 5th repeats", BeatData.ids_for("lava_death:5") == ["lava_death_5"] and range(1, 6).all(func(n): return bool(BeatData.by_id("lava_death_%d" % n).get("repeat", false)) == (n == 5)))

	var want: Array = ["lava_death_1", "lava_death_2", "lava_death_3", "lava_death_4", "lava_death_5", "lava_death_5", "lava_death_5"]
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
	h.check("deaths 1-7 play beats 1, 2, 3, 4, 5, 5, 5", got == want, got)
	h.check("the saved recall count is 7", field.recalls == 7, field.recalls)
