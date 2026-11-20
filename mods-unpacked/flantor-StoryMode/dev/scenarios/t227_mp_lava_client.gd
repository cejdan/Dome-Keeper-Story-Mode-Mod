extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #227: client half. Its lava matches the host's while it flows and once it
# settles; its keeper heats up standing in it, is recalled, and the team's
# $1000 halves on the host. Pair: t227_mp_lava_host.

const TIMEOUT := 420


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var room = await shared(h, "room", 60.0)
	h.check("host dug a room", room != null, room)
	if room == null:
		return
	await h.until(func(): return Level.map.has_node("StoryLavaField"), 20.0)
	var lava = Level.map.get_node("StoryLavaField")
	h.check("client field draws the host's lava", lava.net_client)
	var a := Vector2i(int(room[0]), int(room[1]))
	# The host's digging reaches the client as tile messages that can land
	# after the share itself (#249: reading it at once was flaky).
	var open: bool = await h.until(func(): return Level.map.is_tile_empty(a + Vector2i(1, 1)), 15.0)
	h.check("room open on the client", open, a)
	await h.teleport_tile(a + Vector2i(1, 1))
	await h.wait(3.0)
	var vis := 0
	var vrev := 0
	for y in range(a.y, int(room[3]) + 1):
		for x in range(a.x, int(room[2]) + 1):
			if Level.map.visibleTileCoords.has(Vector2(x, y)):
				vis += 1
			if Level.map.visuallyRevealedTiles.has(Vector2(x, y)):
				vrev += 1
	h.note("client state", Network.local_connection_state)
	h.note("room on the client", {"visible": vis, "visually revealed": vrev, "cells": (int(room[2]) - a.x + 1) * (int(room[3]) - a.y + 1)})
	await h.shot("client_in_room")
	var worst := 0.0
	for i in 8:
		await h.wait(1.0)
		var hs = await shared(h, "lava")
		var mine: float = _total(lava)
		var rel: float = absf(mine - float(hs["total"])) / maxf(1.0, float(hs["total"]))
		worst = maxf(worst, rel)
		h.note("flowing %d" % i, {"host total": hs["total"], "client total": mine, "host n": hs["n"], "client n": lava.mass.size()})
	h.check("lava total tracks the host while it flows (within 5%)", worst < 0.05, worst)
	await h.shot("client_flowing")
	var fin = await shared(h, "lava_final", 90.0)
	await h.wait(1.0)
	var diff := 0
	var biggest := 0.0
	for e in fin["upper"]:
		var c := Vector2i(int(e[0]), int(e[1]))
		var d: float = absf(lava.mass.get(c, 0.0) - float(e[2]))
		biggest = maxf(biggest, d)
		if d > 0.01:
			diff += 1
	h.note("settled", {"host n": fin["n"], "client n": lava.mass.size(), "host total": fin["total"], "client total": _total(lava), "cells off": diff, "biggest": biggest})
	h.check("settled lava matches the host cell by cell", diff == 0, [diff, biggest])
	# #228: rock the host's lava melted (Map.destroyTile, not a hit) is open here too.
	var melt = await shared(h, "melt", 5.0)
	h.check("host melted a rock with lava", melt != null and bool(melt[2]), melt)
	if melt != null:
		var mc := Vector2i(int(melt[0]), int(melt[1]))
		h.check("rock melted by lava is open on the client", Level.map.getTile(Vector2(mc)) == null and Level.map.is_tile_empty(mc), mc)
	# Heat: stand in the lava until the suit recalls.
	var hot = null
	for c in lava.mass:
		if lava.mass[c] >= 0.8 and c.y < 60 and Level.map.is_tile_empty(c + Vector2i.UP):
			hot = c
			break
	h.check("a lava cell to stand in", hot != null, hot)
	if hot == null:
		return
	var money0 = Data.ofOr("team1.inventory.money", 0)
	await h.teleport_tile(hot)
	await h.wait(1.5)
	h.note("heat after 1.5 s in lava", lava.heat)
	h.check("client keeper heats up in lava", lava.heat > 0.0, lava.heat)
	await h.shot("client_in_lava")
	var recalled: bool = await h.until(func(): return h.keeper_tile().y < 0, 120.0)
	h.check("client keeper recalled to the dome", recalled, h.keeper_tile())
	await h.wait(2.0)
	var money1 = Data.ofOr("team1.inventory.money", 0)
	h.check("the host took half the money", int(money1) == int(money0) / 2, [money0, money1])
	await h.shot("client_recalled")


static func _total(lava) -> float:
	var t := 0.0
	for c in lava.mass:
		t += lava.mass[c]
	return t
