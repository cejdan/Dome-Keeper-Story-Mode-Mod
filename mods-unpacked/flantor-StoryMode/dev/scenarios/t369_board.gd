extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t369_surface.gd"

# #369: boarding the ship mid-rise is the doom ending (a won run), not the
# too-late loss; the lava stops where it was once the ending starts. (The same
# run as t369_surface, which takes `--board` for this.)



func boot() -> Dictionary:
	return {"seed": 12345, "free": true, "board": true}
