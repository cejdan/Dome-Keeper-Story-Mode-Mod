extends RefCounted

# English text for everything the mod adds. Keys follow the game's own scheme
# (`upgrades.<id>.title` / `.desc`). Registered once at startup.

const EN := {
	"upgrades.storymode.title": "Story Mode",
	"upgrades.storymode.desc": "Dig deep. Sell what you find. Something down there is waiting.",
	"loadout.storymode.headline": "Story Mode",
	"upgrades.storysuitblaster.title": "Suit Blaster",
	"upgrades.storyheatshield1.title": "Heat Shielding I",
	"upgrades.storyheatshield1.desc": "Suit upgrade that slows the heat. Lava heats you 40% slower, and depth heat starts one layer deeper.",
	"upgrades.storyheatshield2.title": "Heat Shielding II",
	"upgrades.storyheatshield2.desc": "Thicker heat shielding. Lava heats you 65% slower, and depth heat starts one additional layer deeper.",
	"upgrades.storyheatshield3.title": "Heat Shielding III",
	"upgrades.storyheatshield3.desc": "Advanced heat shielding. Lava heats you 80% slower, and depth heat starts another additional layer deeper.",
	"upgrades.storyheatshield4.title": "Heat Shielding IV",
	"upgrades.storyheatshield4.desc": "Maximum heat shielding. You don't have to worry about depth heat, and could even survive a long time in lava.",
	"upgrades.storywin.title": "Win Condition",
	"upgrades.storywin.desc": "Your job here is simple. Fulfill your assigned mineral quota.",
	"upgrades.storydrillmetal.title": "Metal Bit",
	"upgrades.storydrillmetal.desc": "A hardened bit for the Mine Driller. Allows the drills to cut through metal.",
	"upgrades.storydrillbotmetal.title": "Metal Bit",
	"upgrades.storydrillbotmetal.desc": "New teeth for Drillbert. He chews through metal now.",
	"upgrades.storyretirerich.title": "Fill Quota",
	"upgrades.storyretirerich.desc": "Fulfill your assigned mineral quota for your dig. Ends the run as a win.",
	"upgrades.storynewgadget1.title": "New Gadget I",
	"upgrades.storynewgadget2.title": "New Gadget II",
	"upgrades.storynewgadget3.title": "New Gadget III",
	"upgrades.storynewgadget4.title": "New Gadget IV",
	"upgrades.storyventdome.title": "Vent the Dome",
	"upgrades.storyventdome.desc": "Flush all of the gas buildup out of the dome. The dome's air will be clean again.",
	"upgrades.storysuitblaster.desc": "Install a mining blaster into your suit. Its blast breaks rock and metal blocks.",
}


static func register() -> void:
	var t: Translation = Translation.new()
	t.locale = "en"
	for k: String in EN:
		t.add_message(k, EN[k])
	for i in range(1, 5):
		t.add_message("upgrades.storynewgadget%d.desc" % i, "Roll a random gadget for the dome.")
	# Story beats (data/beats.gd): story.beat.<id> holds the beat's lines.
	t.add_message("story.beat.continue", "Continue")
	t.add_message("story.beat.waiting", "Waiting for the other players...")
	for b: Dictionary in load("res://mods-unpacked/cejdan-StoryMode/data/beats.gd").BEATS:
		t.add_message("story.beat." + str(b["id"]), "\n".join(PackedStringArray(b.get("lines", []))))
	TranslationServer.add_translation(t)
