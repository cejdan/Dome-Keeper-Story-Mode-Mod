extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #251 (1/2), host half: an online run with two players is saved into the
# multiplayer folder, and which keeper each player had is written to
# user://t251_saved_<mode>.json for t251_mp_load_*. Story Mode by default;
# `-Extra "--vanilla"` saves a Relic Hunt run instead (the vanilla comparison).
# Pair: t251_mp_save_client.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
const TIMEOUT := 300


static func mode() -> String:
	return "relichunt" if Story.has_user_arg("vanilla") else "storymode"


static func slot() -> int:
	return 34 if Story.has_user_arg("vanilla") else 33


static func saved_path() -> String:
	return "user://t251_saved_%s.json" % mode()


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true}


func run(h) -> void:
	if not await host_start(h, 2, mode()):
		return
	await h.wait(3.0)
	var keepers: Dictionary = {}
	for k in Keepers.getAll():
		keepers["host" if k.peerId == 1 else "client"] = {"playerId": k.playerId, "techId": k.techId}
	h.note("keepers", keepers)
	h.check("both players have a keeper", keepers.has("host") and keepers.has("client") and keepers["host"]["playerId"] != keepers["client"]["playerId"], keepers)
	SaveGame.saveGame("multiplayer", slot(), true)
	h.check("the run was saved", FileAccess.file_exists("user://multiplayer/savegame_%d.json" % slot()), slot())
	var out := FileAccess.open(saved_path(), FileAccess.WRITE)
	out.store_string(JSON.stringify(keepers))
	out.close()
	await h.shot("host_saved")
	share("saved", keepers)
	await host_wait_clients_left(h, 60.0)
