extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #246: the third player back, joining the run under way while the host
# changes Story Mode keys every frame; it must end with the host's values too.
# Pair: t246_mp_late_join_host (as -Rejoin).

const Director = preload("res://mods-unpacked/cejdan-StoryMode/boss/boss_director.gd")
const KEY := "team1.story.t246"
const TIMEOUT := 240


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var want = await shared(h, "final", 120.0)
	h.check("the host shared its final values", want is Dictionary, want)
	if not want is Dictionary:
		return
	await h.wait(3.0)
	var n: int = int(want["n"])
	h.check("the money is the host's", int(Data.ofOr("team1.inventory.money", -1)) == 5000 + n, Data.ofOr("team1.inventory.money", -1))
	h.check("the story key is the host's", str(Data.ofOr(KEY, "")) == "v%d" % n, Data.ofOr(KEY, ""))
	h.check("the boss state is the host's", Director.current() == "t246_%d" % n, Director.current())
	await h.shot("rejoin_end")
