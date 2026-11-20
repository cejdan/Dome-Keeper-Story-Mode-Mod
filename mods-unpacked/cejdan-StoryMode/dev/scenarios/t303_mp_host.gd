extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #303 online, host half: the client presses Call for Evacuation in its own
# shop (t303_mp_client). The host queues Halcyon's refusal for the team: it
# opens here too, the entry is bought for the team, no money moves and the run
# goes on. Pair: t303_mp_client.

const TIMEOUT := 240
const LogData = preload("res://mods-unpacked/cejdan-StoryMode/data/logs.gd")
const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const MONEY := 700


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true, "beats": true}


func run(h) -> void:
	if not await host_start(h, 2, "storymode"):
		return
	h.disable_waves()
	Data.apply("team1.inventory.money", MONEY)
	await h.wait(0.5)
	share("go", true)
	var bought: bool = await h.until(func(): return GameWorld.boughtUpgrades.has("team1.storyevacuate"), 90.0)
	h.check("the client's Call for Evacuation is bought for the team", bought)
	var id: String = await h.read_beat("host_refusal", 8.0)
	h.check("Halcyon's refusal opens on the host too", id == LogData.EVACUATION, id)
	h.check("no money moved", int(Data.ofOr("team1.inventory.money", -1)) == MONEY, Data.ofOr("team1.inventory.money", -1))
	h.check("the run goes on", not GameWorld.won and not GameWorld.lost, [GameWorld.won, GameWorld.lost])
	await host_wait_clients_left(h, 90.0)
