extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 289: Workshop footage, the lava. Run it under Movie Maker (see
# dev/workshop_shoot.gd); "clip" notes give the frames to cut at.
#
# A mine in B2/B3: a tunnel with a magma pocket at its left end, a short
# shaft down from it into a chamber. The keeper drills into the glowing
# cracks; the lava bursts out, runs along the tunnel and pours down the shaft
# into the chamber while the keeper flies clear. Then water dropped into the
# pool hisses to steam and hardens the lava into rock.
#
#   #MMMM#########      M the magma pocket          y 0..2
#   #MMMM.........      the tunnel                  y 2
#   #######.######      the shaft                   y 3..4
#   ##..........##      the chamber                 y 5..7

const Shoot = preload("res://mods-unpacked/cejdan-StoryMode/dev/workshop_shoot.gd")
const TIMEOUT := 900

var R := Vector2i.ZERO
var lava


func boot() -> Dictionary:
	return {"seed": 12345}


func _c(x: int, y: int) -> Vector2i:
	return R + Vector2i(x, y)


func _fly(h, action: String, done: Callable, timeout: float) -> void:
	h.down(action)
	await h.until(done, timeout)
	h.up(action)


func _water(at: Vector2i) -> void:
	Level.drops.network_spawn({"type": CONST.WATER, "position": Level.map.getTilePos(Vector2(at)), "team": "team1"})


func run(h) -> void:
	Shoot.window_1080()
	h.disable_waves()
	lava = Level.map.get_node("StoryLavaField")
	var gas = Level.map.get_node_or_null("StoryGasField")
	var td = Level.map.tileData
	var found: Vector2i = Shoot.find_rock(td, 16, 9, [1, 2], 12, 70, -40, 30)
	h.check("found rock in B2/B3 for the set", found.x != -9999, found)
	R = found + Vector2i(1, 1)
	h.note("set", {"origin": R, "biome": td.get_biomev(R)})
	Shoot.clear_hazards(lava, gas, found, 16, 9)
	await h.reveal(Shoot.rect(found, 16, 9))
	var open: Array = [_c(7, 3), _c(7, 4)]
	for x in range(5, 14):
		open.append(_c(x, 2))
	for x in range(3, 13):
		for y in range(5, 8):
			open.append(_c(x, y))
	await h.clear_tiles(open)
	var pocket: Array = []
	for x in range(1, 5):
		for y in range(0, 3):
			pocket.append(_c(x, y))
	lava.add_pocket(pocket)
	await h.teleport_tile(_c(6, 2))
	await h.wait(3.0)
	h.snap_camera()
	await h.wait(1.0)

	# ---- the breach
	Shoot.clip(h, "lava_sealed")
	await h.wait(2.5)
	await h.shot("sealed")
	Shoot.clip(h, "lava_drill")
	await _fly(h, "ui_left", func(): return lava.sources.size() > 0 or lava.mass.size() > 0, 30.0)
	h.check("the keeper's drill opened the pocket", lava.mass.size() > 0, lava.stats())
	Shoot.clip(h, "lava_burst")
	await h.wait(0.3)
	await _fly(h, "ui_right", func(): return h.keeper_tile().x >= R.x + 11, 5.0)
	h.keeper().set("gravity_scale", 0.0)
	await h.wait(1.5)
	await h.shot("pour")
	await h.wait(3.0)
	await h.shot("pour_late")
	await h.wait(4.0)
	await h.shot("pool")
	Shoot.clip(h, "lava_pool")
	h.note("heat", {"heat": lava.heat, "stats": lava.stats()})

	# ---- a close call: into the pool until the heat bar blinks, then out
	Shoot.clip(h, "lava_dip")
	h.keeper().set("gravity_scale", 1.0)
	await _fly(h, "ui_left", func(): return h.keeper_tile().x <= R.x + 7, 3.0)
	await _fly(h, "ui_down", func(): return lava.heat > 80.0, 8.0)
	await h.shot("dip_hot")
	await _fly(h, "ui_up", func(): return h.keeper_tile().y <= R.y + 2, 4.0)
	await _fly(h, "ui_right", func(): return h.keeper_tile().x >= R.x + 11, 3.0)
	await h.wait(2.0)
	Shoot.clip(h, "lava_dip_end")
	h.check("the keeper got hot and out", lava.recalls == 0, [lava.heat, lava.recalls])
