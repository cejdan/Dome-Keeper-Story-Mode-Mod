extends "res://mods-unpacked/cejdan-StoryMode/dev/scenarios/t171_finale_play.gd"

# Ticket 171: Laser III is not enough for the final battle (playtest
# 2026-11-15: every eye tears free and must be fought, and the user wants
# Laser III to fall short). The laser bot (see t171_finale_play) must lose.


func laser_level() -> int:
	return 3


func expect() -> String:
	return "fall"
