extends RefCounted

# The endings' text (#96 doom, #97 saved). Lines are the story script
# (docs/story/script.md, #25).

# Doom ending, after Retire Rich (shown as Fill Quota): the horror's thanks
# (one page each, tier 4), the planet's end in narration cards, the monsters' last words (key words
# in *asterisks*, shown at the current translation stage), the end screen.
const DOOM_THANKS: Array = [
	["Oh, sweet, sweet air. I'd forgotten the air."],
	["Thank you, now we are both free. Fly home little digger and never return."],
	["Oh, look at all the sheep up here... I'm salivating...."],
	["It's time to"],
	["{huge shake glitch} feast."],
]
const DOOM_CARDS: Array = ["The keeper fled the planet, heavy with minerals.", "Below you, the ground shook and opened like an eye.", "Safe in your ship, you were spared from hearing the screams."]
const DOOM_LAST_WORDS: Array = ["Why, digger, *why*?", "We *tried*. We tried so hard.", "*Sleep* now, little ones. Close your *eyes*."]
const DOOM_TITLE := "The Planet Is Lost"
const DOOM_SUBTITLE := "The company gave you a 5% bonus."

# Saved ending, after the horror is defeated: narration cards, the end screen.
# #368: the fourth card was "You stopped mining and finally got some rest as
# you awaited the scheduled pickup."; no pickup comes now, the ship by the dome
# takes the keeper home. The draft stands in until the user writes the line.
const SAVED_CARDS: Array = ["The voice inside your head finally went quiet, and stayed quiet.", "The creatures stopped attacking the dome.", "You could finally breathe easy.", "[DRAFT] You stopped mining, climbed aboard the ship by the dome and finally got some rest.", "As your ship was departing, in the distance you could still hear them singing."]
const SAVED_TITLE := "The Planet Is Saved"
const SAVED_SUBTITLE := "Saved by the hands that nearly ended it."

# The ship by the dome (#368, endgame/ship.gd). Drafts until the user writes
# them: the boarding hatch's prompt, and the keeper's line when the hatch is
# locked (after the horror's body dies, until the final dome battle is won).
const SHIP_BOARD := "[DRAFT] Board the ship"
const SHIP_LOCKED := "[DRAFT] It's still holding the ship down."

# Too late (#369, endgame/rising_lava.gd): the run lost to the rising lava.
# Drafts until the user writes them: the card when a keeper's suit gives out
# after the last chain (lava, the heat or gas: no recall to the dome now), the
# card when the lava reaches the surface with nobody aboard or fighting, and
# the end screen.
const TOO_LATE_DEATH_CARDS: Array = ["[DRAFT] Your suit gave out. Nothing carried you home this time."]
const TOO_LATE_SURFACE_CARDS: Array = ["[DRAFT] The lava reached the surface. The ship never left."]
const TOO_LATE_TITLE := "[DRAFT] Too Late"
const TOO_LATE_SUBTITLE := "[DRAFT] The lava rose faster than you."
