extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 144: the Story Mode shop, top to bottom: the win condition's own
# section (Retire Rich only), the dome, Story Mode's track, the keeper, then
# vanilla's order. Retire Rich still wins (t54_retire_rich buys it).


func boot() -> Dictionary:
	return {"seed": 12345}


func _short(id: String) -> String:
	var i: int = id.find(".")
	return id.substr(i + 1) if i >= 0 else id


func _shop(h):
	for n in h.get_tree().root.find_children("*", "", true, false):
		if n.has_method("buyUpgrade") and n.has_method("updateCostLabels") and n.find_child("TechTree") != null:
			return n
	return null


func run(h) -> void:
	h.disable_waves()
	await h.wait(1.0)
	h.set_inv("money", 3000)
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	await h.shot("shop_top")
	var tree = _shop(h).find_child("TechTree")
	var roots: Array = []
	var panels: Dictionary = {}
	for track in tree.get_node("Tracks").get_children():
		roots.append(_short(track.rootTechId))
		panels[_short(track.rootTechId)] = track.techPanels.keys().map(func(k): return _short(str(k)))
	h.note("tracks top to bottom", roots)
	h.note("panels per track", panels)
	h.check("first section is the win condition", roots.size() > 3 and roots[0] == "storywin", roots)
	h.check("it holds only Retire Rich", panels.get("storywin", []).filter(func(k): return k != "storywin") == ["storyretirerich"], panels.get("storywin", []))
	var story: int = roots.find("storymode")
	var keeper: int = -1
	var dome: int = -1
	for i in roots.size():
		if roots[i].begins_with("keeper") and keeper < 0:
			keeper = i
		if roots[i].begins_with("dome") and dome < 0:
			dome = i
	h.check("then the dome, then Story Mode, then the keeper", dome == 1 and story == dome + 1 and keeper == story + 1, {"dome": dome, "story": story, "keeper": keeper, "roots": roots})
	h.check("Retire Rich is not on the Story Mode track any more", not panels.get("storymode", []).has("storyretirerich"), panels.get("storymode", []))
	for i in 4:
		for j in 2:
			await h.press("ui_down")
			await h.wait(0.25)
		await h.shot("shop_down_%d" % i)
	await h.press("ui_cancel")
	await h.wait(0.5)
	h.snap("end", [])
