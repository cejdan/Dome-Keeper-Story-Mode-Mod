extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 8 demo: start Story Mode, drill straight down 5 tiles, screenshot each
# tile, take one frame burst, log state.


func boot() -> Dictionary:
	return {"seed": 12345}


func run(h) -> void:
	h.disable_waves()
	h.snap("start")
	await h.hold("ui_right", 0.25)
	h.down("ui_down")
	var start_y: int = -99
	var last_y: int = -99
	var shots: int = 0
	var left: float = 60.0
	while shots < 6 and left > 0.0:
		var y: int = h.keeper_tile().y
		if y != last_y and y >= 0:
			if start_y == -99:
				start_y = y
			last_y = y
			h.snap("tile y=%d" % y)
			await h.shot("down_y%d" % y)
			shots += 1
		await h.wait(0.1)
		left -= 0.1
	await h.burst("drilling", 8, 2)
	h.up("ui_down")
	h.check("drilled 5 tiles down", last_y - start_y >= 5, {"from": start_y, "to": last_y})
