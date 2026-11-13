extends RefCounted

# English text for everything the mod adds. Keys follow the game's own scheme
# (`upgrades.<id>.title` / `.desc`). Registered once at startup.

const EN := {
	"upgrades.storymode.title": "Story Mode",
	"upgrades.storymode.desc": "Dig deep. Sell what you find. Something down there is waiting.",
	"loadout.storymode.headline": "Story Mode",
	"upgrades.storysuitblaster.title": "Suit Blaster",
	"upgrades.storyheatshield1.title": "Heat Shielding I",
	"upgrades.storyheatshield1.desc": "Suit lining that slows the heat. Lava heats you 40% slower; depth heat too.",
	"upgrades.storyheatshield2.title": "Heat Shielding II",
	"upgrades.storyheatshield2.desc": "Thicker lining. Lava heats you 65% slower, depth heat 70% slower.",
	"upgrades.storyheatshield3.title": "Heat Shielding III",
	"upgrades.storyheatshield3.desc": "Ceramic plates. Lava heats you 80% slower, depth heat 90% slower.",
	"upgrades.storyheatshield4.title": "Heat Shielding IV",
	"upgrades.storyheatshield4.desc": "The best suit money can buy. Depth heat can't touch you. Lava still can, about 17 times slower.",
	"upgrades.storydrillmetal.title": "Metal Bit",
	"upgrades.storydrillmetal.desc": "A hardened bit for the Mine Driller. Its drills cut through metal.",
	"upgrades.storydrillbotmetal.title": "Metal Bit",
	"upgrades.storydrillbotmetal.desc": "New teeth for Drillbert. He chews through metal now.",
	"upgrades.storyretirerich.title": "Retire Rich",
	"upgrades.storyretirerich.desc": "Sell the dome, buy an island, never dig again. Ends the run as a win.",
	"upgrades.storynewgadget1.title": "New Gadget I",
	"upgrades.storynewgadget2.title": "New Gadget II",
	"upgrades.storynewgadget3.title": "New Gadget III",
	"upgrades.storynewgadget4.title": "New Gadget IV",
	"upgrades.storysuitblaster.desc": "Install a mining blaster into your suit. Its blast breaks rock, and the metal that no drill can touch.",
}


static func register() -> void:
	var t: Translation = Translation.new()
	t.locale = "en"
	for k: String in EN:
		t.add_message(k, EN[k])
	for i in range(1, 5):
		t.add_message("upgrades.storynewgadget%d.desc" % i, "Roll a random gadget for the dome, as if you found one in a cave. Reroll with water. Paid when you pick.")
	# Story beats (data/beats.gd): story.beat.<id> holds the beat's lines.
	t.add_message("story.beat.continue", "Continue")
	for b: Dictionary in load("res://mods-unpacked/cejdan-StoryMode/data/beats.gd").BEATS:
		t.add_message("story.beat." + str(b["id"]), "\n".join(PackedStringArray(b.get("lines", []))))
	TranslationServer.add_translation(t)
