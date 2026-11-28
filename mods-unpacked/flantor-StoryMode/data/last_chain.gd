extends RefCounted

# The last-chain cutscene (#367, End game 2.0 map #363): the horror hands the
# ship over. endgame/last_chain.gd runs it; every value here is a design call
# for the user to review (#367 PR, "Design calls made"). Seconds are play-frozen
# seconds (the cutscene runs while play is held); pixels are the world's.

# --- the ocean: the coil drags the ship under ----------------------------------------
const HOLD_S := 1.5               # on the ocean before the camera rises
const RELEASE_AT := 0.35          # into the hold: the coil (and the ship in it) starts to sink
const OCEAN_LEAN := 0.45          # how far each camera leans from its keeper toward the ship
const OCEAN_LEAN_RANGE := 1100.0  # px: a keeper farther from the ship than this doesn't lean

# --- the rise: every camera eases up to the dome --------------------------------------
# Longer for a longer way up, within RISE_MIN_S..RISE_MAX_S; the view pulls
# back by ZOOM_DIP (a share of its zoom) halfway, for the sense of the depth.
const RISE_MIN_S := 2.4
const RISE_MAX_S := 3.8
const RISE_PX_PER_S := 1500.0
const ZOOM_DIP := 0.32
# Something huge moves up through the rock with the camera: violet light in
# the cracks, a glow, dust (GLINTS_PER_S of them round its head).
const BURROW_GLOW_R := 46.0
const GLINTS_PER_S := 26.0
const BURROW_LEAD := 0.06         # the head runs this share of the way ahead of the camera

# --- at the dome --------------------------------------------------------------------
# The shot: its middle SHOT_LEFT px left of the dome's middle (the surface's
# backdrop ends not far past the ship: a shot further left shows its edge),
# SHOT_W x SHOT_H world px at least, the ground SHOT_DROP px under its middle,
# at most SHOT_MAX_ZOOM.
const HOLE_BACK := 110.0          # the hole: this far left of where the ship stands (under its tail)
const SHOT_LEFT := 75.0
const SHOT_W := 640.0
const SHOT_H := 420.0
const SHOT_DROP := 150.0
const SHOT_MAX_ZOOM := 4.0
const CRACK_S := 1.0              # the ground cracks and glows
const BURST_S := 0.6              # it breaks out with the ship
const CARRY_S := 1.9              # it swings the ship over toward the dome
const SET_S := 0.45               # and sets it down
const MEND_S := 1.0               # the burns heal over, the lights come on
const RELEASE_S := 1.6            # it uncoils and pulls back into the ground
const DOCK_S := 0.7               # the boarding tube comes out (the ship's own)
# Where the ship goes (from the hole, ship centre): under the ground, the top
# of the burst, then it hovers HOVER_PX over its spot before it is set down.
const START_UNDER := Vector2(10.0, 170.0)
const PEAK := Vector2(40.0, -150.0)
const HOVER_PX := 26.0
const START_TILT := -1.15         # radians, nose up
const PEAK_TILT := -0.55
const DIP_TILT := 0.10            # the nose dips as it comes down
# The arm from the hole to the coil: ARM_ROOT_W wide at the ground (the coil's
# own band width at the ship, ShipData.COIL_BAND_W, at the other end).
const ARM_ROOT_W := 74.0
const SHAKE_RISE := 6.0
const SHAKE_CRACK := 12.0
const SHAKE_BURST := 22.0
const SHAKE_SET := 10.0

# --- the beat and back ---------------------------------------------------------------
const BEAT_ID := "last_chain"     # data/beats.gd
const BEAT_DELAY_S := 0.5         # after the tube is out
const RETURN_MIN_S := 1.9
const RETURN_MAX_S := 3.2
const RETURN_PX_PER_S := 1800.0
# When play resumes, a keeper in the lava is cooled to at most this share of a
# full heat bar: the cutscene took the player's eyes off a hot suit.
const RESUME_HEAT_MAX := 0.7

# --- skipping ----------------------------------------------------------------------
# Hold the use key (or accept) this long, once SKIP_AFTER_S in: the ship is set
# down at once and the beat plays. Online, only the host can skip, for everyone.
const SKIP_AFTER_S := 1.2
const SKIP_HOLD_S := 0.8
