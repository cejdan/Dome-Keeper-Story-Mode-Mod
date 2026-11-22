extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# Ticket 314 (PR #331): Story Mode drops bump like vanilla iron. Their scenes
# are built on vanilla MineralDrop.tscn, whose BumpSound has no clips; they now
# take IronDrop.tscn's BumpSound setup. Checks every Story drop scene's
# BumpSound against vanilla iron's, then drops pieces onto the floor and
# checks the sound starts with a clip on impact.

const TIMEOUT := 120
const VANILLA_IRON := "res://content/drop/iron/IronDrop.tscn"
const Minerals = preload("res://mods-unpacked/flantor-StoryMode/data/minerals.gd")
const Bones = preload("res://mods-unpacked/flantor-StoryMode/data/bones.gd")
const FALLERS := ["iron", "gold", "diamond", "minerbones"]


func boot() -> Dictionary:
	return {"seed": 12345}


func _setup(s) -> Dictionary:
	return {"streams": s.streams.map(func(a): return a.resource_path), "volume_db": snappedf(s.volume_db, 0.001), "pitch_scale": snappedf(s.pitch_scale, 0.001), "bus": str(s.bus)}


func run(h) -> void:
	h.disable_waves()
	var ref = load(VANILLA_IRON).instantiate()
	var want: Dictionary = _setup(ref.get_node("BumpSound"))
	ref.free()
	h.note("vanilla iron's BumpSound", want)
	h.check("vanilla iron has four bump clips", want.streams.size() == 4, want)
	for t: String in ["iron"] + Minerals.MOD_MINERALS + [Bones.TYPE]:
		var d = Data.DROP_SCENES[t].instantiate()
		var got: Dictionary = _setup(d.get_node("BumpSound"))
		d.free()
		h.check("%s's BumpSound matches vanilla iron's" % t, got == want, got)

	# Drop pieces onto the floor of a room and watch for the bump.
	await h.dig_room(Vector2i(-4, 5), Vector2i(4, 8))
	await h.teleport_tile(Vector2i(-3, 8))
	await h.wait(1.0)
	var floor_y: float = Level.map.getTilePos(Vector2i(0, 8)).y
	for i in FALLERS.size():
		var t: String = FALLERS[i]
		var d = Level.drops.network_spawn({"type": t, "position": Vector2(Level.map.getTilePos(Vector2i(-1 + i, 8)).x, floor_y - 40.0), "impulse": Vector2.ZERO})
		var s = d.get_node("BumpSound")
		var played := false
		var clip := ""
		var t0: float = h.now()
		while h.now() - t0 < 3.0 and is_instance_valid(d):
			if s.playing or s.shouldPlay:
				played = true
				clip = s.stream.resource_path if s.stream != null else ""
				break
			await h.frames(1)
		h.check("a falling %s bumps with a clip (%s)" % [t, clip.get_file()], played and clip != "", {"played": played, "clip": clip})
		await h.wait(0.3)
	await h.shot("pieces_on_floor")
