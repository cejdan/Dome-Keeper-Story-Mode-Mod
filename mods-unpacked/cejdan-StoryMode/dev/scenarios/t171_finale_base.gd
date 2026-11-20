extends "res://mods-unpacked/cejdan-StoryMode/dev/scenarios/t171_finale_play.gd"

# Ticket 171: a base laser cannot win the final battle. The laser bot (see
# t171_finale_play) gets every other upgrade of the boss dev gear (a stronger
# dome, faster aim) and only the laser it started the run with: the dome must
# fall, and before the last round.


func laser_level() -> int:
	return 0


func expect() -> String:
	return "lose"
