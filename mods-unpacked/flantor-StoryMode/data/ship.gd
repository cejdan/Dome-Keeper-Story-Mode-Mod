extends RefCounted

# The ship (#368, End game 2.0 map #363): the Halcyon Minerals pickup vessel
# the horror holds in the lava ocean, coiled in a third, much bigger tentacle,
# and sets down beside the dome at the last chain. endgame/ship.gd runs it and
# endgame/ship_art.gd draws it (placeholder art until #371). Every value here
# is a design call for the user to review (#368 PR, "Design calls made").
# Pixels are the world's, not the screen's.

# --- in the ocean ----------------------------------------------------------------
# The ship hangs over the chamber's middle column, its centre OCEAN_LIFT_PX
# above the lava's surface (so the hull, the bridge and the coil's grip are
# in the air band and the belly and the legs are in the lava), nose up by
# OCEAN_TILT radians. The whole grip sways round a pivot deep in the lava.
const OCEAN_LIFT_PX := 6.0
const OCEAN_TILT := -0.10
const SWAY_PIVOT := Vector2(0.0, 300.0)   # ship space: where the coil's body leaves the deep
const SWAY_ANGLE := 0.022                  # radians each way
const SWAY_SPEED := 0.33                   # radians of the sway clock a second
const BOB_PX := 3.5
const BOB_SPEED := 0.52
const SQUEEZE_SPEED := 0.9                 # the coil's grip tightening and easing
# The coil: the tentacle's body thickness from the deep to the tip, along its
# path (endgame/ship_art.gd COIL). The root is far wider than the climbable
# ocean tentacles (46 px): it sells how big the horror is.
const COIL_ROOT_W := 104.0
const COIL_BAND_W := 38.0
const COIL_TIP_W := 9.0
# Under the lava the coil and the ship soak (scorched, with a hot rim) and
# fade out FADE_FROM..FADE_TO px under the surface, into the deep.
const FADE_FROM := 150.0
const FADE_TO := 330.0
const SOAK_PX := 18.0                      # px under the surface to fully soaked
# Depth: everything in the ocean group is darkened toward the lava's haze a
# little, so it reads as behind the climbable tentacles and the anchors.
const DEPTH_TINT := Color(0.55, 0.16, 0.10)
const DEPTH_MIX := 0.18

# --- the placeholder move (until #367's cutscene) -----------------------------------
# At the last chain: the coil drags the ship under the lava (OCEAN_SINK_S),
# then the ground beside the dome cracks and the ship is pushed up out of it
# (DOME_RISE_S), legs out, a thud and dust. LAND_DELAY_S after the last chain.
const OCEAN_SINK_S := 2.6
const LAND_DELAY_S := 1.4
const DOME_RISE_S := 2.2
const DOME_RISE_FROM_PX := 150.0           # how deep under the ground it starts

# --- at the dome ------------------------------------------------------------------
# The ship stands on the ground on the dome's left (the station is on the right
# in every dome), nose toward the dome, TUBE_GAP_PX of boarding tube between its
# nose door and the dome's glass. Its legs are LEG_PX long.
const SIDE := -1.0
# The world's dusk on its hull (the game's own sprites take each world's
# palette; the placeholder's flat colours are tinted toward it instead).
const DOME_TINT := Color(0.84, 0.80, 0.92)
const TUBE_GAP_PX := 54.0
const LEG_PX := 22.0
# Boarding: a hatch in the dome's glass on the ship's side, at keeper height. A
# keeper inside the dome within HATCH_REACH_PX of the glass gets the hatch's
# focus (it wins over anything else there) and boards by holding the use key
# for BOARD_HOLD_S in all (vanilla's own hold, which starts after 0.3 s).
const HATCH_UP_PX := 13.0                  # the hatch's middle over the dome's floor
const HATCH_REACH_PX := 18.0
const BOARD_HOLD_S := 1.1
const LOCKED_LINE_EVERY := 2.5             # s between the locked line's repeats

# --- lift-off --------------------------------------------------------------------
# The keeper goes through the tube (WALK_S), the nose shuts and the tube folds
# away (SHUT_S), the engines light (SPOOL_S), the ship lifts slowly, pitches
# its nose up and climbs out of sight (CLIMB_S). Every local camera leans
# toward it by CAM_LEAN (0..1) and comes back for the ending.
const WALK_S := 0.9
const SHUT_S := 0.7
const SPOOL_S := 1.2
const CLIMB_S := 3.4
const CLIMB_PX := 900.0
const CAM_LEAN := 0.55
const SHAKE := 9.0

# --- the ship itself (placeholder art) ---------------------------------------------
const HULL := Color("8a96a3")
const HULL_MID := Color("5f6b78")
const HULL_DARK := Color("343c48")
const OUTLINE := Color("151a22")
const BRAND := Color("f2b632")             # Halcyon yellow
const BRAND_DARK := Color("a8721c")
const GLASS := Color("7fe0ff")
const GLASS_DARK := Color("2a5a74")
const WINDOW_LIT := Color("ffd98a")
const NAV_RED := Color("ff4a3a")
const NAV_GREEN := Color("5dff7a")
const BEACON := Color("fff4d0")
const PLUME := Color("9fe8ff")
const PLUME_CORE := Color("ffffff")
const HATCH_OPEN := Color("5dff7a")
const HATCH_LOCKED := Color("ff4a3a")
const HATCH_FOCUS := Color("ffd24a")
