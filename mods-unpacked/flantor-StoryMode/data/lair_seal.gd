extends RefCounted

# The lair seal (#366): the energy over the boss chamber's two entries
# (LavaData.BOSS_CHAMBER_ENTRY, the drillable crust in the chamber's roof,
# #361). Blue and impassable until the last chain breaks (#365), then the
# smaller purple energy that lets keepers through and still stops lava.
# endgame/lair_seal.gd builds and runs it; every value here is a design call
# for the user to review (#366 PR, "Design calls made").

# --- the blue seal (before the last chain) ---------------------------------------
# Drawn over each entry's two crust tiles: a slab of energy that bulges
# CAP_PX over the crust into the lava (a dome, highest in the middle), sinks
# LIP_PX under it into the chamber and reaches OVERHANG_PX into the stone on
# either side. Pixels of the world, not the screen.
const CAP_PX := 18.0
const CAP_EDGE_PX := 4.0        # the dome's height at its ends
const LIP_PX := 8.0
const OVERHANG_PX := 3.0
# Its solid body: the crust's two cells, 2 px lower at the top (so a drill
# ray from above meets the crust tile first and its refused hit plays the
# seal's feedback) and BODY_LIP_PX into the chamber.
const BODY_TOP_INSET_PX := 2.0
const BODY_LIP_PX := 6.0

# --- touching it ---------------------------------------------------------------
# A keeper whose body comes within TOUCH_PX of the blue seal (or a drill, a
# sphere, a kunai, a claw or a blast on its crust) is thrown back: away from
# the seal's middle, mostly up, at PUSH_SPEED px/s, at most every
# TOUCH_EVERY s per keeper. A blast only crackles.
const TOUCH_PX := 3.0
const PUSH_SPEED := 300.0
const PUSH_UP := 0.85           # share of the push that is straight up
const TOUCH_EVERY := 0.22
const HIT_FX_EVERY := 0.09      # s between crackles from hits on one entry (the Assessor's beam hits every frame)
const ARC_LIFE := 0.2           # s an arc of crackle lasts
const RIPPLE_LIFE := 0.6        # s a ripple runs over the slab
const AMBIENT_ARC_EVERY := 0.7  # s between idle crackles over each slab (on average)

# --- the opening (the last chain) ------------------------------------------------
# Plays live when the last chain breaks and the seal is on a view (else the
# first time it comes on one; a load or a late join shows the purple state).
#   0 .. STRAIN_S          the blue strains: flicker, cracks of light, a rising whine
#   STRAIN_S               it breaks: a white flash, a shock ring, shards
#   .. COLLAPSE_END_S      it drains down into the lair, blue to violet to purple
#   .. SETTLE_END_S        the purple membrane settles with one slow pulse
const OPEN_DELAY_S := 0.8       # after the last chain's roar, before the strain
const STRAIN_S := 1.1
const COLLAPSE_END_S := 2.8
const SETTLE_END_S := 3.8
const SHARDS := 22
const SHAKE := [16.0, 0.9, 18.0]   # InputSystem.shake(strength, seconds, frequency) for a keeper within SHAKE_RANGE
const SHAKE_RANGE := 520.0
# A live opening shown only from Data (a client's Data before the host's RPC)
# waits this long for the live word before it just shows purple.
const DATA_GRACE := 1.0

# --- the purple membrane (after) -------------------------------------------------
# The old chamber barrier (#82): a band MEMBRANE_PX thick across the
# chamber's top edge under each entry; lava stops on it, keepers pass.
const MEMBRANE_PX := 3.0
const PASS_EVERY := 1.0         # s between pass bursts per keeper

# --- the look --------------------------------------------------------------------
const BLUE_DEEP := Color("0e2a9e")
const BLUE := Color("2f6dff")
const BLUE_LIGHT := Color("9fd8ff")
const BLUE_SPARK := Color("eaf8ff")
# The purple is the old barrier's and the chain anchors' runes (#82, #365).
const PURPLE_DEEP := Color("2e1f8f")
const PURPLE := Color("6b5cff")
const PURPLE_LIGHT := Color("b8b0ff")
const PURPLE_SPARK := Color("eeeaff")
# The seal's circuit: a line of runes along the chamber's roof between and
# beside the entries, CIRCUIT_TILES past the chamber's walls, so the whole lair
# reads as sealed; it goes dark violet with the opening.
const CIRCUIT_TILES := 2
const CIRCUIT_RUNE_EVERY := 3   # tiles between rune marks

# --- sound (the game's own files, boss/sfx.gd) -------------------------------------
# Heard within HEAR_PX of a local keeper, quieter with distance.
const HEAR_PX := 700.0
const HUM_PX := 320.0           # the sealed hum's reach
const HUM_DB := -15.0
