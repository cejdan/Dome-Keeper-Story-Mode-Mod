extends RefCounted

# Shared lava numbers for the user to tune. lava/lava_field.gd and the map
# generator (map/story_gen.gd) read them. All are starting values.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")

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
# Below B8: a rock ceiling row, then OCEAN_ROWS of open cells in a funnel
# centred under the dome, brim-full of lava from the start, with unobtainium
# scattered inside; then the ocean floor and, under its narrow end, a sealed
# boss chamber.
const OCEAN_ROWS := 25                    # was 50: half the height (#175)
# The ocean is a rough funnel (#184): its top spans the map's full width, so
# digging down from anywhere breaks into it, and it slopes down to its bottom
# row, which spans just the boss chamber and its walls plus
# OCEAN_FUNNEL_BOTTOM_MARGIN columns on each side. So the chamber is always
# under the deepest lava. Each side has its own seeded shape: a curve with an
# exponent picked from OCEAN_FUNNEL_CURVE (1 is straight, below 1 bulges out,
# above 1 caves in), plus layers of bumps in or out: layer i reaches up to
# OCEAN_FUNNEL_BUMP[i] tiles, smoothed between points OCEAN_FUNNEL_BUMP_ROWS[i]
# rows apart (big swells, then small roughness). The bumps fade out at the top
# and bottom rows.
const OCEAN_FUNNEL_BOTTOM_MARGIN := 2
const OCEAN_FUNNEL_CURVE := [0.7, 1.6]
const OCEAN_FUNNEL_BUMP := [8.0, 2.5]
const OCEAN_FUNNEL_BUMP_ROWS := [6, 2]
# Open air between the ocean's rock ceiling and the lava (#149), so breaking in
# opens onto a wide cavern, and lava from above has room to drain into.
const OCEAN_AIR_ROWS := 4
const OCEAN_UNOB_CELLS_PER_TILE := 30.0   # one unobtainium tile per this many cells of the map's full width x OCEAN_ROWS; keeps the total of the first, full-size ocean (#43: 60 per cell of a box twice as deep)
const OCEAN_UNOB_CLUMP := [1, 3]
const OCEAN_FLOOR_ROWS := 2               # rock under the ocean (1 row over the chamber)
const BOSS_CHAMBER := Vector2i(20, 10)    # width x height, empty and sealed
const BOSS_CHAMBER_WALL := 2

# --- passive heat (#46, #187) ---------------------------------------------
# The suit heats from depth alone, out of lava, from B4 down (a per-tile biome
# check; the lava ocean counts as B8). Each biome is one heat level deeper than
# the one above it, and each tier of Heat Shielding moves the scale down by one
# biome:
#     level = biome index - PASSIVE_HEAT_START_BIOME - Heat Shielding tier
# Below level 0 the depth is cool (no heat; the bar drains as in the upper
# mine). From level 0 the bar only rises, at PASSIVE_HEAT_BY_LEVEL[level]
# per second (the last entry for anything deeper):
#     0 fine (about 5 min to overheat), 1 rough (about 1 min),
#     2 practically lava (about 10 s), 3+ worse.
# So with no shielding B4 is fine, B5 rough, B6 deadly; with tier I B4 is cool,
# B5 fine, B6 rough, B7 deadly; and so on. In lava the suit heats at whichever
# is faster, the lava or the depth.
const PASSIVE_HEAT_START_BIOME := 3
const PASSIVE_HEAT_LAST_BIOME := 7       # B8; the lava ocean below it counts as B8
const PASSIVE_HEAT_BY_LEVEL := [0.33, 1.7, 10.0, 25.0]

# --- water hardens lava (#47) ---------------------------------------------
# A water drop that touches lava (a cell with at least BURN_MASS) is used up and
# turns up to this many connected lava cells, nearest first, into plain rock.
const WATER_HARDENS_CELLS := 6
const STEAM_SECONDS := 0.7

# --- heat resistance (#44) -------------------------------------------------
# Heat Shielding I-IV, sold in the Story Mode shop. Index = tier (0 = none).
# The max tier still burns in lava (just slower). Passive heat: see above.
# Tier IV's lava multiplier was tuned by #43's dive (ceiling to boss chamber,
# base speed, ~24 s in lava): 0.06 gives 30 s of lava, so tier IV arrives under
# 100% heat and tier III (9 s) doesn't.
const HEAT_SHIELD_LAVA_MULT := [1.0, 0.6, 0.35, 0.2, 0.06]
const HEAT_SHIELD_PRICES := [200, 1000, 4000, 25000]
# Each keeper has its own tier (#265), the way vanilla's keeper-tree upgrades
# are per player: Data <playerId>.suit.heatshield, set by that player's
# storyHeatShield upgrades (player2.storyheatshield1 sets player2.suit.heatshield).
# Before #265 it was the team's (team1.suit.heatshield); a save from then gives
# that tier to every keeper on load (gamemode/keeper_upgrades.gd).
const HEAT_SHIELD_KEY := "suit.heatshield"


# `who` is a keeper, a playerId ("player2"), or null for this instance's first
# keeper ("player1" while it has none).
static func shield_tier(who = null) -> int:
	return clampi(int(Data.ofOr(shield_key(who), 0)), 0, HEAT_SHIELD_LAVA_MULT.size() - 1)


# The Data key holding `who`'s tier.
static func shield_key(who = null) -> String:
	return player_id(who) + "." + HEAT_SHIELD_KEY


static func player_id(who = null) -> String:
	if who is String and who.begins_with("player"):
		return who
	if who is Object and is_instance_valid(who) and "playerId" in who:
		return str(who.playerId)
	return Story.local_pid()


static func lava_heat_mult(who = null) -> float:
	return float(HEAT_SHIELD_LAVA_MULT[shield_tier(who)])


# The heat level of biome index `biome` for `who`'s suit (see above);
# below 0 is cool.
static func passive_level(biome: int, who = null) -> int:
	return mini(biome, PASSIVE_HEAT_LAST_BIOME) - PASSIVE_HEAT_START_BIOME - shield_tier(who)


# Passive heat per second in biome index `biome` for `who`'s suit.
static func passive_rate(biome: int, who = null) -> float:
	if biome < PASSIVE_HEAT_START_BIOME:
		return 0.0
	var level: int = passive_level(biome, who)
	if level < 0:
		return 0.0
	return float(PASSIVE_HEAT_BY_LEVEL[mini(level, PASSIVE_HEAT_BY_LEVEL.size() - 1)])
