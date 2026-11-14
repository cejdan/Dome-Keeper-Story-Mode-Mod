extends RefCounted

# The boss sequence's numbers (#160-#163): Velle's chamber fight, the chase
# back to the dome and the surface finale. Feel and balance are the user's to
# tune; everything is here in one place.

# --- keeper health (#160) ----------------------------------------------------
const HEARTS := 5
const HURT_INVULNERABLE := 1.2       # seconds safe after a hit
const HURT_KNOCKBACK := 46.0         # px the keeper is thrown
const OVERHEAT_HEAT_AFTER := 0.55    # heat (share of max) left after an overheat hit

# --- the chamber fight (#160) ------------------------------------------------
const CORE_HP := 30.0
# Velle's health at which phase 2 and phase 3 begin.
const PHASE_AT := [20.0, 10.0]
# Seconds the great eye stays open once every eye stalk is popped.
const OPEN_SECONDS := [9.0, 8.0, 7.0]
const STALKS := [3, 4, 5]             # eye stalks per phase
const STALK_HP := 2.0
const STALK_FIRE_EVERY := [4.2, 3.6, 3.0]
const ORB_SPEED := [46.0, 54.0, 62.0]
const ATTACK_EVERY := [4.6, 3.4, 2.7]
const DAMAGE := {
	"bomb": {"stalk": 3.0, "core": 5.0, "radius": 50.0},
	"mine": {"stalk": 3.0, "core": 5.0, "radius": 56.0},
	"blast": {"stalk": 2.0, "core": 3.0, "radius": 0.0},   # radius from the suit's own
}
# Old mining charges shake loose from the roof: one every few seconds, up to a cap.
const BOMB_EVERY := 5.0
const BOMB_CAP := 3
# The Suit Blaster recharges this fast in the chamber (seconds per charge).
const BLASTER_RECHARGE := 12.0

# --- the chase (#161) --------------------------------------------------------
const CHASE_TENTACLES := 3
# Tentacle speed as a share of the keeper's own top speed: when right behind
# the keeper, at a middle distance, and when far behind (rubber band).
const CHASE_SPEED_NEAR := 0.86
const CHASE_SPEED_MID := 1.0
const CHASE_SPEED_FAR := 1.6
const CHASE_NEAR_PX := 60.0
const CHASE_FAR_PX := 320.0
const CHASE_HEAD_START := 2.5        # seconds before the tentacles set off
const CHASE_RECOIL := 1.3            # seconds a tip hangs back after it lands a hit

# --- the surface finale (#162) -----------------------------------------------
const FINALE_TENTACLE_HP := 260.0
const FINALE_EYE_HP := 700.0
const FINALE_SLAM_DAMAGE := 22
const FINALE_SLAM_EVERY := 5.5
const FINALE_ROUNDS := [2, 3]         # tentacles in round 1, round 2 (plus the great eye)
