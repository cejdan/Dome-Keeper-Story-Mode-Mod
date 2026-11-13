extends RefCounted

# Story Mode shop prices. In Story Mode every iron cost becomes a dollar cost
# ("money"); water and cobalt costs stay as vanilla has them.
#
# All numbers are starting values for the user to tune:
#   PRICES        dollar price per upgrade id (lowercase), replacing its iron cost
#   REPEAT_ADD    dollars added per repeat, replacing a "cost.iron += n" rule
#   DEFAULT_RATE  dollars per vanilla iron for anything not listed (gadget
#                 upgrades: the flat B4 rate from the price plan)

const DEFAULT_RATE: int = 14

const PRICES: Dictionary = {
	# Keeper
	"drill1": 4, "drill2": 15, "drill3": 200, "drill4": 900,
	"jetpackspeed1": 4, "jetpackspeed2": 15, "jetpackspeed3": 170, "jetpackspeed4": 1150,
	"jetpackstrength1": 4, "jetpackstrength2": 15, "jetpackstrength3": 170, "jetpackstrength4": 1150,
	# Laser dome
	"laserstrength1": 6, "laserstrength2": 60, "laserstrength3": 570, "laserstrength4": 6300,
	"lasermove1": 6, "lasermove2": 50, "lasermove3": 4000,
	"laseraimline": 7, "laserbend": 450, "laserhitprojectiles": 10000,
	"dome1health1": 25, "dome1health2": 280,
	"domehealthmeter": 2, "domewavemeter": 4,
	"domesupplementresurrection2": 950,
	# Shield: strength (+ vanilla water), battle branches (+ vanilla cobalt), overcharge
	"shieldstrength1": 7, "shieldstrength2": 30, "shieldstrength3": 280,
	"shieldbattleelectroblast": 55, "shieldbattlelongerafterdepletion": 500, "shieldbattleblastdamage": 6300,
	"shieldbattleinvulnerable": 55, "shieldbattleactivateondepletion": 500, "shieldbattledestructionprevention": 6300,
	"shieldbattlereflect": 55, "shieldbattlereflectshortuses": 500, "shieldbattlereflectspeed": 6300,
	"shieldovercharge": 30, "shieldoverchargestrength1": 400, "shieldoverchargestrength2": 5900,
	# The other primary gadgets, tier for tier like the shield
	"repellentdelay1": 7, "repellentdelay2": 30, "repellentdelay3": 280,
	"repellentbattlehealthreduction": 55, "repellentbattlelongerhealthreduction": 500, "repellentbattledamageovertime": 6300,
	"repellentbattleslowdown": 55, "repellentbattlestrongerslowdown1": 500, "repellentbattlestrongerslowdown2": 6300,
	"repellentbattleslowdownstun1": 500, "repellentbattleslowdownstun2": 6300,
	"repellentovercharge": 30, "repellentoverchargeduration1": 400, "repellentoverchargeduration2": 5900,
	"orchardduration1": 7, "orchardduration2": 30, "orchardduration3": 280,
	"orchardbattlerooting": 55, "orchardbattlerootingexplosion": 500, "orchardbattlerootingmore": 6300,
	"orchardbattleshield": 55, "orchardbattleshieldsecondlayer": 500, "orchardbattleshieldstrong": 6300,
	"orchardovercharge": 30, "orchardovercharge2": 400, "orchardovercharge3": 5900,
	"droneyarddrones": 7, "droneyarddronespeed1": 30,
	"droneyardbattlegrid": 55, "droneyardbattlegridquick1": 500, "droneyardbattlegridquick2": 6300,
	"droneyardbattlegridlong1": 500, "droneyardbattlegridlong2": 6300,
	"droneyardparasites": 55, "droneyardparasites2": 500, "droneyardparasites3": 6300,
	"droneyardovercharge1": 30, "droneyardovercharge2": 400, "droneyardovercharge3": 5900,
}

const REPEAT_ADD: Dictionary = {
	"drill4": 3000,   # #148: Drill V $3,900, VI $6,900 (was $9,400, $17,400)
	"droneyarddrones": 40,
	"droneyarddronespeed1": 100,
}

# id -> {"cost": original cost, "repeatable": original repeat rules}
static var _vanilla: Dictionary = {}


# Rewrites Data.upgrades in place: Story Mode prices when `story`, vanilla's own
# otherwise. Called before every level start (each run copies its upgrades from
# Data.upgrades), so vanilla modes always see vanilla costs.
static func apply(story: bool) -> void:
	for uk: String in Data.upgrades:
		var u: Dictionary = Data.upgrades[uk]
		if not _vanilla.has(uk):
			var keep: Dictionary = {}
			if u.get("cost") is Dictionary:
				keep["cost"] = u["cost"].duplicate()
			if u.get("repeatable") is Array:
				keep["repeatable"] = u["repeatable"].duplicate()
			_vanilla[uk] = keep
		var orig: Dictionary = _vanilla[uk]
		if orig.has("cost"):
			u["cost"] = orig["cost"].duplicate()
		if orig.has("repeatable"):
			u["repeatable"] = orig["repeatable"].duplicate()
		if story:
			_to_dollars(uk, u)


static func _to_dollars(uk: String, u: Dictionary) -> void:
	if not (u.get("cost") is Dictionary) or not u["cost"].has("iron"):
		return
	var old: Dictionary = u["cost"]
	var cost: Dictionary = {}
	# Money first, so it is the first cost shown on the panel.
	cost["money"] = int(PRICES.get(uk, int(old["iron"]) * DEFAULT_RATE))
	for k: String in old:
		if k != "iron":
			cost[k] = old[k]
	u["cost"] = cost
	if u.get("repeatable") is Array:
		var rules: Array = []
		for change in u["repeatable"]:
			if change.keyClass == "cost" and change.keyName == "iron":
				if change.cumulative:
					var add: int = int(REPEAT_ADD.get(uk, int(change.value) * DEFAULT_RATE))
					rules.append(PropertyChange.new("cost.money += %d" % add))
				elif change.multiplicative:
					rules.append(PropertyChange.new("cost.money *= %s" % str(change.value)))
				else:
					rules.append(PropertyChange.new("cost.money = %d" % (int(change.value) * DEFAULT_RATE)))
			else:
				rules.append(change)
		u["repeatable"] = rules


# Short money text for the narrow cost slot on a tech panel: 950, 1400, 17.4k, 25k, 1M.
static func short(amount: int) -> String:
	if amount >= 1000000:
		return str(snappedf(amount / 1000000.0, 0.01)).trim_suffix(".0") + "M"
	if amount >= 10000:
		return str(snappedf(amount / 1000.0, 0.1)).trim_suffix(".0") + "k"
	return str(amount)
