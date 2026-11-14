extends RefCounted

# The endings' text (#96 doom, #97 saved). Lines are the story script
# (docs/story/script.md, #25).

# Doom ending, after Retire Rich: the horror's thanks (one beat per page, tier
# 4), the planet's end in narration cards, the monsters' last words (key words
# in *asterisks*, shown at the current translation stage), the end screen.
const DOOM_THANKS: Array = [
	["Thank you, little keeper.", "Oh, the air up there. I'd forgotten the air."],
	["Go on, then. Fly home. Spend it all.", "You were always going to."],
	["Don't look back. This part isn't for you.", "I'll sing the little ones to sleep, all of them. It's what they wanted."],
]
const DOOM_CARDS: Array = ["The pod left the surface at dawn, a million dollars heavier.", "Below it, the ground opened like an eye.", "On the surface the singing stopped, one voice at a time.", "By the time the pod reached orbit, the planet had gone dark.", "Halcyon Extraction logged the site as fully yielded."]
const DOOM_LAST_WORDS: Array = ["Was it *enough*, digger?", "We *tried*. We tried so hard.", "*Sleep* now, little ones. Close your *eyes*."]
const DOOM_TITLE := "The Planet Is Lost"
const DOOM_SUBTITLE := "You retired rich. The planet paid for it."

# Saved ending, after the horror is defeated: narration cards, the end screen.
const SAVED_CARDS: Array = ["Velle went quiet, and stayed quiet.", "The next wave reached the dome and did not attack. They sat in the dust and sang, low and slow.", "The translator called it a lullaby. It was not for the keeper.", "The tunnels stayed open to the sky. The keeper had dug every one of them.", "Halcyon Extraction marked the site as a loss."]
const SAVED_TITLE := "The Planet Is Saved"
const SAVED_SUBTITLE := "Saved by the hands that nearly ended it."
