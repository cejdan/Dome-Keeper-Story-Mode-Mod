extends RefCounted

# Miner data logs (#94): one per biome, found in the miner bones. Each opens
# in the salvaged-log box when its bones are sold at the dome, once per run.
#   id     log_b1 .. log_b8 (biome index 0 .. 7)
#   title  the log's header line
#   lines  the body, one paragraph each (a blank line between them;
#          beats/LogBox.gd pages long logs)
#   header optional: the box's top line, in place of "salvaged suit log,
#          recovered in B<n>" (the keeper's own company log, #123)
# Lines are the story script (docs/story/script.md, #25).
#
# keeper_welcome (#123) is the keeper's own log: Halcyon Minerals' welcome memo, which
# opens once at the start of a new run (gamemode/Storymode.gd). biome -1.

const WELCOME := "keeper_welcome"

const LOGS: Array = [
	{"id": "keeper_welcome", "biome": -1, "header": "HALCYON MINERALS INC  //  KEEPER COMMS UPLINK  //  SIGNAL 100%", "title": "MEMO: Keeper Onboarding and Welcome", "lines": ["Congratulations on your new assignment and safe landing, Keeper!", "From everyone here at Halcyon Minerals, thank you! You are the CORE of what we do!", "Be aware that local fauna are agitated by mining operations. They can be easily managed with your company-issued Dome Defense™ equipment.", "Please also be aware that all mined Minerals are company property. Do not attempt to modify the stock Dome Defense™ with mined Minerals, as this will be docked from your pay and could result in penalties up to and including termination.", "We are looking forward to a long and productive dig.", "— Halcyon Minerals Inc."]},
	{"id": "log_b1", "biome": 0, "title": "Personal Keeper Log // Dale Okafor // Dig Day 3", "lines": ["The bugs hit the dome again. More bugs today than yesterday. The company-issued laser held them off, but one hit the dome and caused a small crack.", "I'm worried if more bugs come, I'll need to use some minerals to upgrade the laser power. Technically against the rules. But I don't want to imagine what will happen if the dome crack spreads."]},
	{"id": "log_b2", "biome": 1, "title": "Halcyon Minerals Inc // Keeper Memo // Alien Artifact Policy", "lines": ["MEMO - ALL KEEPERS: We have received reports of unknown alien artifacts discovered during some Keeper digs. These artifacts may be dangerous, do not extract or investigate.", "For your own safety, under no circumstances should you bring them into the dome.", "As a reminder, bonuses will continue to be awarded for minerals extracted from Layer 4 and beyond."]},
	{"id": "log_b3", "biome": 2, "title": "Personal Keeper Log // Ines Varga // Dig Day 7", "lines": ["It's been a week of mining. The bugs keep getting stronger. I'm starting to hear their screams even in my dreams. Been hard to sleep.", "I'm probably just tired but I'm starting to hear voices down in the mine.", "The company said not to waste resources on the dome, they said the dome is strong enough to hold.", "But they can't hear the screams."]},
	{"id": "log_b4", "biome": 3, "title": "Personal Keeper Log // Jay Nguyen // Dig Day 9", "lines": ["I found something down here. Not just gems or minerals. It was some type of alien machine.", "I read the company memo about not researching alien artifacts. But I also read the company memo about not using minerals on dome defenses, what a joke. The waves of bugs are getting really strong now, I would be long dead if I hadn't fixed up the dome. Still probably need to make it stronger.", "Anyway, the artifact seems to let me understand the creatures, a little bit at least. I think they are saying \"help\" and \"please\". It doesn't make sense. They are trying to kill me.", "Will continue further research on the artifacts."]},
	{"id": "log_b5", "biome": 4, "title": "Personal Keeper Log // Uki Akamora // Dig Day 14", "lines": ["It's creepy down here. Not to mention hot. The suit's heat shielding is barely keeping up anymore. Is this an old volcano or something?", "I've just got this sense of dread with every rock I drill. Can't shake the feeling I'm being watched. Starting to think about calling for the evacuation soon.", "Between the monster attacks, the intense heat, and this... voice. The pay just doesn't seem worth it."]},
	{"id": "log_b6", "biome": 5, "title": "Personal Keeper Log // Daemin Barnet // Dig Day 16", "lines": ["Ok that's it, I'm calling for the evacuation. Today's my last day digging. Don't care if they dock my pay or fire me.", "I heard that voice again. It was clear this time, not whispers like before. It said the monsters will rip me apart.", "There's monsters above me. And there's something down here with me. Get me out of here!"]},
	{"id": "log_b7", "biome": 6, "title": "Personal Keeper Log // Sol Haddad // Dig Day 18", "lines": ["No? No, no, no, no!", "I called for evacuation. Request denied? What the hell do they mean request denied?", "There's... something down there, and there's monsters beating at my dome. It's barely intact. The cracks have spread across the entire dome.", "Request denied??", "I'm not going down there. But I can't stay here.", "What do I do?"]},
	{"id": "log_b8", "biome": 7, "title": "Personal Keeper Log // Pavi Khan // Dig Day 21", "lines": ["This will be my last log.", "My dome was breached. The monsters kept getting more aggressive the deeper I went. I couldn't hold them off. I'm sheltering down here, hoping, praying they, or IT won't find me.", "I won't last long without my dome. There's no food, no water. The heat is unbearable. I'm low on oxygen. But I would rather die down here than be ripped to pieces.", "If you are reading this, I finally finished the translator. The bugs are pleading me to stop mining, that if I keep going I'll awaken IT. But if I stay here I'll die.", "I don't really have a choice but to keep going and see what's down there."]},
]


static func by_id(id: String) -> Dictionary:
	for l: Dictionary in LOGS:
		if l["id"] == id:
			return l
	return {}


static func for_biome(biome: int) -> Dictionary:
	for l: Dictionary in LOGS:
		if int(l["biome"]) == biome:
			return l
	return {}
