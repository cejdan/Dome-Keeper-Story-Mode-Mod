extends RefCounted

# The Story Mode gadget shop (#51, reworked in #132): gadgets are bought, never
# found.
#
# The shop's Story Mode track has one chain, New Gadget I -> II -> III -> IV.
# Each entry costs more (data/upgrades.yaml) and does the same thing: buying it
# opens vanilla's gadget choice, as if a gadget had been found in a cave, with
# vanilla's number of offers drawn from every gadget the dome can still take.
# A reroll costs 1 water. The offers stay fixed until a pick and live in Data,
# so they are saved with the run. The entry's price is charged on pick, which
# also marks it bought and unlocks the next one; Cancel closes the choice and
# costs nothing.
#
# Keeper-suit gadgets are never offered: the suit slot belongs to the Suit
# Blaster (#22), the only way through the gate.

const PREFIX := "storynewgadget"
const TIERS := 4
const REROLL_WATER: int = 1
const SUIT_SLOT := "keepersuit"

# Never offered, whatever their slots say.
const REMOVED: Array = ["suitblaster"]


static func _base(id: String) -> String:
	var i: int = id.rfind(".")
	return id.substr(i + 1) if i >= 0 else id


static func is_entry(tech_id: String) -> bool:
	return _base(tech_id).begins_with(PREFIX)


# Shop entry ids for a team, cheapest first.
static func entries(teamId: String) -> Array:
	var out: Array = []
	for i in range(1, TIERS + 1):
		out.append("%s.%s%d" % [teamId, PREFIX, i])
	return out


static func _suit_gadget(data: Dictionary) -> bool:
	if REMOVED.has(_base(str(data.get("id", "")))):
		return true
	for s in data.get("takeslots", []):
		if _base(str(s)) == SUIT_SLOT:
			return true
	return false


# Every gadget the dome can take right now (vanilla's own availability rules:
# limits, free slots for every slot it takes, not yet bought), minus suit gadgets.
static func candidates(teamId: String, playerId: String) -> Array:
	var out: Array = []
	for data: Dictionary in GameWorld.generateGadgets(teamId, playerId):
		if not _suit_gadget(data):
			out.append(str(data.get("id", "")))
	out.sort()
	return out


# Vanilla's number of choices per found gadget.
static func offer_count(teamId: String) -> int:
	return maxi(1, int(Data.ofOr(teamId + ".artifacts.gadgetChoicesPerArtifact", 3)))


static func _key(teamId: String) -> String:
	return teamId + ".story.gadgetoffers"


# The current offers. Kept until a pick or a reroll; drawn fresh when there are
# none yet or one of them can no longer be bought.
static func offers(teamId: String, playerId: String) -> Array:
	var cands: Array = candidates(teamId, playerId)
	var n: int = offer_count(teamId)
	var cur: Array = Array(str(Data.ofOr(_key(teamId), "")).split(",", false))
	var valid: bool = cur.size() > 0
	for id in cur:
		valid = valid and cands.has(id)
	if valid and (cur.size() >= n or cur.size() == cands.size()):
		return cur
	cur = _draw(cands, [], n)
	Data.apply(_key(teamId), ",".join(cur))
	return cur


# New offers, avoiding the current ones where there are enough others.
static func reroll(teamId: String, playerId: String) -> Array:
	var cands: Array = candidates(teamId, playerId)
	var cur: Array = Array(str(Data.ofOr(_key(teamId), "")).split(",", false))
	var next: Array = _draw(cands, cur, offer_count(teamId))
	Data.apply(_key(teamId), ",".join(next))
	return next


static func clear(teamId: String) -> void:
	Data.apply(_key(teamId), "")


static func _draw(cands: Array, avoid: Array, n: int) -> Array:
	var fresh: Array = cands.filter(func(c): return not avoid.has(c))
	fresh.shuffle()
	var out: Array = fresh.slice(0, n)
	var rest: Array = cands.filter(func(c): return avoid.has(c))
	rest.shuffle()
	while out.size() < n and rest.size() > 0:
		out.append(rest.pop_back())
	return out


# The entry a pick pays for: the cheapest one not bought yet.
static func next_entry(teamId: String) -> String:
	for id: String in entries(teamId):
		if GameWorld.upgrades.has(id) and not GameWorld.boughtUpgrades.has(id):
			return id
	return ""


static func price(teamId: String) -> int:
	var id: String = next_entry(teamId)
	if id == "":
		return -1
	var cost = GameWorld.upgrades[id].get("cost", {})
	return int(cost.get("money", 0)) if cost is Dictionary else 0


# Before the shop opens: with nothing left to offer, the unbought entries are
# taken off the shop.
static func refresh_entries(teamId: String, playerId: String) -> void:
	if not candidates(teamId, playerId).is_empty():
		return
	for id: String in entries(teamId):
		if GameWorld.upgrades.has(id) and not GameWorld.boughtUpgrades.has(id):
			GameWorld.upgrades.erase(id)
