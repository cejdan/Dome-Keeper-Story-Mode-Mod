extends RefCounted

# The horror's story beats (#23): text boxes that pause the wave countdown.
# Each plays once per run. Lines and triggers live here so the story script
# (#25, loaded by #99) drops in without code changes.
#
# Fields:
#   id       unique name; code fires a beat with StoryBeats.fire(id)
#   trigger  what fires it: StoryBeats.trigger(name) plays every unplayed beat
#            whose trigger is `name`. Names wired so far: none (the biome and
#            event watchers are #26). Planned names:
#              biome:B2 .. biome:B8, lava_ocean, boss_chamber,
#              first_gem, gate_broken, lava_death, translator:1 .. translator:3,
#              unobtainium:1, :3, :5, :7, :10, ending:doom, ending:saved
#   tier     style tier 1 (calm) .. 3 (large, glowing); styling is #24, the
#            box draws every tier plainly for now
#   lines    1 to 3 short lines, shown together
#
# All text below is placeholder until the script lands.

const BEATS: Array = [
	{"id": "biome_b2", "trigger": "biome:B2", "tier": 1, "lines": ["You dig well.", "Keep going."]},
	{"id": "biome_b3", "trigger": "biome:B3", "tier": 1, "lines": ["Deeper. Yes."]},
	{"id": "biome_b4", "trigger": "biome:B4", "tier": 2, "lines": ["The metal was never meant to keep you out."]},
	{"id": "biome_b5", "trigger": "biome:B5", "tier": 2, "lines": ["They shout at you up there.", "Down here it is quiet."]},
	{"id": "biome_b6", "trigger": "biome:B6", "tier": 2, "lines": ["You are close now."]},
	{"id": "biome_b7", "trigger": "biome:B7", "tier": 3, "lines": ["Warm, isn't it?"]},
	{"id": "biome_b8", "trigger": "biome:B8", "tier": 3, "lines": ["Almost.", "Almost."]},
	{"id": "lava_ocean", "trigger": "lava_ocean", "tier": 3, "lines": ["The fire remembers me.", "Take what shines in it."]},
	{"id": "boss_chamber", "trigger": "boss_chamber", "tier": 3, "lines": ["You came.", "I knew you would."]},
	{"id": "first_gem", "trigger": "first_gem", "tier": 1, "lines": ["Pretty, isn't it?", "There is more below."]},
	{"id": "gate_broken", "trigger": "gate_broken", "tier": 2, "lines": ["Metal breaks.", "So does everything."]},
	{"id": "lava_death", "trigger": "lava_death", "tier": 2, "lines": ["Not yet.", "Come back to me."]},
	{"id": "translator_1", "trigger": "translator:1", "tier": 1, "lines": ["Why listen to them?", "They only scream."]},
	{"id": "translator_2", "trigger": "translator:2", "tier": 2, "lines": ["Their words are lies."]},
	{"id": "translator_3", "trigger": "translator:3", "tier": 3, "lines": ["Now you hear them.", "Dig anyway."]},
	{"id": "unobtainium_1", "trigger": "unobtainium:1", "tier": 3, "lines": ["Ah."]},
	{"id": "unobtainium_3", "trigger": "unobtainium:3", "tier": 3, "lines": ["The seal thins."]},
	{"id": "unobtainium_5", "trigger": "unobtainium:5", "tier": 3, "lines": ["I can feel your hands."]},
	{"id": "unobtainium_7", "trigger": "unobtainium:7", "tier": 3, "lines": ["More.", "More."]},
	{"id": "unobtainium_10", "trigger": "unobtainium:10", "tier": 3, "lines": ["I am awake."]},
]


static func by_id(id: String) -> Dictionary:
	for b: Dictionary in BEATS:
		if b["id"] == id:
			return b
	return {}


static func ids_for(trigger_name: String) -> Array:
	var out: Array = []
	for b: Dictionary in BEATS:
		if b.get("trigger", "") == trigger_name:
			out.append(b["id"])
	return out
