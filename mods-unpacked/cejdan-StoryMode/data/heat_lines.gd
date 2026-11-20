extends RefCounted

# What the keeper says about the depth heat (#146), shown over its head by
# hud/heat_talk.gd. Lines and timings are starting values for the user to tune.

# Reaching a hotter heat level (#285): the level is how far below the suit's
# shielding the keeper is (data/lava.gd passive_level, with the lava ocean one
# deeper than B8): 0 is the first level that heats (B4 with no shielding, B5
# with Heat Shielding I, ... B8 with IV), 1 the next, and so on. Level 5, the
# lava ocean with no shielding, shouldn't be reachable; it is there in case.
# Each shows once on the way down, and again after the keeper has cooled off.
const HOT: Array = [
	"so hot",
	"feels even hotter",
	"the heat is unbearable",
	"it's scorching down here",
	"the air itself is burning",
	"not gonna make it...",
]

# Back where the heat bar drains: one of these, in a shuffled cycle so the
# same line doesn't come back until the rest have had their turn.
const COOL: Array = [
	"Ah, so much cooler",
	"that feels better",
	"thank the stars, cool air",
	"phew",
	"finally, some air",
	"much better",
	"I can breathe again",
	"the sweat's drying",
	"that's a relief",
	"oh, cool air",
	"okay. okay. better.",
	"ahh, that's nice",
	"back where it's bearable",
	"cooling off",
	"my visor's clearing up",
	"cooling down",
	"phew, cool air",
	"thank the stars, it's cool",
	"that was too hot",
	"whew, need a heat suit upgrade",
]

const HOT_COLOR := Color("ff6a2a")
const COOL_COLOR := Color("a6ecff")
# Seconds a line stays up (fade included), the least gap between two lines,
# and how long the keeper must stay in a new state before it counts (so a
# keeper hovering on a biome edge doesn't chatter).
const LIFE := 2.8
const GAP := 2.0
const SETTLE := 0.4
