extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 41: lava survives save and reload. Breach a pocket, let the lava flow,
# save through vanilla's SaveGame (slot 11, the cheat menu's slot), then do what
# a load does for lava: drop the lava field and let the director build a new
# one, which must come back from the saved state rather than re-placing pockets.
# (A full quit-and-relaunch load can't be driven from the dev boot yet.)

const SLOT := 11


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	var field = Level.map.get_node_or_null("StoryLavaField")
	h.check("the run has a lava field", field != null)
	# Breach the shallowest pocket from an open room right next to it.
	var cells: Array = field.magma.keys()
	cells.sort_custom(func(a, b): return a.y < b.y)
	var hit: Vector2i = cells[0]
	await h.dig_room(hit + Vector2i(-3, -3), hit + Vector2i(3, -1))
	await h.reveal([hit])
	await h.teleport_tile(hit + Vector2i(0, -1))
	var tile = Level.map.getTile(Vector2(hit))
	Level.map.destroyTile("team1", "", tile)
	await h.wait(12.0)
	await h.teleport_tile(hit + Vector2i(0, -3))
	await h.wait(1.5)
	await h.shot("before_save")
	var st: Dictionary = field.stats()
	var breached: Array = []
	for c in cells:
		if not field.magma.has(c):
			breached.append([c.x, c.y])
	# One pocket far away that stays whole, to breach after the reload.
	var whole: Vector2i = cells.back()
	h.check("lava is flowing before the save", st["cells"] > 0, st)
	await SaveGame.saveGame(SaveGame.get_run_folder(), SLOT, true)
	await h.wait(1.0)
	h.note("saved", {"stats": st, "breached": breached.size(), "whole": whole})
	h.check("lava went into the save (Data key, which vanilla writes into the save file)", str(Data.ofOr("story.lava", "")).length() > 10 and str(Data.serialize()).find("story.lava") >= 0)
	GameWorld.paused = true
	var blob: String = str(Data.ofOr("story.lava", ""))
	# Reload, as far as lava goes: a fresh field on the same map.
	Level.map.remove_child(field)
	field.queue_free()
	GameWorld.paused = false
	await h.until(func(): return Level.map.get_node_or_null("StoryLavaField") != null, 10.0)
	var f2 = Level.map.get_node_or_null("StoryLavaField")
	h.check("a new lava field came up", f2 != null and f2 != field)
	var st2: Dictionary = f2.stats()
	h.note("restored", {"before": st, "after": st2})
	h.check("same lava cells after the reload", int(st2["cells"]) == int(st["cells"]), [st["cells"], st2["cells"]])
	h.check("same total mass after the reload", absf(float(st2["total"]) - float(st["total"])) < 0.01, [st["total"], st2["total"]])
	h.check("same magma left after the reload", int(st2["magma"]) == int(st["magma"]), [st["magma"], st2["magma"]])
	var back: Array = []
	for e in breached:
		if f2.magma.has(Vector2i(int(e[0]), int(e[1]))):
			back.append(e)
	h.check("breached pockets don't come back as magma", back.is_empty() and breached.size() > 0, back)
	await h.wait(1.0)
	await h.shot("after_reload")
	# A pocket that was never breached still breaches and flows.
	h.check("an unbreached pocket is still magma", f2.magma.has(whole), whole)
	await h.dig_room(whole + Vector2i(-2, -3), whole + Vector2i(2, -1))
	await h.reveal([whole])
	await h.teleport_tile(whole + Vector2i(0, -3))
	var b0: int = f2.breaches
	var c0: int = f2.mass.size()
	Level.map.destroyTile("team1", "", Level.map.getTile(Vector2(whole)))
	await h.wait(6.0)
	h.check("it breaches and flows after the reload", f2.breaches > b0 and f2.mass.size() > c0, f2.stats())
	await h.shot("whole_pocket_breached")
