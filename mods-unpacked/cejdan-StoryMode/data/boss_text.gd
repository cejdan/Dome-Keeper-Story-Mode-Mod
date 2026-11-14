extends RefCounted

# The boss sequence's text (#162). Claude's draft, for the user to rewrite;
# every line is also in docs/story/script.md under "Boss".

# After the final blow the surface monsters thank the keeper, one line each,
# shown like their pleas: runes until translators are installed, key words
# (in *asterisks*) first.
const THANKS: Array = ["*Digger*. You came *back* for us.", "The *hunger* is *still*. We *thank* you.", "*Sleep* now, deep one. Go in *peace*, digger."]

# The lost ending: the keeper died to Velle, or the dome fell in the finale.
const FALLEN_CARDS: Array = ["\"Hush now, little keeper,\" said Velle. \"You did so well.\"", "The suit went quiet in the dark. Nobody came for it.", "Above, the ground opened like an eye.", "On the surface the singing stopped, one voice at a time.", "Halcyon Extraction logged the keeper as lost with the site, and posted the job again."]
const FALLEN_TITLE := "The Planet Is Lost"
const FALLEN_SUBTITLE := "You woke it. Nobody was left to stop it."
