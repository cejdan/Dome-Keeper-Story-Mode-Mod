extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 176: the `--boss` dev commands, run the way the command line runs
# them: at once, on the first frame the run is ready, with the keeper still
# counted as inside the dome.
#
#   --what=chase   (default) `--boss=chase`: the chase must start and stay a
#                  chase. It used to jump straight to the finale, because the
#                  dome still counted the just-teleported keeper as home.
#   --what=fight   `--boss`: the fight starts with the shaft home already
#                  drilled, and the shaft is still open when Velle dies and
#                  the chase begins.
#
# (t170_dev_chase flew that shaft home with real input; dropped in #272, as it
# expected Laser III and the dev gear has had Laser IV since #195.)

const Director = preload("res://mods-unpacked/cejdan-StoryMode/boss/boss_director.gd")
const Dev = preload("res://mods-unpacked/cejdan-StoryMode/dev/boss_dev.gd")
const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const TIMEOUT := 300


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	var what: String = Story.user_arg("what", "chase")
	var boss = Director.instance()
	var k = h.keeper()
	var ch: Rect2i = Level.map.tileData.get_meta("story_boss_chamber")
	h.note("at the start", {"isInsideDome": k.isInsideDome})
	# No wait: the command runs on the first ready frame.
	boss._dev_boss("chase" if what == "chase" else "true")
	var states: Dictionary = {}
	for i in 50:
		await h.wait(0.1)
		states[Director.current()] = true
	h.snap_camera()
	h.note("states seen in the first 5 s", states.keys())
	h.check("the keeper is in Velle's chamber, out of the dome", ch.has_point(h.keeper_tile()) and not k.isInsideDome, h.keeper_tile())
	var path: Array = boss.dev_path
	await h.until(func(): return Dev.blocked(path).is_empty(), 10.0)
	if what == "chase":
		h.check("`--boss=chase` starts the chase and never leaves it for the finale", Director.current() == "chase" and not states.has("finale") and boss.finale == null, states.keys())
		h.check("the tentacles are there", boss.chase != null and is_instance_valid(boss.chase) and boss.chase.running)
		await h.shot("chase")
		h.check("a shaft is open from the chamber to the dome (%d cells)" % path.size(), not path.is_empty() and Dev.blocked(path).is_empty(), Dev.blocked(path).slice(0, 8))
		return
	h.check("`--boss` starts the fight", Director.current() == "fight" and not states.has("finale") and not states.has("chase"), states.keys())
	h.check("with the shaft home already drilled (%d cells)" % path.size(), not path.is_empty() and Dev.blocked(path).is_empty(), Dev.blocked(path).slice(0, 8))
	h.check("it reaches from the chamber roof to under the dome", path[0].y == ch.position.y - 1 and path[path.size() - 1].y <= 1 and absi(path[path.size() - 1].x) <= 2, [path[0], path[path.size() - 1]])
	await h.shot("fight")
	var velle = boss.velle
	await h.until(func(): return velle.state == "fight", 8.0)
	boss.health.invulnerable = 9999.0
	velle._damage_core(9999.0)
	var chased: bool = await h.until(func(): return Director.current() == "chase", 15.0)
	await h.wait(3.0)
	h.check("Velle dies and the chase starts", chased and Director.current() == "chase", Director.current())
	h.check("the shaft is still open for the run home", Dev.blocked(path).is_empty(), Dev.blocked(path).slice(0, 8))
	await h.shot("chase_after_fight")
