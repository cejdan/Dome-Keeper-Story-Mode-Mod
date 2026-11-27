extends RefCounted

# The chain anchors (#365, End game 2.0 #363): ten round stones in the lava
# ocean, five per tentacle, each holding one chain to its tentacle. Breaking
# an anchor snaps its chain and wakes the tentacles a little more
# (map/ocean_tentacles.gd); the tenth is "the last chain" (endgame/end_game.gd).
# Read by the map generator (map/story_gen.gd place_anchors), the tile
# (extensions/content/map/tile/Tile.gd), the map (extensions/content/map/Map.gd)
# and the anchors' node (map/chain_anchors.gd). Every value here is a
# first-pass feel value for the user to tune.

const TYPE := "chainanchor"
const TILE_ID := 51

# --- placement ------------------------------------------------------------------
# Each anchor is a 2 x 2 block of tiles. Per tentacle, one anchor per entry of
# HEIGHTS: that share of the way up the tentacle (0 its base, 1 its tip row),
# on the side in SIDES (1 out toward the map's edge, -1 in toward the boss
# chamber's middle), as near the tentacle as fits outside its swing (the
# generator's reach, which already keeps a tile of margin) with rock in reach.
# Low on the floor and high under the ceiling on the inner side, three up the
# outer wall: the tentacle held down from every side, and every anchor by
# rock a climber can get to (the open middle has no walls).
const PER_TENTACLE := 5
const HEIGHTS := [0.06, 0.3, 0.52, 0.74, 0.97]
const SIDES := [-1, 1, 1, 1, -1]
const SIZE := 2
# Rows above and below the wanted row an anchor may sit, first strictly, then
# looser.
const BANDS := [2, 4, 7]
# Before giving up on rock in reach, a last, wider band.
const BAND_LAST := 12
# Farthest an anchor may sit from its tentacle's column, in tiles.
const MAX_OUT := 24
# Open tiles kept between two anchors.
const GAP := 2
# An anchor may sit half in the ocean's rock wall, floor or ceiling, set into
# it; at least this many of its four tiles are open, so it shows.
const MIN_OPEN := 2
# Two anchors on the same side of one tentacle are at least this many rows
# apart, so no chain runs behind another anchor.
const SAME_SIDE_ROWS := 5
# The Beastmaster climbs rock and grabs within its claws' reach (keeper4
# Tentacles.REACH, 65 px): an anchor is "supported" when rock is within this
# many tiles of it, or the tentacle at rest is within CLAW_REACH px.
const SUPPORT_TILES := 2
const CLAW_REACH := 60.0
# The chain meets the tentacle this many tiles above the anchor's middle, so
# it pulls the tentacle down and out.
const ATTACH_RISE := 2.5

# --- breaking ---------------------------------------------------------------------
# Extra health over a plain tile at the same depth (base 3, so 3 more is twice
# a plain rock there; the four tiles share every hit, so the anchor breaks as
# one).
const EXTRA_HEALTH := 3.0
# The tentacles' flinch when a chain snaps: the swing jumps by this share of
# the full sweep (capped at the full sweep) and the wave speeds up, then both
# ease back to the new wake (data/tentacles.gd EASE_SHARE, EASE_SPEED).
const FLINCH_SHARE := 0.3
const FLINCH_SPEED := 1.2
# The camera's nudge at the break (InputSystem.shake strength, seconds,
# period), falling off with distance.
const SHAKE := [14.0, 0.5, 18.0]


static func register() -> void:
	Data.TILE_ID_TO_STRING_MAP[TILE_ID] = TYPE
