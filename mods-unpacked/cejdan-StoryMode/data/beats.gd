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
#   tier     style tier (beats/BeatBox.gd, #24): 1 calm, 2 warm violet wave,
#            3 glowing with glitches, 4 awake (full-screen violet dark)
#   lines    1 to 3 short lines, shown together
#
# Lines are the story script (docs/story/script.md, #25).

const BEATS: Array = [
	{"id": "biome_b2", "trigger": "biome:B2", "tier": 1, "lines": ["Oh. Someone is digging.", "Hello. Don't stop on my account."]},
	{"id": "biome_b3", "trigger": "biome:B3", "tier": 1, "lines": ["The rock is warmer here. That's me, I think.", "The ones on the surface are only frightened. You don't have to be."]},
	{"id": "biome_b4", "trigger": "biome:B4", "tier": 2, "lines": ["You're doing so well.", "Every layer you lift is a blanket off my face.", "Just a little deeper."]},
	{"id": "biome_b5", "trigger": "biome:B5", "tier": 2, "lines": ["I can hear your heartbeat through the stone.", "It keeps time with the drill. Isn't that lovely?", "Don't go up yet."]},
	{"id": "biome_b6", "trigger": "biome:B6", "tier": 2, "lines": ["Others came before you. They stopped about here, for a while.", "They always came down in the end.", "Just a little deeper."]},
	{"id": "biome_b7", "trigger": "biome:B7", "tier": 3, "lines": ["I've waited such a long time for hands like yours.", "Patient hands. Hungry hands.", "Closer."]},
	{"id": "biome_b8", "trigger": "biome:B8", "tier": 3, "lines": ["This is the last crust between us.", "Under it, everything is warm and bright, and all of it is yours.", "I only want one small thing back. Keep digging."]},
	{"id": "lava_ocean", "trigger": "lava_ocean", "tier": 3, "lines": ["Swim, then. The fire won't mind you.", "The bright stone is down there. Your kind call it a fortune.", "Every piece you lift, I breathe a little easier. Take as many as you like."]},
	{"id": "first_gem", "trigger": "first_gem", "tier": 1, "lines": ["Pretty, isn't it?", "There's so much more. All of it further down."]},
	{"id": "gate_broken", "trigger": "gate_broken", "tier": 2, "lines": ["Someone locked that door a long time ago.", "Not against you. Never against you."]},
	{"id": "lava_death", "trigger": "lava_death", "tier": 2, "lines": ["Oh. Oh, that hurt you.", "The fire is clumsy. I would hold you more gently.", "There you are. Come back down."]},
	{"id": "translator_1", "trigger": "translator:1", "tier": 1, "lines": ["That's one of theirs. You don't need it.", "I already speak your language."]},
	{"id": "translator_2", "trigger": "translator:2", "tier": 2, "lines": ["Another one? Their words are so loud, and so small.", "Mine are only for you. Wouldn't you rather have mine?"]},
	{"id": "translator_3", "trigger": "translator:3", "tier": 3, "lines": ["Please put it down. They'll tell you I'm something terrible.", "Have I ever been anything but kind to you?", "Listen to me. Only me."]},
	{"id": "unobtainium_1", "trigger": "unobtainium:1", "tier": 3, "lines": ["Ah. Ahh. Did you feel that?", "Something very old just cracked, little keeper.", "Do it again."]},
	{"id": "unobtainium_3", "trigger": "unobtainium:3", "tier": 3, "lines": ["Three. I can feel my fingers again, little keeper.", "The first thing they touch will be you."]},
	{"id": "unobtainium_5", "trigger": "unobtainium:5", "tier": 3, "lines": ["Five. I can see your lamp through my eyelids, little keeper.", "Up there, they're crying. Down here, I'm smiling.", "Keep digging."]},
	{"id": "unobtainium_7", "trigger": "unobtainium:7", "tier": 4, "lines": ["Seven. My heart has started again. It beats with yours.", "I'm so proud of you, little keeper.", "Bring me the rest, and I'll give you everything you came here for."]},
	{"id": "unobtainium_10", "trigger": "unobtainium:10", "tier": 4, "lines": ["Ten. The seal is only a whisper now, little keeper.", "Come to the middle of the world. I want to see your face.", "Or go home rich, if you like. I'll be awake to wave goodbye."]},
	{"id": "boss_chamber", "trigger": "boss_chamber", "tier": 4, "lines": ["There you are. Oh, look at you. So small, after all that digging.", "You were so good, little keeper. Better than the others.", "The little ones above have a word for me. It means hunger. That's unkind.", "My name is Velle. It means wanting.", "You know all about wanting, don't you?", "Now come closer, and let me open my eyes."]},
	{"id": "boss_wait", "trigger": "boss_wait", "tier": 4, "lines": ["Not yet, little keeper. Come closer.", "Closer still. I'm almost ready for you."]},
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
