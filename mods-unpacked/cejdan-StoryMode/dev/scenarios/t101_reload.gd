extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 101, part two: run t101_chains first. Loads its save (slot 15) in a
# fresh process: the chain broken before the save is still broken.

const Awakening = preload("res://mods-unpacked/cejdan-StoryMode/beats/awakening.gd")


func boot() -> Dictionary:
	return {"load": 15}


func run(h) -> void:
	await h.until(func(): return not SaveGame.currentLoadingSavegame, 20.0)
	await h.wait(1.5)
	h.disable_waves()
	var chains = Level.map.get_node_or_null("StoryChains")
	h.check("chains come back", chains != null and chains.chains.size() > 0)
	var broken: Array = chains.chains.filter(func(c): return c["broken"])
	var freed: Array = chains.chains.filter(func(c): return c["cells"].any(func(x): return Awakening.freed(x)))
	h.check("the chains broken before the save are broken, the rest whole", broken.size() > 0 and broken == freed, [broken.size(), freed.size(), chains.chains.size()])
	h.check("they come back broken, not snapping again", chains._all.all(func(c): return c["snap_t"] < 0.0))
	var trunks_ok: bool = chains.trunks.all(func(t): return t["broken"] == t["members"].all(func(i): return chains.chains[i]["broken"]))
	h.check("a knot's trunk is broken exactly when all its deposits are", trunks_ok and chains.trunks.any(func(t): return t["broken"]))
	h.keeper().teleport(broken[0]["b"] + Vector2(0, -40))
	h.snap_camera()
	await h.wait(1.0)
	await h.shot("after_reload")
