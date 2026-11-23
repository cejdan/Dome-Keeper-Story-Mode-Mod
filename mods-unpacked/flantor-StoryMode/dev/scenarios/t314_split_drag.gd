extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 314 in splitscreen: each local Engineer (keyboard, then gamepad) drags
# vanilla iron, a Story iron piece and gold over rock and metal, pressed and
# flung as in t314_drop_drag, and the Story pieces match vanilla iron.

const TIMEOUT := 480
const D = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t314_drop_drag.gd")
const Split = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t231_split_restart.gd")


func boot() -> Dictionary:
	return {"loadout": true, "splitscreen": true}


func run(h) -> void:
	if not await Split.start_split(h):
		return
	var ks: Array = h.local_keepers()
	h.check("both local keepers are Engineers", ks.all(func(k): return k.techId == "keeper1"), ks.map(func(k): return k.techId))
	var by_floor: Dictionary = await D.make_lanes(h, ["rock", "metal"])
	if by_floor.is_empty():
		return
	for k in ks:
		var mover: Dictionary = D.keyboard_mover(h) if k.deviceId == 0 else D.pad_mover(k.deviceId)
		var who: String = "%s (device %d) " % [k.playerId, k.deviceId]
		var res := {}
		for f in ["rock", "metal"]:
			for kind in ["vanilla_iron", "iron", "gold"]:
				await D.both(h, k, by_floor[f], kind, f, mover, res, who)
		D.judge(h, res, who)
		# Out of the other keeper's lanes.
		k.teleport(Level.getDome("team1").global_position + Vector2(0, -8))
		await h.frames(5)
