extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #252: the Artillery Dome (dome3.gd, `class_name Dome3 extends Dome`) in a
# Story Mode run. Before #252 it did not compile once Dome.gd was extended
# (the run had no dome script); held before the install it sits on vanilla's
# Dome, so it needs its own extension to take Story Mode minerals at the
# shredder like the other domes (extensions/content/dome/Dome.gd).

const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
static var _Minerals = Minerals  # calls go through this: lazy_preload makes const-preload calls slow


func boot() -> Dictionary:
	return {"seed": 12345, "dome": "dome3"}


func run(h) -> void:
	h.disable_waves()
	var dome = Level.getDome("team1")
	var script: Script = dome.get_script() if dome else null
	h.check("the run's dome is the Artillery Dome", script != null and script.can_instantiate() and dome is Dome3, str(script.resource_path) if script else "no script")
	var target = dome.getDropTarget("gold")
	h.check("gold goes to the shredder", target != null and target == dome.get_node_or_null("Shredder"), str(target))
	var m0: int = int(h.inv("money"))
	await h.deliver("gold", 2)
	await h.until(func(): return int(h.inv("money")) >= m0 + 2 * _Minerals.value_of("gold"), 10.0)
	var m1: int = int(h.inv("money"))
	h.check("2 gold delivered pay 2 x gold's value", m1 == m0 + 2 * _Minerals.value_of("gold"), {"before": m0, "after": m1})
	await h.wait(0.5)
	await h.shot("artillery_dome")
