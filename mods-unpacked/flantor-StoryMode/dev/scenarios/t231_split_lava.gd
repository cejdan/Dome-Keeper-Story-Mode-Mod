extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #231: lava on player 2's screen is drawn when it is on player 2's screen.
# The user saw lava pop in late on player 2's view: the lava field drew only
# the cells in the first split view (player 1's camera), so lava under player
# 2 appeared only once player 1's view came near it. Keeper 1 stays in the
# dome; keeper 2 jetpacks up a shaft past a lava pool far below keeper 1's
# view. Each frame of a burst shows both views at once; player 2's half must
# show the pool's orange from the first frame. `-Extra "--oldcull"` brings
# back the old culling (first view only) to show the bug.

const TIMEOUT := 300
const Split = preload("res://mods-unpacked/flantor-StoryMode/dev/scenarios/t231_split_restart.gd")


func boot() -> Dictionary:
	return {"loadout": true, "splitscreen": true}


func run(h) -> void:
	if not await Split.start_split(h):
		return
	var old: bool = "--oldcull" in OS.get_cmdline_user_args()
	var k2 = Keepers.getLocalKeeperByDeviceId(1)
	var lava = Level.map.get_node("StoryLavaField")
	# No gas (a gas fire is orange too). The map's own lava stays: the field
	# culls only while it holds more cells than a view shows (with a handful
	# it draws them all), and a real map holds hundreds.
	lava.magma.clear()
	lava.freeze_flow = true
	h.note("lava cells on the map", lava.shown.size())
	var gas = Level.map.get_node("StoryGasField")
	gas.rock.clear()
	gas.mass.clear()
	gas.fire.clear()
	gas.freeze_flow = true
	lava.single_view_cull = old
	h.note("culling", "first view only (old)" if old else "every view")
	# A shaft at x = -9 from row 14 to 30, with a lava pool at its foot that
	# fills the shaft's bottom three rows and a wide chamber beside it.
	var x0 := -9
	await h.dig_room(Vector2i(x0 - 4, 26), Vector2i(x0 + 4, 30))
	await h.dig_room(Vector2i(x0, 12), Vector2i(x0 + 1, 25))
	for y in range(28, 31):
		for x in range(x0 - 4, x0 + 5):
			lava.mass[Vector2i(x, y)] = 1.0
			lava.shown[Vector2i(x, y)] = 1.0
	lava.wake_all()
	# Keeper 2 hangs over the pool, out of reach of its heat.
	await h.teleport_tile(Vector2i(x0, 25), k2)
	k2.set("gravity_scale", 0.0)
	await h.wait(1.0)
	h.snap_camera(k2)
	await h.frames(3)
	var cells: Array = lava._visible_cells()
	h.note("drawn cells", {"n": cells.size(), "views": lava._view_boxes})
	var pool_drawn: bool = cells.has(Vector2i(x0, 29))
	if old:
		h.check("old culling: the pool under keeper 2 is NOT drawn (the bug)", not pool_drawn, cells.size())
	else:
		h.check("the pool under keeper 2 is drawn", pool_drawn, cells.size())
	await h.burst("both_views", 6, 2)
	var orange: Array = _orange(h)
	h.note("orange pixels [left view, right view]", orange)
	if old:
		h.check("old culling: no lava on player 2's view", orange[1] < 50, orange)
	else:
		h.check("lava shows on player 2's view the same frame", orange[1] > 400, orange)
		h.check("keeper 1's view shows no lava (it is far away)", orange[0] < 50, orange)
	# Keeper 2 flies up the shaft: the pool leaves its view smoothly, drawn
	# while it is on screen.
	await h.pad_stick(1, Vector2(0, -1), 0.1)
	k2.set("gravity_scale", 1.0)
	h.pad(1, "ui_up", true)
	await h.burst("flying_up", 8, 4)
	h.pad(1, "ui_up", false)


# Lava-orange pixels in the left and right halves of the window now.
func _orange(h) -> Array:
	var img: Image = h.get_viewport().get_texture().get_image()
	var n := [0, 0]
	var half: int = img.get_width() / 2
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c: Color = img.get_pixel(x, y)
			if c.r > 0.8 and c.g > 0.2 and c.g < 0.6 and c.b < 0.2:
				n[0 if x < half else 1] += 1
	return n
