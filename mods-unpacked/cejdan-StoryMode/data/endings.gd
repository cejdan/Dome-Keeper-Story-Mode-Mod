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
const SAVED_CARDS: Array = ["The voice inside your head finally went quiet, and stayed quiet.", "The creatures stopped attacking the dome.", "You could finally breathe easy.", "You stopped mining and finally got some rest as you awaited the scheduled pickup.", "As your ship was departing, in the distance you could still hear them singing."]
const SAVED_TITLE := "The Planet Is Saved"
const SAVED_SUBTITLE := "Saved by the hands that nearly ended it."
