extends RefCounted

# Base class for playtest scenarios (see dev/harness.gd and CLAUDE.md).
# A scenario overrides boot() to say what to start, and run(h) to drive it.


# Keys: mode (default "storymode"), seed, gadget, difficulty, world, palette,
# mapsize (vanilla modes), loadout (true = open the loadout screen instead).
func boot() -> Dictionary:
	return {}


func run(_h) -> void:
	pass
