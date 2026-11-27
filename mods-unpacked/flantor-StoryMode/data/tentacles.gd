extends RefCounted

# The lava ocean's two climbable tentacles (#364, End game 2.0 #363). Read by
# the map generator (map/story_gen.gd place_tentacles), the tentacles
# (map/ocean_tentacles.gd) and their rig (map/tentacle_rig.gd). Everything
# here is a first-pass feel value for the user to tune.

# --- the chains ---------------------------------------------------------------
# Ten chains bind the two tentacles (#365 places the anchors). The number
# broken, 0..CHAINS, maps smoothly onto the test room's wake stages 0..4 (#359):
# 0 broken is stage 0 ("alive but held down"), 10 broken is stage 4.
const CHAINS := 10
# Per wake stage 0..4: the share of the full swing (SWEEP_TILES at the tip),
# and how fast the wave runs (the test room's numbers: its per-joint swing of
# 2, 6, 10, 15, 20 degrees is 0.1 .. 1.0 of stage 4's).
const WAKE_SHARE := [0.1, 0.3, 0.5, 0.75, 1.0]
const WAKE_SPEED := [0.8, 1.1, 1.4, 1.7, 2.0]
# Ocean tentacles are about twice as tall as the test room's, so their wave
# runs slower (they read heavier, and the tip doesn't fling a keeper off).
const TEMPO := 0.6
# A change of wake eases in: share per second and speed per second.
const EASE_SHARE := 0.08
const EASE_SPEED := 0.5

# --- the shape ----------------------------------------------------------------
# Segments run joint to joint, tapering from WIDTH_BASE at the floor to
# WIDTH_TIP under the pad, each with a round knuckle on its lower joint.
const SEG_LEN := 26.0                  # px, about; fitted so the tip lands exactly
const WIDTH_BASE := 46.0
const WIDTH_TIP := 22.0
# The tip is a rounded knuckle (map/tentacle_rig.gd Pad): a blunt dome a little
# wider than the last segment, PAD_HEIGHT long. It follows the body's lean
# (TIP_LEVEL 0). The flat club it replaced (#364's first pass, kept level so
# the Infiltrator could stand on it) was an overcorrection: the tentacles are
# for wall jumps and the Beastmaster's claws, not for standing on.
const PAD_WIDTH := 28.0
const PAD_HEIGHT := 18.0
const TIP_LEVEL := 0.0
# How far the tip swings each way at stage 4, in tiles, and the wave along the
# body (radians of phase per segment: about one and a half waves on a
# 28-segment tentacle).
const SWEEP_TILES := 5.0
const WAVE_K := 0.36

# --- placement (map/story_gen.gd) -------------------------------------------------
# Open rows kept between the ocean's rock ceiling and the pad's top: room for
# a keeper standing on the tip.
const TIP_CLEAR_ROWS := 2
# Where each tentacle wants to stand: this share of the ocean's half width out
# from the boss chamber's middle, then the nearest column that fits.
const SPREAD := 0.42
# Tiles of open lava or air kept beyond the swing's reach on each side.
const MARGIN_TILES := 1
# Columns kept clear either side of each chamber entry tile, so the dive into
# the chamber never lands on a tentacle's base.
const ENTRY_GAP := 2
# No tentacle shorter than this many tiles.
const MIN_TILES := 12
