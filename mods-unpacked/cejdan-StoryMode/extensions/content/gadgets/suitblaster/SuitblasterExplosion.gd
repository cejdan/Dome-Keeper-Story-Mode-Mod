extends "res://content/gadgets/suitblaster/SuitblasterExplosion.gd"

# Records each Suit Blaster blast just before it goes off, so metal tiles can
# tell it apart from other explosions (see data/metal.gd). The blast itself is
# vanilla.

const Metal = preload("res://mods-unpacked/cejdan-StoryMode/data/metal.gd")


func explode():
	if Level.map:
		var centre: Vector2 = Vector2(Level.map.getTileCoord(global_position))
		var radius: float = Data.of(teamId + ".suitblaster.radius")
		if Data.of(teamId + ".suitblaster.directionalexplosions") and dir.length() > 0:
			var d: Vector2 = Vector2(Data.snapVectorToDirections(dir, CONST.PI_HALF))
			Metal.record_line(centre, d.round(), int(round(0.5 + pow(radius, 2) * 1.25)))
		else:
			Metal.record_circle(centre, radius)
	super()
