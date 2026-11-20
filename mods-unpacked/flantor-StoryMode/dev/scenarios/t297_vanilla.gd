extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #297: vanilla is unchanged. A Relic Hunt run with keeper3 (`-Extra
# "--keeper=keeper2"` for another): its shop's keeper track holds vanilla's
# tree at vanilla's iron prices, and none of Story Mode's entries.

const K = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t297_keeper2.gd")


func boot() -> Dictionary:
	return {"mode": "relichunt", "seed": 12345, "keeper": "keeper3"}


func run(h) -> void:
	h.disable_waves()
	var k = h.keeper()
	await h.wait(1.0)
	h.check("no storykeeper limit in Relic Hunt", not GameWorld.isUpgradeLimitAvailable(k.playerId + ".storykeeper"))
	var shop = await K.open_shop(h, k)
	h.check("the shop opens", shop != null)
	if shop == null:
		return
	var root: String = k.playerId + "." + k.techId
	var panels: Array = []
	var all_ids: Array = []
	for t in K.tracks(shop):
		var ids: Array = t.techPanels.keys().map(func(x): return str(x))
		all_ids.append_array(ids)
		if t.rootTechId == root:
			panels = ids
	h.check("the shop has the %s track" % k.techId, not panels.is_empty(), all_ids)
	h.check("no Story Mode entry anywhere in the shop", not all_ids.any(func(i): return K.short(i).begins_with("story")), all_ids.filter(func(i): return "story" in i))
	var wrong: Array = []
	for id: String in panels:
		if id == root:
			continue
		var cost: Dictionary = GameWorld.upgrades.get(id, {}).get("cost", {})
		var vanilla = Data.upgrades.get(K.short(id), {}).get("cost", {})
		if cost.has("money") or cost != vanilla:
			wrong.append([id, cost, vanilla])
	h.check("every %s entry costs vanilla's iron (%d entries)" % [k.techId, panels.size() - 1], wrong.is_empty() and panels.size() > 3, wrong)
	await K.focus(h, shop, panels[1] if panels.size() > 1 else root)
	await h.shot("vanilla_shop")
	await h.press("ui_cancel")
