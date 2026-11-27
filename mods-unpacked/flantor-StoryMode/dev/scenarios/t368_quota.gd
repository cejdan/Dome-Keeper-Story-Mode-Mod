extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #368: Leave the Planet's quota (Fill Quota, `storyretirerich`) is impossible.
# Sums what every map size is worth over a few seeds (every mineral on the
# map, the ocean's too, at its pieces x value, and the miners' bones): the
# quota is more than ten times the richest. It stays in the shop's Leave the
# Planet section, out of reach (shot of the shop with it focused), next to
# Call for Evacuation; it is no longer how the doom ending is reached.

const MapConfig = preload("res://mods-unpacked/flantor-StoryMode/data/map_config.gd")
static var _MapConfig = MapConfig  # calls go through this: lazy_preload makes const-preload calls slow
const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
static var _Minerals = Minerals  # calls go through this: lazy_preload makes const-preload calls slow
const Bones = preload("res://mods-unpacked/flantor-StoryMode/data/bones.gd")
static var _Bones = Bones  # calls go through this: lazy_preload makes const-preload calls slow
const SEEDS := 3
const TIMEOUT := 600
const SIZES: Array = ["regular-small", "regular-medium", "regular-large", "regular-huge"]


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	h.mute_beats()
	var entry: Dictionary = GameWorld.upgrades.get("team1.storyretirerich", {})
	var quota: int = int(entry.get("cost", {}).get("money", 0))
	h.check("Fill Quota's price is $25,000,000", quota == 25000000, entry.get("cost", {}))
	# The shop, focused on it.
	h.set_inv("money", 48210)
	Level.stage.startUpgradesInput(h.keeper())
	await h.wait(1.5)
	var focused: String = ""
	for i in 8:
		var tree = _tech_tree(h)
		focused = str(tree.focussedTechPanel.techId) if tree != null and tree.focussedTechPanel != null else ""
		if focused.ends_with("storyretirerich"):
			break
		await h.press("ui_up" if i < 4 else "ui_right")
		await h.wait(0.25)
	await h.wait(0.6)
	await h.shot("shop_fill_quota")
	h.check("it is in the shop's Leave the Planet section", focused.ends_with("storyretirerich") or GameWorld.upgrades.has("team1.storyretirerich"), focused)
	h.check("out of reach: the panel can't be bought", not GameWorld.canAfford(entry.get("cost", {}), "team1"), h.inv("money"))
	# What the maps are worth.
	var worth: Dictionary = {}
	var richest: int = 0
	for size: String in SIZES:
		var best: int = 0
		for s in SEEDS:
			var td = h.generate_map(_MapConfig.make_archetype(size), 9100 + s)
			if td == null:
				continue
			var total: int = 0
			for c: Vector2i in td.get_used_biome_cells():
				var r: int = td.get_resourcev(c)
				var m: String = _Minerals.by_tile_id(r) if (r >= 40 or r == Data.TILE_IRON) else ""
				if m == "":
					continue
				total += int(Minerals.TABLE[m].get("drops", 2)) * _Minerals.value_of(m)
			for bone: Array in td.get_meta("story_bones", []):
				total += _Bones.value_for(int(bone[2]))
			best = maxi(best, total)
			td.queue_free()
			await h.frames(1)
		worth[size] = best
		richest = maxi(richest, best)
	h.note("the richest map of each size ($, minerals and bones)", worth)
	h.check("the quota is more than ten times the richest map ($%d)" % richest, richest > 0 and quota > richest * 10, {"quota": quota, "richest": richest})


func _tech_tree(h):
	for n in h.get_tree().get_nodes_in_group("techtree"):
		if n.get("focussedTechPanel") != null or "focussedTechPanel" in n:
			return n
	var found: Array = h.get_tree().root.find_children("*", "", true, false).filter(func(n): return "focussedTechPanel" in n)
	return found[0] if not found.is_empty() else null
