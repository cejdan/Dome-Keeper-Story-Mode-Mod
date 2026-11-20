extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 121: every piece sold pops its price over the dome. Three iron pop
# +$5 three times, one after another; a mixed batch pops each mineral's own
# price; bones pop their value. Frame bursts catch the ripple.

const Minerals = preload("res://mods-unpacked/cejdan-StoryMode/data/minerals.gd")
const SalePops = preload("res://mods-unpacked/cejdan-StoryMode/hud/sale_pops.gd")
const Bones = preload("res://mods-unpacked/cejdan-StoryMode/data/bones.gd")


func boot() -> Dictionary:
	return {"seed": 12345}


func _amounts(pops, from: int) -> Array:
	return pops.shown.slice(from).map(func(p): return int(p["amount"]))


func run(h) -> void:
	await h.until(func(): return not StageManager.isSwitchingStage(), 20.0)
	await h.wait(1.0)
	h.disable_waves()
	var pops = SalePops.instance()
	h.check("the sale pops node is in the run", pops != null)
	if pops == null:
		return
	h.snap_camera()
	await h.wait(0.5)

	# ---- three iron: +$5 +$5 +$5, staggered
	var iron: int = Minerals.value_of("iron")
	var m0: int = int(h.inv("money"))
	var n0: int = pops.shown.size()
	h.deliver("iron", 3)
	await h.until(func(): return pops.shown.size() > n0, 10.0)
	await h.burst("iron_x3", 30, 4)
	await h.until(func(): return pops.shown.size() >= n0 + 3, 5.0)
	var got: Array = _amounts(pops, n0)
	h.check("3 iron pop +$%d three times" % iron, got == [iron, iron, iron], got)
	var ts: Array = pops.shown.slice(n0).map(func(p): return float(p["t"]))
	h.check("the three pops come one after another, not at once", ts.size() == 3 and ts[1] > ts[0] and ts[2] > ts[1], ts)
	h.check("money rose by the pops' total", int(h.inv("money")) - m0 == iron * 3, int(h.inv("money")) - m0)
	await h.wait(2.0)

	# ---- a mixed batch: each mineral pops its own price
	n0 = pops.shown.size()
	var batch: Array = ["bronze", "gold", "ruby", "diamond"]
	var want: Array = []
	for t: String in batch:
		want.append(Minerals.value_of(t))
		h.deliver(t, 1)
		await h.frames(4)
	await h.until(func(): return pops.shown.size() > n0, 10.0)
	await h.burst("mixed", 30, 4)
	await h.until(func(): return pops.shown.size() >= n0 + batch.size(), 5.0)
	got = _amounts(pops, n0)
	got.sort()
	want.sort()
	h.check("a mixed batch pops each piece's price", got == want, {"got": got, "want": want})
	await h.wait(2.0)

	# ---- a big batch: 10 iron, one pop per piece as the dome takes each in
	n0 = pops.shown.size()
	var mb: int = int(h.inv("money"))
	h.deliver("iron", 10)
	await h.until(func(): return pops.shown.size() > n0, 10.0)
	await h.burst("iron_x10", 30, 4)
	await h.until(func(): return pops.shown.size() >= n0 + 10, 20.0)
	h.check("10 iron: 10 pops, one per piece sold", pops.shown.size() - n0 == 10 and int(h.inv("money")) - mb == iron * 10, {"pops": pops.shown.size() - n0, "money": int(h.inv("money")) - mb})
	await h.wait(2.0)

	# ---- bones pop their value
	n0 = pops.shown.size()
	var dome = Level.getDome("team1")
	var d = Level.drops.network_spawn({"type": Bones.TYPE, "position": dome.getDropTarget("iron").global_position + Vector2(0, -8), "impulse": Vector2.ZERO})
	d.value = Bones.value_for(4)
	d.biome = 4
	await h.until(func(): return pops.shown.size() > n0, 10.0)
	await h.burst("bones", 24, 3)
	got = _amounts(pops, n0)
	h.check("bones pop their value ($%d)" % Bones.value_for(4), got == [Bones.value_for(4)], got)
	await h.wait(2.0)
	h.check("finished pops are freed", h.get_tree().get_nodes_in_group("story-sale-pop").is_empty(), h.get_tree().get_nodes_in_group("story-sale-pop").size())
