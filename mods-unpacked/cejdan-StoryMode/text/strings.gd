extends RefCounted

# English text for everything the mod adds. Keys follow the game's own scheme
# (`upgrades.<id>.title` / `.desc`). Registered once at startup.

const EN := {
	"upgrades.storymode.title": "Story Mode",
	"upgrades.storymode.desc": "Dig deep. Sell what you find. Something down there is waiting.",
	"loadout.storymode.headline": "Story Mode",
}


static func register() -> void:
	var t: Translation = Translation.new()
	t.locale = "en"
	for k: String in EN:
		t.add_message(k, EN[k])
	TranslationServer.add_translation(t)
