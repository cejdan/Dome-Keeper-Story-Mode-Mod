extends RefCounted

# English text for everything the mod adds. Keys follow the game's own scheme
# (`upgrades.<id>.title` / `.desc`). Registered once at startup.

const EN := {
	"upgrades.storymode.title": "Story Mode",
	"upgrades.storymode.desc": "Dig deep. Sell what you find. Something down there is waiting.",
	"loadout.storymode.headline": "Story Mode",
	"upgrades.storysuitblaster.title": "Suit Blaster",
	"upgrades.storyretirerich.title": "Retire Rich",
	"upgrades.storyretirerich.desc": "Sell the dome, buy an island, never dig again. Ends the run as a win.",
	"upgrades.storygadgetcellar.title": "Cellar Gadget",
	"upgrades.storygadgetcellar.desc": "Pick one of three gadgets for a cellar slot. Paid when you pick.",
	"upgrades.storygadgetmineshaft.title": "Mineshaft Gadget",
	"upgrades.storygadgetmineshaft.desc": "Pick one of three gadgets for the mineshaft. Paid when you pick.",
	"upgrades.storygadgetdomesurface.title": "Dome Surface Gadget",
	"upgrades.storygadgetdomesurface.desc": "Pick one of three gadgets for the dome's surface. Paid when you pick.",
	"upgrades.storygadgetdomeback.title": "Dome Back Gadget",
	"upgrades.storygadgetdomeback.desc": "Pick one of three gadgets for the back of the dome. Paid when you pick.",
	"upgrades.storygadgetactive.title": "Active Gadget",
	"upgrades.storygadgetactive.desc": "Pick one of three active gadgets. Paid when you pick.",
	"upgrades.storysuitblaster.desc": "Install a mining blaster into your suit. Its blast breaks rock, and the metal that no drill can touch.",
}


static func register() -> void:
	var t: Translation = Translation.new()
	t.locale = "en"
	for k: String in EN:
		t.add_message(k, EN[k])
	TranslationServer.add_translation(t)
