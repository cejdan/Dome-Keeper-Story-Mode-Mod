extends "res://content/gadgets/blastMining/Mine.gd"

# A Blast Mining charge going off tells the boss (#160), so charges carried
# down from the dome hurt Velle like the chamber's own bombs do.


func explode(direction: Vector2):
	if not exploded:
		var radius: float = float(Data.ofOr(teamId + ".blastMining.radius", 2.7)) * 24.0
		load("res://mods-unpacked/cejdan-StoryMode/boss/boss_director.gd").explosion_at(global_position, "mine", radius)
	super(direction)
