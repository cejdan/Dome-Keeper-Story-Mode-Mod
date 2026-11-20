extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 200, the dev key: with `-- --gas`, F10 puts the keeper in a tunnel
# beside the next gas pocket. boot() asks for --gas itself (#272).


func boot() -> Dictionary:
	return {"seed": 12345, "gas": true}


func run(h) -> void:
	h.disable_waves()
	await h.until(func(): return Level.map.get_node_or_null("StoryGasField") != null, 10.0)
	var field = Level.map.get_node("StoryGasField")
	var finder = h.get_tree().root.find_child("DevGasFinder", true, false)
	h.check("the gas finder is there (launched with --gas)", finder != null)
	if finder == null:
		return
	await h.wait(2.0)
	var seen: Array = []
	for i in 2:
		var ev := InputEventKey.new()
		ev.keycode = KEY_F10
		ev.pressed = true
		Input.parse_input_event(ev)
		await h.wait(1.0)
		var kt: Vector2i = h.keeper_tile()
		var near := 999.0
		for c in field.rock:
			near = minf(near, Vector2(c - kt).length())
		h.check("F10 #%d: the keeper stands in the open, two tiles from gas rock" % (i + 1), Level.map.is_tile_empty(kt) and near <= 2.01 and not seen.has(kt), [kt, near, finder._label.text])
		seen.append(kt)
		await h.shot("pocket_%d" % (i + 1))
	h.check("the tunnels breached nothing", field.breaches == 0, field.breaches)
