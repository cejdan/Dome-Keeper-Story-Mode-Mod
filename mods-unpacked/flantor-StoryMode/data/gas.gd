extends RefCounted

# Shared noxious gas numbers for the user to tune (#198). gas/gas_field.gd and
# the map generator read them. All are starting values.

# --- hidden pockets ------------------------------------------------------------
# Gas rock inside plain rock, from biome index POCKET_START_BIOME (1 = B2) down
# to the lava ocean's ceiling. One pocket per POCKET_ROCK_PER_POCKET[0] plain
# rock cells at the first gas biome, falling evenly to [1] at B8 (more gas
# deeper). A pocket is POCKET_SIZE cells, plus one for every POCKET_GROW_ROWS
# rows of depth.
const POCKET_START_BIOME := 1
const POCKET_LAST_BIOME := 7
const POCKET_ROCK_PER_POCKET := [260.0, 130.0]
const POCKET_SIZE := [3, 6]
const POCKET_GROW_ROWS := 40.0
const VOLUME_PER_ROCK_CELL := 3.0      # cells of gas released by one gas rock tile
const CRACK_SECONDS := 0.18            # a breached pocket bursts: each gas rock cell next to a broken one breaks this much later

# --- sealed caverns (#201) -----------------------------------------------------
# Enclosed caverns already full of gas, carved at map generation from biome
# index CAVERN_START_BIOME (1 = B2) down to above the lava ocean. One cavern per
# CAVERN_ROCK_PER_CAVERN[0] plain rock cells at the top of that range, falling
# evenly to [1] at its bottom; CAVERN_SIZE[0] cells at the top, growing evenly
# to [1] at the bottom. CAVERN_GAP rock tiles are kept between a cavern and
# anything open or special (lava pools, the gate, metal, story tiles, other
# caverns).
const CAVERN_START_BIOME := 1
const CAVERN_ROCK_PER_CAVERN := [700.0, 380.0]
const CAVERN_SIZE := [5, 20]
const CAVERN_GAP := 2

# --- the gas -------------------------------------------------------------------
# Seconds per simulation step: the gas's clock (#211). Gas climbs at most one
# cell a step, so a cloud in an open shaft rises at up to 1 / TICK tiles a
# second, 4.0 at 0.25: a keeper with Jetpack Speed II (3.9 tiles/s) about keeps
# pace, III (4.8) and IV (5.8) outrun it, no upgrade (2.3) and I (3.1) do not.
# It was 0.02 (50 tiles/s).
# Everything the flow does (rising, spreading under ceilings, venting, a
# breached pocket's jet) runs on this clock; the look blends between steps.
const TICK := 0.25
const COMPRESS := 0.5                  # how much more the upper of two full cells holds
const MAX_FLOW := 1.0                  # most gas one cell passes on in one direction a step
const RISE_SHARE := 0.7                # share of the balancing flow moved up each step
const SIDE_DIVISOR := 2.4              # sideways along a ceiling: this share of the difference a step
const DRIFT_DIVISOR := 16.0            # sideways while still rising (a loose cloud widens slowly)
const MIN_FLOW := 0.002
# Gas resting under rock clings to it (#212): each cell with rock above keeps
# this much gas that does not flow sideways, so low ceilings and bends trap
# part of a pocket (toxic: over TOXIC_MASS) and only the rest moves on.
# Burning it, or opening the rock above it, frees it.
const CLING_MASS := 0.5
# But it never clings toward an open cell beside it that leads up (#217): gas
# under rock next to an opening spills out into it; one cell further along the
# ceiling it sticks.
# Rising gas carries momentum (#217), counted in tiles: each tile it climbs
# adds 1 (up to RISE_MAX), each cell it moves sideways takes 1 off, and gas
# that stays put loses RISE_DECAY a step. Gas under rock with at least 1
# splashes: SPLASH_SHARE of it a step is pushed along the ceiling, out both
# ways where it hit, then on in the way it was going, whatever is there. Gas
# with momentum does not cling (fading in as it drops under 1), so gas that
# climbed a tall shaft runs along the ceiling it hits before it settles; gas
# that barely rose clings at once.
const RISE_MAX := 8.0
const RISE_DECAY := 1.0
const SPLASH_SHARE := 0.8
const MIN_PACKET := 0.012             # least gas that moves sideways into an empty cell (more than MIN_MASS, or it is dropped)
const MIN_MASS := 0.004
const SOURCE_RATE := 0.5               # gas a breached gas rock cell lets out a step ...
const SOURCE_PRESSURE := 3.0           # ... until its own cell holds this much (the jet)
const THIN_MASS := 0.07                # gas thinner than this that has stopped moving fades ...
const DECAY_PER_SECOND := 0.12         # ... at this rate
const MIN_Y := 0                       # the mine's top row; gas there with open sky above it leaves the mine
const VENT_PER_STEP := 1.0

# --- toxin (#202) --------------------------------------------------------------
const TOXIC_MASS := 0.12               # gas this dense in the keeper's cells poisons
const DENSE_MASS := 0.8                # at this density and above the bar fills at full rate
const TOXIN_PER_SECOND := 30.0         # full rate: 3.3 s from clean to recall (was 50: 2 s; #211)
const TOXIN_THIN_SHARE := 0.25         # share of the full rate at TOXIC_MASS
const CLEAR_PER_SECOND := 30.0         # out of the gas
const TOXIN_MAX := 100.0
const WARN_SHARE := 0.7                # the bar flashes and the screen greens past this

# --- fire (#204) ---------------------------------------------------------------
# Lava lights gas: a gas cell next to lava deep enough to burn catches, and the
# fire runs through the cloud, using it up. It heats the suit; it breaks nothing.
const IGNITE_MASS := 0.05              # gas this dense can burn
const LAVA_IGNITES_MASS := 0.18        # lava this deep lights gas beside it (the lava's own BURN_MASS)
# #211: an area stays alight about 3.5x as long as at first (burn 4.0, ember
# 0.4, spread [0.16, 0.06]).
const FIRE_SPREAD_SECONDS := [0.4, 0.16]    # a burning cell lights its neighbours this much later: thin gas, thick gas
const FIRE_BURN_PER_SECOND := 1.1      # gas a burning cell uses up a second
const FIRE_EMBER_SECONDS := 1.5       # a burnt-out cell still glows (and heats) this long
const FIRE_HEAT_PER_SECOND := 110.0    # suit heat a second in a burning cell, before Heat Shielding


# --- the dome's gas (#213) -----------------------------------------------------
# Gas that leaves the mine through the shaft under the dome (a top-row cell
# within DOME_HALF_WIDTH px of the dome's middle) goes into the dome and stays
# there until the shop's Vent the Dome clears it. It is counted in pockets'
# worth, DOME_POCKET_MASS of the field's gas each. While the keeper is in the
# dome, the toxin bar fills at DOME_TOXIN_PER_SECOND x pockets ^ DOME_TOXIN_POWER
# a second (and does not clear): from empty to full in about
#   1 pocket 5.5 min, 2 2 min, 3 64 s, 4 42 s, 5 30 s, 6 23 s
# so a little gas can wait, 3 pockets ought to be vented, 4 makes a wave dicey,
# 5 means a wave can't be fought through. A full bar there is a gas death (half
# the money, the horror's line) without the trip home. Under DOME_TRACE_POCKETS
# the dome's air clears the bar at once, as before #213. The haze is fully
# thick at DOME_THICK_POCKETS.
const DOME_HALF_WIDTH := 80.0
const DOME_POCKET_MASS := 10.0
const DOME_TOXIN_PER_SECOND := 0.3
const DOME_TOXIN_POWER := 1.5
const DOME_TRACE_POCKETS := 0.05
const DOME_THICK_POCKETS := 5.0


static func dome_toxin_rate(pockets: float) -> float:
	if pockets < DOME_TRACE_POCKETS:
		return 0.0
	return DOME_TOXIN_PER_SECOND * pow(pockets, DOME_TOXIN_POWER)

static func pocket_rock_per_pocket(biome: int) -> float:
	var t: float = clampf(float(biome - POCKET_START_BIOME) / float(maxi(POCKET_LAST_BIOME - POCKET_START_BIOME, 1)), 0.0, 1.0)
	return lerpf(POCKET_ROCK_PER_POCKET[0], POCKET_ROCK_PER_POCKET[1], t)


# Share of the full toxin rate in gas of this density.
static func toxin_share(density: float) -> float:
	if density < TOXIC_MASS:
		return 0.0
	return lerpf(TOXIN_THIN_SHARE, 1.0, clampf((density - TOXIC_MASS) / (DENSE_MASS - TOXIC_MASS), 0.0, 1.0))
