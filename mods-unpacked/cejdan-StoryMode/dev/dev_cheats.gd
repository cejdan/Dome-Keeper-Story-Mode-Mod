extends Node

# Dev cheats for hand playtests of Story Mode (#292). Dev-only: this file is in
# dev/, which release builds leave out, and mod_main.gd only adds it when the
# file exists.
#
# The F1 cheat panel (vanilla stages/level/Cheats.tscn, open in dev mode) gets
# a "Story Mode" column, first in the row:
#   +$1k .. +$1M         money for the shop (a Story Mode iron is only $5)
#   Heat Shield +1 / IV  every keeper, one tier or all four
#   Suit Blaster         every keeper
#   Metal Bits           the Mine Driller's and Drillbert's metal bits, if owned
#   Boss gear            what `--boss` gives (dev/boss_dev.gd): max drill and
#                        jetpack, the dome's top weapon, Heat Shielding IV, Blaster
#   Shop list + Give     anything the shop offers right now, bought for free
#                        (filter box above it; double-click gives too)
#   Unlock all           every dome, keeper, mode and gadget, for the next loadout
# Everything changes the run's Data, so it works on the host (and single
# player) only, as Data.apply does.
#
# Launch switches (after `--`), for dev/play_dev.ps1:
#   --unlockall          unlocks every dome, keeper, mode and gadget at boot
#                        (saved into the dev profile, %APPDATA%\StoryModeDev)
#   --money=<n>          each Story Mode run starts with $n
#   --gear               each Story Mode run starts with the boss gear

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const KeeperUpgrades = preload("res://mods-unpacked/cejdan-StoryMode/gamemode/keeper_upgrades.gd")
const BossDev = preload("res://mods-unpacked/cejdan-StoryMode/dev/boss_dev.gd")
const Prices = preload("res://mods-unpacked/cejdan-StoryMode/data/prices.gd")

const COLUMN := "StoryModeCheats"
const MONEY_STEPS := [1000, 10000, 100000, 1000000]
const METAL_BITS := ["storydrillmetal", "storydrillbotmetal"]

var _booted := false
var _cheats: Control
var _list: ItemList
var _filter: LineEdit
var _money_label: Label
var _status: Label
# The level stage the launch switches were last applied to.
var _started_stage_id := 0


static func wanted() -> bool:
	return OS.has_feature("editor")


func _process(_delta: float) -> void:
	if not _booted and get_tree().current_scene != null:
		# GameWorld.init() (Game._ready) has loaded the meta save by now, so the
		# unlocks are not overwritten by it.
		_booted = true
		if Story.has_user_arg("unlockall"):
			unlock_all()
	var stage = StageManager.currentStage
	if stage == null or not is_instance_valid(stage):
		return
	var cheats = stage.get("cheats")
	if cheats is Control and is_instance_valid(cheats) and cheats != _cheats:
		_cheats = cheats
		_build_column(cheats)
	if _cheats != null and is_instance_valid(_cheats) and _cheats.visible and _money_label != null:
		_money_label.text = "Money: $%s" % _fmt(int(Data.ofOr(_team() + ".inventory.money", 0)))
	_apply_launch_switches(stage)


# --money / --gear once per Story Mode run, when its keepers are in.
func _apply_launch_switches(stage) -> void:
	if _started_stage_id == stage.get_instance_id():
		return
	if not StageManager.isInLevel() or StageManager.isSwitchingStage() or not Story.is_story():
		return
	if Keepers.getAll().is_empty() or not GameWorld.multiplayer.is_server():
		return
	_started_stage_id = stage.get_instance_id()
	var money: int = int(Story.user_arg("money", "0"))
	if money > 0:
		Data.apply(_team() + ".inventory.money", maxi(money, int(Data.ofOr(_team() + ".inventory.money", 0))))
		print("[devcheats] start money $", money)
	if Story.has_user_arg("gear"):
		print("[devcheats] start gear: ", BossDev.give_gear())


func _build_column(cheats: Control) -> void:
	var row: Node = cheats.get_node_or_null("HBoxContainer")
	if row == null or row.has_node(COLUMN):
		return
	var col := VBoxContainer.new()
	col.name = COLUMN
	col.custom_minimum_size = Vector2(230, 0)
	row.add_child(col)
	row.move_child(col, 0)

	var title := Label.new()
	title.text = "Story Mode"
	col.add_child(title)
	_money_label = Label.new()
	col.add_child(_money_label)

	var money_grid := GridContainer.new()
	money_grid.columns = 2
	col.add_child(money_grid)
	for step: int in MONEY_STEPS:
		_button(money_grid, "+$" + Prices.short(step), add_money.bind(step))

	_button(col, "Heat Shield +1 (all keepers)", heat_shield_up)
	_button(col, "Heat Shield IV (all keepers)", heat_shield_up.bind(KeeperUpgrades.TIERS))
	_button(col, "Suit Blaster (all keepers)", give_blaster)
	_button(col, "Metal Bits (drill, Drillbert)", give_metal_bits)
	_button(col, "Boss gear (everything)", give_boss_gear)

	col.add_child(HSeparator.new())
	var shop_label := Label.new()
	shop_label.text = "Shop: give for free"
	col.add_child(shop_label)
	_filter = LineEdit.new()
	_filter.placeholder_text = "filter (e.g. heat, drill)"
	_filter.text_changed.connect(func(_t): refresh_list())
	col.add_child(_filter)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(230, 260)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(func(i): _give_item(i))
	col.add_child(_list)
	_button(col, "Give selected", func():
		for i in _list.get_selected_items():
			_give_item(i))

	col.add_child(HSeparator.new())
	_button(col, "Unlock all domes + keepers", func():
		unlock_all()
		_say("Unlocked: pick them in the next loadout"))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.custom_minimum_size = Vector2(230, 0)
	col.add_child(_status)

	cheats.visibility_changed.connect(func():
		if is_instance_valid(cheats) and cheats.visible:
			refresh_list())
	refresh_list()


func _button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		if not GameWorld.multiplayer.is_server():
			_say("Host only")
			return
		action.call()
		refresh_list.call_deferred())
	parent.add_child(b)
	return b


func _say(text: String) -> void:
	if _status != null:
		_status.text = text
	print("[devcheats] ", text)


# --- actions ---------------------------------------------------------------

func add_money(amount: int) -> void:
	Data.changeByInt(_team() + ".inventory.money", amount)
	_say("+$" + _fmt(amount))


# Every keeper's Heat Shielding up one tier, or to `to_tier`.
func heat_shield_up(to_tier: int = -1) -> void:
	var given: Array = []
	for pid: String in KeeperUpgrades.player_ids():
		var tier: int = to_tier
		if tier < 0:
			tier = int(Data.ofOr(pid + ".suit.heatshield", 0)) + 1
		given.append_array(KeeperUpgrades.give_heat_shield(pid, tier))
	_say("Heat Shielding: " + (", ".join(given) if not given.is_empty() else "already there"))


func give_blaster() -> void:
	var given: Array = []
	for pid: String in KeeperUpgrades.player_ids():
		var id: String = pid + ".suitblaster"
		if not GameWorld.boughtUpgrades.has(id):
			GameWorld.serverAddUpgrade(id, KeeperUpgrades.team_of(pid))
			given.append(id)
	KeeperUpgrades.mark_blaster_entries()
	_say("Suit Blaster: " + (", ".join(given) if not given.is_empty() else "already there"))


func give_metal_bits() -> void:
	var given: Array = []
	for raw: String in METAL_BITS:
		var id: String = _shop_id(raw)
		if id != "" and not GameWorld.boughtUpgrades.has(id):
			GameWorld.serverAddUpgrade(id, _team())
			given.append(id)
	_say("Metal Bits: " + (", ".join(given) if not given.is_empty() else "none (needs the drill gadget or Drillbert first)"))


func give_boss_gear() -> void:
	var given: Array = BossDev.give_gear()
	_say("Boss gear: %d upgrades" % given.size())


# Buys a shop upgrade the way the shop does, with its price paid by the cheat:
# each cost is topped up first and put back afterwards, so the purchase runs
# every hook a real one does (the Blaster entry grants the gadget, and so on).
func buy_free(id: String) -> bool:
	if not GameWorld.upgrades.has(id) or GameWorld.boughtUpgrades.has(id) and not _repeatable(id):
		return false
	var pid: String = id.get_slice(".", 0) if id.begins_with("player") else Story.local_pid()
	var team: String = KeeperUpgrades.team_of(pid)
	var cost: Dictionary = GameWorld.upgrades[id].get("cost", {})
	var before: Dictionary = {}
	for k: String in cost:
		var key: String = team + ".inventory." + k
		before[key] = Data.ofOr(key, 0)
		Data.apply(key, before[key] + cost[k])
	GameWorld.buyUpgrade(id, team, pid)
	for key: String in before:
		Data.apply(key, before[key])
	return GameWorld.boughtUpgrades.has(id)


func _give_item(i: int) -> void:
	if not GameWorld.multiplayer.is_server():
		_say("Host only")
		return
	var id: String = _list.get_item_metadata(i)
	_say(("Gave " if buy_free(id) else "Could not give ") + id)
	refresh_list.call_deferred()


# Every dome, keeper, mode and gadget (vanilla's unlock-everything, as the
# playtest build type does), plus the domes and keepers by name.
static func unlock_all() -> void:
	GameWorld.unlockEverything()
	for id: String in ["dome1", "dome2", "dome3", "dome4", "keeper1", "keeper2", "keeper3", "keeper4", Story.MODE_ID]:
		GameWorld.unlockElement(id)
	GameWorld.unlocks.update()
	print("[devcheats] unlocked everything")


# --- shop list -------------------------------------------------------------

func refresh_list() -> void:
	if _list == null or not is_instance_valid(_list):
		return
	var want: String = _filter.text.strip_edges().to_lower() if _filter != null else ""
	var ids: Array = []
	for id: String in GameWorld.upgrades:
		var u: Dictionary = GameWorld.upgrades[id]
		if GameWorld.boughtUpgrades.has(id) and not _repeatable(id):
			continue
		var cost = u.get("cost", {})
		if not (cost is Dictionary) or cost.is_empty() and id.find("story") == -1:
			continue
		if want != "" and id.to_lower().find(want) == -1:
			continue
		ids.append(id)
	# Story Mode's own entries first, then the rest by name.
	ids.sort_custom(func(a: String, b: String):
		var sa: bool = a.find(".story") != -1 or a.begins_with("story")
		var sb: bool = b.find(".story") != -1 or b.begins_with("story")
		if sa != sb:
			return sa
		return a < b)
	_list.clear()
	for id: String in ids:
		var cost: Dictionary = GameWorld.upgrades[id].get("cost", {})
		var price: Array = []
		for k: String in cost:
			price.append(("$" + Prices.short(int(cost[k]))) if k == "money" else "%d %s" % [int(cost[k]), k])
		var i: int = _list.add_item("%s  %s" % [id, " ".join(price)])
		_list.set_item_metadata(i, id)


func _repeatable(id: String) -> bool:
	return GameWorld.upgrades.has(id) and GameWorld.upgrades[id].get("repeatable") != null


# The shop's id for a raw upgrade id: as is, or with the team's or the local
# player's prefix. "" when the shop has none.
func _shop_id(raw: String) -> String:
	for id: String in [raw, _team() + "." + raw, Story.local_pid() + "." + raw]:
		if GameWorld.upgrades.has(id):
			return id
	return ""


func _team() -> String:
	return KeeperUpgrades.team_of(Story.local_pid())


static func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
