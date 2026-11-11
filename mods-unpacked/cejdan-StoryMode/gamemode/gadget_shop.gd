extends RefCounted

# The Story Mode gadget shop (#51): gadgets are bought, never found.
#
# The shop's Story Mode track lists one entry per open gadget slot. Choosing
# one opens vanilla's gadget-choice popup (extensions/stages/level/LevelStage.gd)
# with that slot's 3 offers. The offers stay fixed until a pick and live in
# Data, so they are saved with the run; a reroll costs 1 water. The price is
# charged on pick and follows a ladder by the number of gadgets owned (the
# primary gadget and the Suit Blaster don't count).
#
# Prices are starting values for the user to tune.

# Ladder: price of the 1st, 2nd, ... gadget; after the last, +LADDER_STEP each.
const LADDER: Array = [50, 400, 2500, 10000]
const LADDER_STEP: int = 10000
const OFFERS: int = 3
const REROLL_WATER: int = 1

# Shop entry id (lowercase, as in data/upgrades.yaml) -> gadget slot.
const ENTRIES: Dictionary = {
	"storygadgetcellar": "cellar",
	"storygadgetmineshaft": "mineshaft",
	"storygadgetdomesurface": "domesurface",
	"storygadgetdomeback": "domebackside",
	"storygadgetactive": "activegadget",
}

# Never offered in Story Mode: the suit slot belongs to the Suit Blaster (#22).
const REMOVED: Array = ["probe", "prospectionmeter", "resourcepacker", "suitblaster"]


static func _base(id: String) -> String:
	var i: int = id.rfind(".")
	return id.substr(i + 1) if i >= 0 else id


static func is_entry(tech_id: String) -> bool:
	return ENTRIES.has(_base(tech_id))


static func slot_of(tech_id: String) -> String:
	return ENTRIES.get(_base(tech_id), "")


# Gadgets owned that count for the ladder.
static func owned(teamId: String) -> int:
	var n: int = 0
	for id: String in GameWorld.boughtUpgrades:
		var b: String = _base(id)
		if Data.gadgets.has(b) and Data.gadgets[b].get("type", "") == "gadget" and not REMOVED.has(b):
			n += 1
	return n


static func price(teamId: String) -> int:
	var n: int = owned(teamId)
	if n < LADDER.size():
		return int(LADDER[n])
	return int(LADDER.back()) + LADDER_STEP * (n - LADDER.size() + 1)


# Every gadget that can go in `slot` right now (vanilla's own availability
# rules: limits, free slots for every slot it takes, not yet bought).
static func candidates(slot: String, teamId: String, playerId: String) -> Array:
	var out: Array = []
	for data: Dictionary in GameWorld.generateGadgets(teamId, playerId):
		var id: String = data.get("id", "")
		if REMOVED.has(_base(id)):
			continue
		for s in data.get("takeslots", []):
			if _base(str(s)) == slot:
				out.append(id)
				break
	out.sort()
	return out


static func _key(teamId: String, slot: String) -> String:
	return teamId + ".story.gadgetoffers." + slot


# The slot's current offers. Kept until a pick or a reroll; drawn fresh when
# there are none yet or one of them can no longer be bought.
static func offers(slot: String, teamId: String, playerId: String) -> Array:
	var cands: Array = candidates(slot, teamId, playerId)
	var stored: String = str(Data.ofOr(_key(teamId, slot), ""))
	var cur: Array = Array(stored.split(",", false))
	var valid: bool = cur.size() > 0
	for id in cur:
		valid = valid and cands.has(id)
	if valid and (cur.size() >= OFFERS or cur.size() == cands.size()):
		return cur
	cur = _draw(cands, [])
	Data.apply(_key(teamId, slot), ",".join(cur))
	return cur


# New offers, avoiding the current ones where there are enough others.
static func reroll(slot: String, teamId: String, playerId: String) -> Array:
	var cands: Array = candidates(slot, teamId, playerId)
	var cur: Array = Array(str(Data.ofOr(_key(teamId, slot), "")).split(",", false))
	var next: Array = _draw(cands, cur)
	Data.apply(_key(teamId, slot), ",".join(next))
	return next


static func clear(slot: String, teamId: String) -> void:
	Data.apply(_key(teamId, slot), "")


static func _draw(cands: Array, avoid: Array) -> Array:
	var fresh: Array = cands.filter(func(c): return not avoid.has(c))
	fresh.shuffle()
	var out: Array = fresh.slice(0, OFFERS)
	var rest: Array = cands.filter(func(c): return avoid.has(c))
	rest.shuffle()
	while out.size() < OFFERS and rest.size() > 0:
		out.append(rest.pop_back())
	return out


# Before the shop opens: each slot entry shows the ladder price, and a slot with
# nothing left to offer is taken off the shop.
static func refresh_entries(teamId: String, playerId: String) -> void:
	for e: String in ENTRIES:
		var id: String = teamId + "." + e
		if not GameWorld.upgrades.has(id):
			continue
		if candidates(ENTRIES[e], teamId, playerId).is_empty():
			GameWorld.upgrades.erase(id)
			continue
		var cost = GameWorld.upgrades[id].get("cost", {})
		if cost is Dictionary:
			cost["money"] = price(teamId)
