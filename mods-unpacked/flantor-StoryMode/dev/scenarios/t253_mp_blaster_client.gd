extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #253, client half: once the host has given every keeper the Suit Blaster,
# this client's keeper has it, its charge keys are here and its HUD shows.
# The error scan fails the run on SuitBlaster.gd's script error or the HUD's
# unknown-key reads. Pair: t253_mp_blaster_host.
# #261: with `--give=<gadget>` the host gives another gadget instead. Either
# way, each of the gadget's Data keys must have been here when the RPC that
# adds it arrived (GameWorld.upgradeAdded), and (#268) must stay here every
# frame after, through a full sync landing (`--fullsync`).

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
const OrderedChunker = preload("res://mods-unpacked/flantor-StoryMode/net/ordered_chunker.gd")
const TIMEOUT := 300

var _at_add: Dictionary = {}   # upgrade id -> the Data keys here when it was added
var _gone: Dictionary = {}     # Data keys here at an add that were missing in a frame after it


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var give: String = Story.user_arg("give", "suitblaster")
	GameWorld.upgradeAdded.connect(func(id: String, _team: String):
		# A team gadget's RPC carries its bare id ("drill", "team1").
		if (id == give or id.ends_with("." + give)) and not _at_add.has(id):
			_at_add[id] = Data.values.keys())
	var watch := func():
		for id in _at_add:
			for key in _at_add[id]:
				if not Data.values.has(key):
					_gone[key] = true
	h.get_tree().process_frame.connect(watch)
	var restored0: int = OrderedChunker.restored
	var given = await shared(h, "given", 150.0)
	h.check("the host gave the %s" % give, given is Dictionary, given)
	if not given is Dictionary:
		return
	await h.wait(2.0)
	var k = Story.local_keeper()
	var mine: Array = given.get("ids", []).filter(func(id): return not String(id).begins_with("player") or (k != null and String(id).begins_with(k.playerId + ".")))
	h.check("this client's keeper has the %s" % give, k != null and not mine.is_empty() and mine.all(func(id): return GameWorld.boughtUpgrades.has(id)), mine)
	if give == "suitblaster":
		var gadget = null
		if k != null:
			for c in k.get_children():
				if str(c.get_script().resource_path if c.get_script() else "").ends_with("SuitBlaster.gd"):
					gadget = c
		h.check("this client's keeper has the Suit Blaster", gadget != null, k.playerId if k else null)
		var charge = Data.ofOr(k.playerId + ".suitblaster.charge", null) if k else null
		var maxc = Data.ofOr(k.teamId + ".suitblaster.maxcharge", null) if k else null
		h.check("its charge keys reached this client", charge != null and maxc != null, {"charge": charge, "maxcharge": maxc})
	# #261: the gadget's keys were here before (or with) the RPC that added it.
	var keys: Array = given.get("keys", [])
	h.check("the host listed the gadget's Data keys", not keys.is_empty(), keys.size())
	var late: Dictionary = {}
	for id in _at_add:
		var have: Array = _at_add[id]
		for key in keys:
			# A key of another keeper's gadget is that keeper's, not this one's.
			var owner: String = String(key).get_slice(".", 0)
			if owner.begins_with("player") and not String(id).begins_with(owner + "."):
				continue
			if not have.has(key):
				late[key] = true
	h.note("upgrades added here", _at_add.keys())
	h.check("the RPC adding the %s came here (%d)" % [give, _at_add.size()], _at_add.size() >= 1, _at_add.keys())
	h.check("every %s key was here when it was added (#261)" % give, late.is_empty(), late.keys())
	h.get_tree().process_frame.disconnect(watch)
	var gone: Array = keys.filter(func(key): return _gone.has(key))
	h.check("no %s key went missing after it was added (#268)" % give, gone.is_empty(), gone)
	h.note("keys put back after a full sync landed (#268)", OrderedChunker.restored - restored0)
	await h.shot("client_blaster")
