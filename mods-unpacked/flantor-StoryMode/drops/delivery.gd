extends RefCounted

# How the dome takes each Story Mode drop type (#327). Vanilla knows only its
# own types: the dome's shredder area asks a drop "are you iron / water / sand
# / pack?", the relic socket "are you a relic?", and Dome.getDropTarget(type)
# names the target that taking a dome station (Keeper.enterStation) and the
# transport drones send a drop to. A type it does not know gets no target:
# enterStation still lets go of it as "on its way", so it can't be picked up
# again and falls down the shaft.
#
# So every mod drop type is registered here with the vanilla type it is
# delivered as: minerals and miner bones go to the shredder as iron (and are
# credited as themselves), a translator to the relic socket. The dome
# (extensions/content/dome/Dome.gd, dome3.gd) and the drops' trigger
# (StoryDropTrigger.gd) both read it, so a new drop type registered here works
# at the station, the shredder and the socket alike.

static var _as: Dictionary = {}

# How far (px) a drop on its way to the dome may wander and still count as not
# moving (resolve_stuck).
const STUCK_SLACK := 2.0


# Adds `type` to the game's drop tables with its scene, delivered as `as_type`.
static func register(type: String, scene: PackedScene, as_type: String) -> void:
	if not Data.DROP_TYPES.has(type):
		Data.DROP_TYPES.append(type)
	Data.DROP_SCENES[type] = scene
	_as[type] = as_type


# The vanilla type `type` is delivered as (itself for vanilla types).
static func as_vanilla(type: String) -> String:
	return _as.get(type, type)


# Vanilla's stuck check for a drop on its way to its target
# (Drop.processIndependantStuckResolver): once it has not moved for a second,
# it stops colliding with rock and the dome's border and passes through to
# its target. "Not moved" there means exactly the same position, but a drop
# pushed up against a body that won't give (a translator still carried while
# the keeper sits at the computer: the paused world freezes it) jitters a
# little every frame, so it never counts as stuck and stays wedged there,
# unpickable (#327). Here it counts as stuck while it stays within
# STUCK_SLACK of where it stopped. Called where vanilla's would be: each
# physics frame of a drop that is on its way, and only then.
static func resolve_stuck(drop, delta: float) -> void:
	var p: Vector2 = drop.position
	if p.distance_squared_to(drop.lastIndependantPos) <= STUCK_SLACK * STUCK_SLACK:
		drop.independantTimeSinceLastMove += delta
		if drop.independantTimeSinceLastMove > 1.0:
			drop.set_collision_mask_value(CONST.LAYER_DROP_COLLISION, false)
			drop.set_collision_mask_value(CONST.LAYER_DROP_DOME_BORDER, false)
	else:
		drop.independantTimeSinceLastMove = 0.0
		drop.lastIndependantPos = p
