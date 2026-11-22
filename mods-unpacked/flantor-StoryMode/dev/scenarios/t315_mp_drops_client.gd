extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #315, client half: the water drop the host's lava uses up and the charge
# that goes off on the host are each seen here first, then gone here too
# (before #315 both stayed drawn on a client). Pair: t315_mp_drops_host.

const TIMEOUT := 300


func boot() -> Dictionary:
	return {"netjoin": true}


# The drop with this UID, as this instance has it: null once it is gone
# (out of the drop synchronizer and no node left in Level.drops).
func _drop(uid: int):
	if Level.drops.has_drop(uid):
		var d = Level.drops.get_drop(uid)
		if is_instance_valid(d) and not d.is_queued_for_deletion():
			return d
	for d in Level.drops.get_children():
		if "UID" in d and d.UID == uid and not d.is_queued_for_deletion():
			return d
	return null


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var rooms = await shared(h, "rooms", 150.0)
	h.check("the host dug the rooms", rooms != null)
	if rooms == null:
		return
	var br: Array = room_of(rooms["bomb"])
	await h.teleport_tile(br[0] + Vector2i(1, 0))
	h.snap_camera()

	# ---- the water drop
	var uid: int = int(await shared(h, "water", 30.0))
	var has: bool = await h.until(func(): return _drop(uid) != null, 15.0)
	h.check("the host's water drop is here", has, uid)
	await h.shot("client_water_before")
	var used = await shared(h, "water_used", 40.0)
	h.check("the host used the water up", used == true)
	var gone: bool = await h.until(func(): return _drop(uid) == null, 5.0)
	h.check("the used-up water drop is gone on the client too", gone, {"uid": uid, "drop": str(_drop(uid))})
	await h.shot("client_water_after")

	# ---- the charge
	uid = int(await shared(h, "bomb", 40.0))
	has = await h.until(func(): return _drop(uid) != null, 15.0)
	h.check("the host's charge is here", has, uid)
	await h.wait(0.5)
	await h.shot("client_bomb_before")
	await shared(h, "bomb_lit", 30.0)
	var lit: bool = await h.until(func(): return _drop(uid) == null or bool(_drop(uid).activated), 3.0)
	h.check("the lit fuse shows on the client", lit and _drop(uid) != null, str(_drop(uid)))
	await h.wait(0.5)
	await h.shot("client_bomb_lit")
	gone = await h.until(func(): return _drop(uid) == null, 8.0)
	h.check("the spent charge is gone on the client too", gone, {"uid": uid, "drop": str(_drop(uid))})
	await h.burst("client_bomb_blast", 6, 4)
	await shared(h, "done", 30.0)

