extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #303 online, client half: this player opens its own shop and presses Call
# for Evacuation with its keys. Its shop closes and Halcyon's refusal opens
# here; the entry shows as bought. Pair: t303_mp_host.

const TIMEOUT := 240
const LogData = preload("res://mods-unpacked/flantor-StoryMode/data/logs.gd")
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
const K = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t297_keeper2.gd")
const EVAC := "team1.storyevacuate"


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	h.check("the host is ready", await shared(h, "go", 150.0) == true)
	var me = h.keeper()
	var shop = await K.open_shop(h, me)
	h.check("the client's shop opens", shop != null)
	if shop == null:
		return
	h.check("Call for Evacuation is in the client's shop", await K.focus(h, shop, EVAC))
	await h.shot("client_shop_before")
	await h.press("ui_select")
	var ok: bool = await h.until(func(): return GameWorld.boughtUpgrades.has(EVAC), 8.0)
	h.check("bought with the client's keys", ok)
	await h.until(func(): return StoryBeats.is_open(), 6.0)
	h.check("the client's shop closed", not (is_instance_valid(shop) and shop.isIn), shop.isIn if is_instance_valid(shop) else "freed")
	var id: String = await h.read_beat("client_refusal", 6.0)
	h.check("Halcyon's refusal opens on the client", id == LogData.EVACUATION, id)
	await h.wait(1.0)
	shop = await K.open_shop(h, me)
	if shop != null:
		await K.focus(h, shop, EVAC)
		await h.shot("client_shop_after")
		await h.press("ui_cancel")
	await h.wait(1.0)
