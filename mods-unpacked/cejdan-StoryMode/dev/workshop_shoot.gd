extends RefCounted

# Ticket 289: helpers for the Workshop footage scenarios (t289_workshop_*).
# They run under Godot's Movie Maker (--write-movie, --fixed-fps): every
# frame is written, so the footage is smooth however slow the capture is.
# "clip <name>" notes carry the frame number to cut at.


# Fullscreen on the last screen (1920x1080 there): the game draws at exactly
# 4 screen pixels per art pixel, so frames stay crisp. The game applies its own
# window option after launch, so this runs from the scenario.
static func window_1080() -> void:
	var screen: int = DisplayServer.get_screen_count() - 1
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_current_screen(screen)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


static func clip(h, name: String) -> void:
	h.note("clip " + name, {"frame": Engine.get_frames_drawn()})


# The top-left cell of a w x hh rect (plus a margin of 2) of solid, breakable
# rock in one of `biomes`, searching rows y0..y1 and columns x0..x1.
static func find_rock(td, w: int, hh: int, biomes: Array, y0: int, y1: int, x0: int, x1: int) -> Vector2i:
	for oy in range(y0, y1):
		for ox in range(x0, x1):
			if not biomes.has(td.get_biomev(Vector2i(ox, oy))) or not biomes.has(td.get_biomev(Vector2i(ox + w, oy + hh))):
				continue
			var ok := true
			for y in range(oy - 2, oy + hh + 2):
				for x in range(ox - 2, ox + w + 2):
					var c := Vector2i(x, y)
					if td.get_biomev(c) < 0 or td.get_resourcev(c) == Data.TILE_EMPTY or td.get_resourcev(c) == Data.TILE_BORDER or td.get_hardnessv(c) >= Data.HARDNESS_INDESTRUCTIBLE:
						ok = false
						break
				if not ok:
					break
			if ok:
				return Vector2i(ox, oy)
	return Vector2i(-9999, -9999)


# No magma or gas rock of the map's own in the rect (plus a margin): the set
# shows only what the scenario puts there.
static func clear_hazards(lava, gas, o: Vector2i, w: int, hh: int) -> void:
	for y in range(o.y - 3, o.y + hh + 3):
		for x in range(o.x - 3, o.x + w + 3):
			var c := Vector2i(x, y)
			if lava != null:
				lava.magma.erase(c)
			if gas != null:
				gas.rock.erase(c)


# The rect's cells.
static func rect(o: Vector2i, w: int, hh: int) -> Array:
	var out: Array = []
	for y in range(o.y, o.y + hh):
		for x in range(o.x, o.x + w):
			out.append(Vector2i(x, y))
	return out
