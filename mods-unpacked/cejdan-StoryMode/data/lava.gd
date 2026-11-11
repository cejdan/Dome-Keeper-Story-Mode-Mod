extends RefCounted

# Shared lava numbers for the user to tune. lava/lava_field.gd and the map
# generator (map/story_gen.gd) read them. All are starting values.

# --- pockets -------------------------------------------------------------------
const POCKET_MIN_DEPTH := 7            # first tile row that may hold magma
const POCKET_CELLS_PER_POCKET := 150   # one pocket per this many plain rock cells
const POCKET_SIZE_MIN := 3
const POCKET_SIZE_MAX := 6
const VOLUME_PER_MAGMA_CELL := 4.5     # cells of lava released by one magma tile
const MELT_SECONDS := 0.7              # lava contact time before magma rock melts

# --- fluid ---------------------------------------------------------------------
const TICK := 0.09                     # seconds per simulation step
const MAX_MASS := 1.0
const MAX_COMPRESS := 0.25
const MIN_MASS := 0.004
const MIN_FLOW := 0.004
const MAX_FLOW := 0.42                 # per step; keeps lava thick and slow
const SIDE_FLOW_DIVISOR := 5.0
const STICKY_MASS := 0.05              # a film this thin stops spreading sideways
const SOURCE_RATE := 0.36              # mass per step a breached magma cell emits
const COOL_PER_SECOND := 0.004         # a cooling cell loses this (a full one lasts ~4 min); see _cools()
const FILM_MASS := 0.12                # films thinner than this cool much faster
const FILM_COOL_PER_SECOND := 0.03
const MIN_Y := 1                       # lava never rises above this tile row

# --- suit heat -----------------------------------------------------------------
const BURN_MASS := 0.18                # lava this deep in the keeper's cell burns
const HEAT_PER_SECOND := 55.0
const COOL_MINE_PER_SECOND := 9.0
const COOL_DOME_PER_SECOND := 45.0
const HEAT_MAX := 100.0

# --- cooling (#41) ---------------------------------------------------------
# A lava cell cools only when the cell below holds no lava and its top is open
# to air: the cell above is open and holds no lava, or the cell itself isn't full.
# "Holds lava" means at least HOLDS_MASS; "full" means at least FULL_MASS.
const HOLDS_MASS := 0.12
const FULL_MASS := 0.9

# --- open pools (#42) ------------------------------------------------------
# Enclosed caverns already brim-full of standing lava, carved at map generation.
const POOL_START_BIOME := 4            # B5, the first biome past the gate (per-tile biome check)
const POOL_SIZE_TOP := 6               # cells in a pool at the top of B5 ...
const POOL_SIZE_BOTTOM := 40           # ... growing linearly to this at the map bottom
const POOL_ROCK_PER_POOL := 400.0      # one pool per this many plain rock cells at the top ...
const POOL_FREQ_BONUS_AT_BOTTOM := 0.5 # ... and 50% more often at the bottom
const POOL_GAP := 2                    # rock tiles kept between a pool and anything open or special

# --- lava ocean (#43) -------------------------------------------------------
# Below B8: a rock ceiling row, then OCEAN_ROWS of open cells across the map's
# full width, brim-full of lava from the start, with unobtainium scattered
# inside; then the ocean floor and, centred under it, a sealed boss chamber.
const OCEAN_ROWS := 50
const OCEAN_UNOB_CELLS_PER_TILE := 60.0   # about one unobtainium tile per this many ocean cells
const OCEAN_UNOB_CLUMP := [1, 3]
const OCEAN_FLOOR_ROWS := 2               # rock under the ocean (1 row over the chamber)
const BOSS_CHAMBER := Vector2i(20, 10)    # width x height, empty and sealed
const BOSS_CHAMBER_WALL := 2

# --- passive heat (#46) ----------------------------------------------------
# The suit heats slowly from depth alone, out of lava, in B4 and deeper (a
# per-tile biome check). The rate grows linearly from 0 at the top row of B4 to
# PASSIVE_HEAT_RATE_AT_BOTTOM at the lava ocean's ceiling (the map's last row
# until the ocean exists). Heat Shielding's passive multiplier scales it.
const PASSIVE_HEAT_START_BIOME := 3
const PASSIVE_HEAT_RATE_AT_BOTTOM := 2.2

# --- water hardens lava (#47) ---------------------------------------------
# A water drop that touches lava (a cell with at least BURN_MASS) is used up and
# turns up to this many connected lava cells, nearest first, into plain rock.
const WATER_HARDENS_CELLS := 6
const STEAM_SECONDS := 0.7

# --- heat resistance (#44) -------------------------------------------------
# Heat Shielding I-IV, sold in the Story Mode shop. Index = tier (0 = none).
# The max tier still burns in lava (just slower) but blocks passive heat.
# Tier IV's lava multiplier was tuned by #43's dive (ceiling to boss chamber,
# base speed, ~24 s in lava): 0.06 gives 30 s of lava, so tier IV arrives under
# 100% heat and tier III (9 s) doesn't.
const HEAT_SHIELD_LAVA_MULT := [1.0, 0.6, 0.35, 0.2, 0.06]
const HEAT_SHIELD_PASSIVE_MULT := [1.0, 0.6, 0.3, 0.1, 0.0]
const HEAT_SHIELD_PRICES := [200, 1000, 4000, 25000]
# The keeper's tier lives in Data under <team>.suit.heatshield (set by the upgrades).
const HEAT_SHIELD_KEY := "suit.heatshield"


static func shield_tier(teamId: String = "team1") -> int:
	return clampi(int(Data.ofOr(teamId + "." + HEAT_SHIELD_KEY, 0)), 0, HEAT_SHIELD_LAVA_MULT.size() - 1)


static func lava_heat_mult(teamId: String = "team1") -> float:
	return float(HEAT_SHIELD_LAVA_MULT[shield_tier(teamId)])


static func passive_heat_mult(teamId: String = "team1") -> float:
	return float(HEAT_SHIELD_PASSIVE_MULT[shield_tier(teamId)])
