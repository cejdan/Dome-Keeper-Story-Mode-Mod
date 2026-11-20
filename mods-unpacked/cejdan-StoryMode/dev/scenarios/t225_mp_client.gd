extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #225: client half. The client's lava, gas and chains match the host's, it
# has the money HUD, and its shop shows dollar prices. Pair: t225_mp_host.

const TIMEOUT := 420
const Host = preload("res://mods-unpacked/cejdan-StoryMode/dev/scenarios/t225_mp_host.gd")


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var host_counts = await shared(h, "counts")
	await h.until(func(): return Level.map.has_node("StoryGasField"), 20.0)
	# Since #228 a client's gas field starts empty and draws the host's stream.
	var gas = Level.map.get_node_or_null("StoryGasField")
	await h.until(func(): return gas != null and gas.net_packets > 0 and not gas.rock.is_empty(), 20.0)
	var mine: Dictionary = Host._counts()
	h.note("counts", {"host": host_counts, "client": mine})
	h.check("story map facts arrived", Level.map.tileData.has_meta("story_meta_synced"))
	for k in ["magma", "lava cells", "gas rock", "chains"]:
		h.check("same %s as the host" % k, host_counts != null and int(host_counts.get(k, -2)) == int(mine[k]), [host_counts.get(k) if host_counts else null, mine[k]])
	h.check("money HUD", Level.stage.find_child("StoryMoneyHud", true, false) != null)
	var priced: Array = []
	for uk: String in Data.upgrades:
		var cost = Data.upgrades[uk].get("cost")
		if cost is Dictionary and cost.has("money"):
			priced.append(uk)
	h.check("shop prices in dollars", priced.size() > 10, priced.size())
	h.check("story iron drop", str(Data.DROP_SCENES["iron"].resource_path).contains("cejdan-StoryMode"), Data.DROP_SCENES["iron"].resource_path)
	await h.shot("client_start")
