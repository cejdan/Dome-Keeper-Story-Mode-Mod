extends RefCounted

# The boss sequence's numbers (#160-#163): Velle's chamber fight, the chase
# back to the dome and the surface finale. Feel and balance are the user's to
# tune; everything is here in one place.

# --- keeper health (#160) ----------------------------------------------------
const HEARTS := 5
const HURT_INVULNERABLE := 1.2       # seconds safe after a hit
const HURT_KNOCKBACK := 46.0         # px the keeper is thrown
const OVERHEAT_HEAT_AFTER := 0.55    # heat (share of max) left after an overheat hit

# --- the chamber fight (#160, second pass #169) -------------------------------
const CORE_HP := 30.0
# Velle's health at which phase 2 and phase 3 begin. Once every eye stalk is
# popped the great eye opens and stays open until its health crosses the next
# of these (or reaches 0): there is no timer.
const PHASE_AT := [20.0, 10.0]
# An open eye fights back with its gaze. Seconds between its volleys when it
# has just opened, per phase; each second it stays open shortens that by
# OPEN_RAGE_PER_S (a share), down to OPEN_BEAM_FASTEST.
const OPEN_BEAM_EVERY := [3.2, 2.6, 2.2]
const OPEN_BEAM_FASTEST := 0.9
const OPEN_RAGE_PER_S := 0.03
const STALKS := [2, 3, 4]             # eye stalks per phase
const STALK_HP := 2.0
const STALK_FIRE_EVERY := [3.6, 3.2, 2.8]
# The share of a stalk's shots that are thin lasers instead of orbs.
const STALK_LASER_SHARE := [0.0, 0.5, 0.8]
const ORB_SPEED := [52.0, 60.0, 68.0]
const ATTACK_EVERY := [3.8, 3.0, 2.4]
const DAMAGE := {
	"bomb": {"stalk": 3.0, "core": 5.0, "radius": 56.0},
	"mine": {"stalk": 3.0, "core": 5.0, "radius": 56.0},
	"blast": {"stalk": 2.0, "core": 3.0, "radius": 0.0},   # radius from the suit's own
}
# Old mining charges shake loose from the roof: one every few seconds (faster
# while the eye is open), up to a cap; one more for every stalk popped, and
# BOMBS_ON_OPEN at once when the eye opens.
const BOMB_EVERY := 3.0
const BOMB_EVERY_OPEN := 2.2
const BOMB_CAP := 5
const BOMBS_ON_OPEN := 2
# Each new phase shakes a heart loose; it waits this long to be picked up.
const HEART_ON_PHASE := true
const HEART_SECONDS := 25.0
# The Suit Blaster recharges this fast in the chamber (seconds per charge).
const BLASTER_RECHARGE := 12.0

# --- difficulty (#174) ---------------------------------------------------------
# The numbers above are the brutal fight, which plays right. The other
# difficulties change these, per phase 1, 2, 3. Rows: easy, normal, brutal,
# You Asked For It. Normal and easy keep phases 1 and 2 and thin out phase 3
# (fewer lasers at once); You Asked For It makes phases 1 and 2 harder.
const TIER_BY_DIFFICULTY := {-2: 0, -1: 1, 0: 2, 2: 3}
const TIER_NAMES: Array = ["easy", "normal", "brutal", "you asked for it"]
const T_STALKS: Array = [[2, 3, 3], [2, 3, 3], STALKS, [3, 4, 4]]
const T_STALK_FIRE_EVERY: Array = [[4.0, 3.6, 3.4], [3.6, 3.2, 3.2], STALK_FIRE_EVERY, [3.1, 2.8, 2.6]]
const T_STALK_LASER_SHARE: Array = [[0.0, 0.4, 0.4], [0.0, 0.5, 0.5], STALK_LASER_SHARE, [0.35, 0.7, 0.85]]
const T_ATTACK_EVERY: Array = [[4.4, 3.6, 3.4], [3.8, 3.0, 2.9], ATTACK_EVERY, [3.0, 2.5, 2.2]]
# Gaze beams in one volley of the open eye.
const T_OPEN_BEAMS: Array = [[1, 2, 2], [1, 2, 2], [1, 2, 3], [2, 3, 3]]
# Wall lasers in phase 3's grid (5: three down, two across; 3: two down, one across).
const T_GRID_RAYS: Array = [3, 3, 5, 5]
# Phase 3: two walls of light closing (else one), and lunges in pairs.
const T_JAWS: Array = [false, false, true, true]
const T_DOUBLE_LUNGE: Array = [false, false, true, true]
# You Asked For It draws each phase's attacks from the next phase's list.
const T_POOL_SHIFT: Array = [0, 0, 0, 1]
# Hearts handed back when Velle dies, before the chase (easy: all of them).
const T_HEARTS_AFTER_VELLE: Array = [HEARTS, 3, 1, 0]


static func tier() -> int:
	return int(TIER_BY_DIFFICULTY.get(Level.difficulty("team1"), 2))


static func stalks(phase: int) -> int:
	return int(T_STALKS[tier()][phase])


static func stalk_fire_every(phase: int) -> float:
	return float(T_STALK_FIRE_EVERY[tier()][phase])


static func stalk_laser_share(phase: int) -> float:
	return float(T_STALK_LASER_SHARE[tier()][phase])


static func attack_every(phase: int) -> float:
	return float(T_ATTACK_EVERY[tier()][phase])


static func open_beams(phase: int) -> int:
	return int(T_OPEN_BEAMS[tier()][phase])


static func hearts_after_velle() -> int:
	return int(T_HEARTS_AFTER_VELLE[tier()])


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

# --- the surface finale (#162, second pass #171) ------------------------------
# Tuned for a dome with Laser IV (210 damage a second); Laser III (110) falls
# short, and a base laser (15) is buried early. Health is fixed, not scaled to the run: by now every run
# has had the same chance to gear up.
const FINALE_TENTACLE_HP := 420.0
const FINALE_EYE_HP := 1500.0          # Velle's great eye, in the last round
const FINALE_FLYER_HP := 120.0         # an eye that tore free of a tentacle
# A tentacle comes up with this many eyes; one tears free and becomes a flyer
# every FINALE_EYE_POP_EVERY seconds, and the ones still on it all tear free
# at once when it dies (#173; playtest 2026-11-15: every eye must be fought).
const FINALE_TENTACLE_EYES := 4
const FINALE_EYE_POP_EVERY := 2.0
# Where a flyer takes its place in the sky: this far from the dome (px), and
# this high (radians above the horizon), the angles taken in turn. High and
# spread, so the dome's weapon has a long way to swing between them, and the
# screen has ~580 px of sky above the dome.
const FINALE_FLYER_RADIUS := [260.0, 340.0]
const FINALE_FLYER_ANGLES := [0.8, 1.05, 1.3]
# The great eye hangs this many px above the dome's foot. Its stalk is drawn
# on this layer (absolute z), behind the dome.
const FINALE_EYE_HEIGHT := 132.0
const FINALE_STALK_Z := 1
const FINALE_SLAM_DAMAGE := 30         # to the dome; the great eye hits twice as hard
const FINALE_SLAM_EVERY := 5.5
const FINALE_FLYER_DAMAGE := 10        # one bolt
const FINALE_FLYER_EVERY := 3.4
# The great eye's gaze: it charges this long, then burns the dome, unless it
# loses GAZE_BREAK of its full health while charging (then it flinches).
const FINALE_GAZE_CHARGE := 3.0
const FINALE_GAZE_DAMAGE := 140
const FINALE_GAZE_BREAK := 0.14
# Fury: every second of the battle shortens all their waits by this share,
# down to FURY_FLOOR of the listed times. A slow dome is buried.
const FINALE_FURY_PER_S := 0.004
const FINALE_FURY_FLOOR := 0.45

# The finale's bell intro (#172, music/boss_finale_intro.ogg, written by
# art/music/variants.py toll): 7 bars at 174 bpm, played once while the ground
# first cracks; the battle loop and the first tentacles come in together at
# its end. Beats count from the start of the intro. On each toll the ground
# jolts and the cracks open a step further; the kicks before the drop thud;
# from the snare roll on the cracks tear right open.
# Before the bells, a breath of silence (#196): the bells start the moment
# the keeper takes the dome's weapon (Battle at the console), or after this
# many seconds walking about. The console's menu and the shop hold them off
# (they pause the game, as in any wave).
const FINALE_BREATH := 4.0
# The wave alarm (the HUD's blinking beep while nobody is at the console) is
# this much quieter during the finale, so the bells come through (#196).
const FINALE_ALARM_DB := -8.0
const FINALE_BEAT := 60.0 / 174.0
const FINALE_INTRO_BEATS := 28
const FINALE_TOLLS := [0.0, 4.0, 8.0, 12.0, 16.0, 20.0]
const FINALE_HEARTBEATS := [22.0, 24.0, 25.0, 26.0, 26.5, 27.0, 27.5]
const FINALE_ROLL_BEAT := 26.0
