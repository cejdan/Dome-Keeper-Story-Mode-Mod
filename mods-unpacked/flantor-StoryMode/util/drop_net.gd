extends RefCounted

# Using up a drop (a carryable in Level.drops) the networked way (#315).
#
# Vanilla's drop synchronizer never removes a drop from clients because the
# host freed it: a host-side queue_free (or Drop.remove()) leaves the drop
# drawn on every client screen. Vanilla sends the removal itself
# (Level.drops.network_free_drop, as Spore.gd and ResourceGrabber.gd do), and
# so does this. Host only; untyped, so it compiles before and after the
# extensions (installer.gd).


# On the host: drops `d` from whoever carries it on every peer, takes it out
# (Drop.remove() for a resource drop, so its floating count goes down) and
# frees it on every client. Safe to call on a drop already freed on the host
# (CaveBomb.explode frees itself): the clients still get the removal.
static func consume(d) -> void:
	if not is_instance_valid(d) or not d.multiplayer.is_server():
		return
	var drops = Level.drops
	var uid: int = int(d.get("UID")) if "UID" in d else -1
	var networked: bool = drops != null and not bool(d.get("isLocal")) and drops.has_drop(uid)
	if not d.is_queued_for_deletion():
		if networked:
			drops.network_drop_from_all(d)
		else:
			for k in Keepers.getAll():
				if k.carriedCarryables.has(d):
					k.dropCarry(d)
		if d.has_method("remove") and "absorbed" in d:
			d.remove()
		else:
			d.queue_free()
	if networked:
		drops.network_free_drop(uid)
