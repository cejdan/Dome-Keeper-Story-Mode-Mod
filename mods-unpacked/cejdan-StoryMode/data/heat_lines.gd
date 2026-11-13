extends RefCounted

# What the keeper says about the depth heat (#146), shown over its head by
# hud/heat_talk.gd. Lines and timings are starting values for the user to tune.

# Entering a hotter section, by biome index (3 = B4, where passive heat
# starts; 8 = the lava ocean). Each shows once on the way down, and again
# after the keeper has cooled off.
const HOT: Dictionary = {
	3: "so hot",
	4: "feels even hotter",
	5: "so much sweat",
	6: "the heat is unbearable",
	7: "it's scorching in here",
	8: "the air itself is burning",
}

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
	"oh, fresh air",
	"okay. okay. better.",
	"cool rock, sweet cool rock",
	"never going that deep again. Maybe.",
	"the heat lets go",
	"ahh, that's nice",
	"back where it's bearable",
	"cooling off",
	"my visor's clearing up",
	"ok, I can think again",
	"sweet, sweet shade",
]

const HOT_COLOR := Color("ff6a2a")
const COOL_COLOR := Color("a6ecff")
# Seconds a line stays up (fade included), the least gap between two lines,
# and how long the keeper must stay in a new state before it counts (so a
# keeper hovering on a biome edge doesn't chatter).
const LIFE := 2.8
const GAP := 2.0
const SETTLE := 0.4
