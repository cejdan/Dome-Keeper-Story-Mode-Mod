extends RefCounted

# Miner data logs (#94): one per biome, found in the miner bones. Each opens
# in the salvaged-log box when its bones are uncovered, once per run.
#   id     log_b1 .. log_b8 (biome index 0 .. 7)
#   title  the log's header line
#   lines  the body, one line each
# Lines are the story script (docs/story/script.md, #25).

const LOGS: Array = [
	{"id": "log_b1", "biome": 0, "title": "Personal log: Dale Okafor, Keeper 1, shift 3", "lines": ["Bugs hit the dome again. They shriek the whole fight, like they're yelling at me.", "Ore's thick up here. Hit quota by noon.", "Company sheet says the fauna is acoustically aggressive, non-strategic.", "Earplugs in. Drill on."]},
	{"id": "log_b2", "biome": 1, "title": "MEMO: Halcyon Extraction, Fauna Compliance", "lines": ["To all Keepers: native vocalisations are noise, not language. Do not record them.", "Alien translation devices found on site are company property. Surrender them unused.", "Productivity bonuses resume below Layer 4."]},
	{"id": "log_b3", "biome": 2, "title": "Personal log: Ines Varga, Keeper 4, shift 21", "lines": ["Heard something under the drill tonight. Not the bugs. Lower. Kind.", "It said the things on the surface are only frightened. That I don't have to be.", "Slept nine hours. First time since landing."]},
	{"id": "log_b4", "biome": 3, "title": "MEMO: Halcyon Extraction, Office of Deep Projects", "lines": ["Keeper 4 reports a voice at Layer 3. Excellent. Do not recall her.", "Her depth per shift is up 300 percent since contact.", "Classify the voice as a motivational phenomenon. Keep it out of onboarding.", "Keepers who hear it dig. Keepers who dig retire."]},
	{"id": "log_b5", "biome": 4, "title": "Personal log: Ruth Ammon, Keeper 5, shift 64", "lines": ["Passed Varga's bones at Layer 3. Her pad said the voice told her she was doing so well.", "It tells me that too. I think it means it.", "I've stopped going up for the waves. They don't break the dome. They just cry at it.", "Just a little deeper. It's always just a little deeper."]},
	{"id": "log_b6", "biome": 5, "title": "Personal log: Sol Haddad, Keeper 6, shift 80", "lines": ["Got a translator working. The company said never to.", "They aren't screaming. They're saying please. They've been saying please since day one.", "It asked me to put the translator down. It's never asked me for anything before.", "I put it down. Then I picked up the drill."]},
	{"id": "log_b7", "biome": 6, "title": "Personal log: Ada Lindqvist, Keeper 7, shift 112", "lines": ["The translator says they've stopped screaming. Now they sing. Funeral songs.", "It calls me little keeper now. It told me its name.", "I won't write it down. Writing it feels like opening a door.", "I said I'd go up. I'm going down."]},
	{"id": "log_b8", "biome": 7, "title": "MEMO: Halcyon Extraction, Office of the Chair (copied by Keeper 8)", "lines": ["The Asset gave Keeper 7 its name: Velle.", "The ore was never the product. Once woken, Velle hollows the planet. What's left is solid unobtainium.", "Keeper 9 deploys next cycle. Do not brief. Pre-approve the retirement.", "Added by Keeper 8: whoever you are, don't buy it."]},
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
