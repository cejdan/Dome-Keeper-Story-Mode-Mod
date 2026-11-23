extends "res://content/keeper/keeper4/Goblins.gd"

# The Beastmaster's cats (#345): in Story Mode each player's task manager is
# gamemode/cat_tasks.gd, which lets the cats extract Story Mode's minerals as
# well as iron, sand and water. Vanilla modes keep vanilla's.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const CatTasks = preload("res://mods-unpacked/flantor-StoryMode/gamemode/cat_tasks.gd")


func get_task_manager(playerId: String) -> GoblinTaskManager:
	if not task_managers.has(playerId) and _Story.is_story():
		var tm = CatTasks.new(
			_navigator, self,
			_shared_resource_claims, _shared_mining_claims,
			_shared_surface_claims, _shared_hop_claims)
		tm.set_team_id(teamId)
		task_managers[playerId] = tm
	return super(playerId)
