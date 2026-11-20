extends RefCounted

# Story Mode shop prices. In Story Mode every iron cost becomes a dollar cost
# ("money"); water and cobalt costs stay as vanilla has them.
#
# All numbers are starting values for the user to tune:
#   PRICES        dollar price per upgrade id (lowercase), replacing its iron cost
#   REPEAT_ADD    dollars added per repeat, replacing a "cost.iron += n" rule
#   MAX_COST      dollar cap, replacing a "maxcost.iron = n" rule
#   DEFAULT_RATE  dollars per vanilla iron for anything not listed (gadget
#                 upgrades: the flat B4 rate from the price plan)

const DEFAULT_RATE: int = 14

const PRICES: Dictionary = {
	# Keeper
	"drill1": 4, "drill2": 15, "drill3": 200, "drill4": 900,
	"jetpackspeed1": 4, "jetpackspeed2": 15, "jetpackspeed3": 170, "jetpackspeed4": 1150,
	"jetpackstrength1": 4, "jetpackstrength2": 15, "jetpackstrength3": 170, "jetpackstrength4": 1150,
	# The other keepers (#297): starting values, tier for tier like the Engineer
	# by depth in the keeper's tree: 4, 15, then 200 / 900 on a mining line (like
	# the drill) or 170 / 1150 on any other (like the jetpack). Not balanced yet.
	# Assessor (keeper2)
	"keeper2pinballdamage1": 4, "keeper2pinballdamage2": 15, "keeper2pinballdamage3": 200, "keeper2pinballdamage4": 900,
	"keeper2pinballmorespheres1": 4, "keeper2pinballspherelifetime": 15,
	"keeper2pinballreflect": 200, "keeper2pinballreflect2": 900,
	"keeper2pinballexplode": 200, "keeper2pinballexplode2": 900,
	"keeper2pinballsplit": 200, "keeper2pinballsplit2": 900,
	"keeper2rotationalmining1": 4, "keeper2rotationalmining2": 15,
	"keeper2movement1": 4, "keeper2movement2": 15, "keeper2movement3": 170, "keeper2movement4": 1150,
	"keeper2bundle1": 4, "keeper2bundle2": 15, "keeper2bundle3": 170, "keeper2bundle4": 1150,
	# Keeper3
	"keeper3kunaidamage4": 4, "keeper3kunaicooldown1": 15, "keeper3kunaicooldown2": 200, "keeper3kunaicooldown3": 900,
	"keeper3shuriken1": 4, "keeper3shuriken2": 15,
	"keeper3shurikencooldown1": 200, "keeper3shurikencooldown2": 900,
	"keeper3shurikenstrength1": 200, "keeper3shurikenstrength2": 900,
	"keeper3kunaibounce1": 4, "keeper3kunaibounce2": 15,
	"keeper3doublejump": 4, "keeper3slidecontrol": 15, "keeper3quadjump": 170, "keeper3aerialmastery": 1150,
	"keeper3carrylimit1": 4, "keeper3carrylimit2": 15, "keeper3carrylimit3": 170,
	# Keeper4
	"keeper4punch1": 4, "keeper4punch2": 15, "keeper4punch3": 200, "keeper4punch4": 900,
	"keeper4ramping1": 4, "keeper4ramping2": 15, "keeper4ramping3": 200, "keeper4ramping4": 900,
	"keeper4flexible1": 4, "keeper4flexible2": 15, "keeper4flexible3": 200, "keeper4flexible4": 900,
	"keeper4squad1": 4, "keeper4autospawnminers": 15, "keeper4squad2": 200, "keeper4squad3": 900,
	"keeper4speed1": 4, "keeper4speed2": 15, "keeper4speed3": 170,
	"keeper4catgoblinamount": 4, "keeper4catgoblindig1": 15, "keeper4catgoblindig2": 170, "keeper4catgoblinsleeptime": 1150,
	# Laser dome
	"laserstrength1": 6, "laserstrength2": 60, "laserstrength3": 570, "laserstrength4": 6300,
	"lasermove1": 6, "lasermove2": 50, "lasermove3": 4000,
	"laseraimline": 7, "laserbend": 450, "laserhitprojectiles": 10000,
	"dome1health1": 25, "dome1health2": 280,
	"domehealthmeter": 2, "domewavemeter": 4,
	"domesupplementresurrection2": 950,
	# The other domes (#269): starting values, tier for tier like the laser dome
	# (by depth in the tree: 6, ~55, ~570, ~6300; cheap side picks like the aim
	# line, mid-tree extras like Laser Bend / Move III). Not balanced yet.
	# Sword dome
	"swordblade1": 6, "swordlargeblade1": 60, "swordlargeblade2": 570, "swordlargeblade3": 6300,
	"swordlongblade1": 60, "swordlongblade2": 570, "swordelectrified": 6300,
	"swordaimline": 7, "swordextendlong1": 6, "swordextendlong2": 50, "swordextendlong3": 4000,
	"swordstabfast1": 6, "swordstabfast2": 50, "swordstabshoot": 570,
	"swordreflection1": 6, "swordreflection2": 50, "swordreflection3": 570,
	"swordfastreflection": 50, "swordexplosivereflection": 450,
	"dome2health1": 25, "dome2health2": 280,
	# Artillery dome
	"artillerydirecthit1": 6, "artillerydirecthit2": 60, "artillerydirecthit3": 570, "artillerydirecthit4": 6300,
	"artillerysplash1": 6, "artillerysplash2": 60, "artillerysplash3": 570, "artillerysplash4": 6300,
	"artillerygrenadefastreload": 6300, "artilleryrotation2": 50, "artilleryrotation1": 450,
	"artillerymachinegun1": 6, "artillerymachinegun2": 50, "artillerymachinegun3": 570, "artillerydoublemachinegun": 6300,
	"artillerymachinegunhoming1": 570, "artillerymachinegunhoming2": 6300,
	"dome3health1": 25, "dome3health2": 280,
	# Tesla dome
	"teslapower1": 6, "teslapower2": 60, "teslapower3": 570, "teslapower4": 6300,
	"teslaspeed1": 6, "teslaspeed2": 50, "teslaspeed3": 570, "teslaspeed4": 4000,
	"teslaquickshot": 7, "teslaquickshot2": 60, "teslaautoaim": 7,
	"teslaorbs": 6, "teslapersistance1": 50, "teslapersistance2": 450, "teslapersistance3": 4000,
	"teslanurture": 50, "teslaorbstun": 450, "teslaorbdamage": 4000,
	"dome4health1": 25, "dome4health2": 280,
	# Turret dome (unreleased in vanilla; only the machine gun picks do anything)
	"turretslot1machinegun": 60, "turretslot1railgun": 60, "turretslot2machinegun": 60, "turretslot2minelayer": 60,
	"dome5health1": 25, "dome5health2": 280,
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
	# The other keepers' last mining tiers repeat like Drill IV (#297).
	"keeper2pinballdamage4": 3000,
	"keeper4punch4": 3000, "keeper4ramping4": 3000, "keeper4flexible4": 3000,
	# Repeatable early picks (as often as vanilla allows): one more sphere, more
	# sphere life, one more squad member, one more cat goblin (capped at $100,
	# MAX_COST). Keeper3's Kunai Damage doubles its price each time, as vanilla.
	"keeper2pinballmorespheres1": 25,
	"keeper2pinballspherelifetime": 30,
	"keeper4squad1": 50,
	"keeper4catgoblinamount": 10,
	"droneyarddrones": 40,
	"droneyarddronespeed1": 100,
}

const MAX_COST: Dictionary = {
	"keeper4catgoblinamount": 100,
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
			elif change.keyClass == "maxcost" and change.keyName == "iron":
				# Left as it is, vanilla's cap would add "iron: 0" to the money cost.
				rules.append(PropertyChange.new("maxcost.money = %d" % int(MAX_COST.get(uk, int(change.value) * DEFAULT_RATE))))
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
