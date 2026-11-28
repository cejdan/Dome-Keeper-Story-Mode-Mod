extends RefCounted

# The rising lava after the last chain (#369, End game 2.0 map #363): the
# numbers endgame/rising_lava.gd and the lava field's flood line
# (lava/lava_field.gd) read. All are first-pass values for the user to tune.

# --- the speed -----------------------------------------------------------------
# One speed for every map size, in world px a second (a tile is 24 px), so the
# chase feels the same on a small map as on a huge one: the keeper's climb
# speed doesn't change with the map either. The ticket's starting point was
# 2 minutes from the ocean to the surface; on the huge map (the ocean's lava
# 156 rows down, 3,720 px to the top of the mine) that is 31 px/s, a quarter
# of how fast the Engineer and the Beastmaster climb a shaft with the boss
# gear (127 px/s; the Assessor 155 px/s, measured by t369_probe). 55 px/s
# (2.3 rows a second) takes 68 s on the huge map: a keeper who flies straight
# up their own shaft has about half a minute to spare, one who stops to mine,
# carries a load or digs a new way out does not.
# By hand: `--rise=<seconds>` sets the time from the ocean to the surface on
# the map being played, `--risespeed=<px a second>` the speed itself.
const RISE_PX_PER_S := 55.0
# It wells up slowly at first: the speed starts at this share and reaches
# full speed over RAMP_S seconds (also after a load).
const START_SHARE := 0.25
const RAMP_S := 6.0

# --- the band ------------------------------------------------------------------
# Dug cells in this many rows at the top of the flood are real lava in the lava
# field (they flow, burn, steam, light gas, melt magma); every open cell below
# them, down to the ocean, is lava by the level alone (implied: not stored).
const BAND_ROWS := 3
# The lava's surface reaching the top of this row is "the surface": the run is
# lost unless a keeper has boarded the ship or is fighting. (Lava never sits
# above data/lava.gd MIN_Y, row 1: the dome's floor is two rows over it.)
const SURFACE_ROW := 1
# Steam off the rising surface: per band surface cell on screen, a puff this
# often a second.
const SURFACE_PUFFS_PER_S := 0.5

# --- the warning (no HUD) ------------------------------------------------------
# A rumble and a camera shake for each local keeper, growing as the lava's
# surface comes closer below it: nothing FAR_ROWS or more below, full at
# NEAR_ROWS (about the bottom edge of the screen) and in the lava.
const FAR_ROWS := 40.0
const NEAR_ROWS := 6.0
const SHAKE_MIN := 1.2           # camera shake strength at the far edge ...
const SHAKE_MAX := 6.5           # ... and near (vanilla's scale: 100 = 3 px)
const SHAKE_EVERY := 0.25        # a fresh shake this often (each lasts a little longer)
# Now and then a heavier jolt and a deep boom, more often the closer it is.
const JOLT_CLOSE := 0.45         # from this closeness (0..1) on
const JOLT_EVERY := [5.0, 1.6]   # seconds between jolts at JOLT_CLOSE and at full
const JOLT_SHAKE := 14.0
const RUMBLE_DB := [-36.0, -9.0] # the rumble loop's volume, far and near
const START_SHAKE := 16.0        # the rise begins: a roar and a big shake
const STOP_FADE_S := 2.5         # the lair: the rise stops, the rumble fades out

# --- online --------------------------------------------------------------------
const NET_EVERY := 0.2           # the host sends the level this often

# --- the "too late" loss -------------------------------------------------------
const SURFACE_HOLD_S := 2.5      # the lava at the surface: this long before the cards
const DEATH_HOLD_S := 1.6        # a keeper lost in the lava: this long before the cards
