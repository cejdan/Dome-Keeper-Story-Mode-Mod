extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 352: the loadout's mode list is longer than the space vanilla's tile
# blocks carve for it (Story Mode is the last entry; Versus adds one in
# multiplayer; other mods add more), so Story Mode's entry landed in rock or
# behind the indestructible wall. Every entry must sit in open space.
# -Extra "--splitscreen" (multiplayer mode: Versus listed) and
# "--dummymodes=2" (two extra modes registered, like other mods would).


func boot() -> Dictionary:
	var b := {"loadout": true}
	if "--splitscreen" in OS.get_cmdline_user_args():
		b["splitscreen"] = true
	# Stand-ins for other mods' modes, listed after Story Mode. They reuse
	# vanilla ids so their icons load; only their place in the list matters.
	for i in int(_arg("dummymodes", "0")):
		Data.loadoutGameModes.append(["relichunt", "assignments"][i % 2])
	return b


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.split("=", true, 1)[1]
	return def


# Tiles overlapping a control's world rect.
func _tiles_under(c: Control) -> Array:
	var xf: Transform2D = c.get_global_transform()
	var r := Rect2(xf.origin, c.size * xf.get_scale())
	var a: Vector2i = Level.map.getTileCoord(r.position)
	var b: Vector2i = Level.map.getTileCoord(r.end - Vector2(0.5, 0.5))
	var out: Array = []
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			var t = Level.map.getTile(Vector2(x, y))
			if t != null and is_instance_valid(t):
				out.append([x, y, t.hardness if "hardness" in t else -1])
	return out


func run(h) -> void:
	var stage = Level.stage
	var dummies: int = int(_arg("dummymodes", "0"))
	if "--splitscreen" in OS.get_cmdline_user_args():
		await h.join_device(0)
	await h.wait(3.0)
	GameWorld.figuredOutMovementInLoadout = true
	stage.updateBlockVisibility(true)
	await h.wait(1.0)
	stage.gameModeSelected("storymode")
	await h.wait(2.0)
	var box: Control = stage.find_child("GameModeContainers", true, false)
	var entries: Array = box.get_children().filter(func(c): return not c is Label and c.visible)
	h.map_png("loadout_map", {})
	h.note("modes", {"listed": entries.map(func(e): return e.id), "multiplayer": stage.isMultiplayerMode(), "dummies": dummies})
	var xf: Transform2D = box.get_global_transform()
	h.keeper().teleport(xf.origin + box.size * xf.get_scale() * Vector2(0.5, 1.0) + Vector2(0, -12))
	await h.wait(0.5)
	await h.snap_camera()
	await h.wait(1.0)
	await h.shot("mode_list")
	for e: Control in entries:
		var under: Array = _tiles_under(e)
		h.check("entry '%s' sits in open space" % e.id, under.is_empty(), {"tiles": under, "rect": Rect2(e.get_global_transform().origin, e.size)})
