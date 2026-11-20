extends "res://mods-unpacked/flantor-StoryMode/dev/scenarios/t171_finale_play.gd"

# Ticket 188: what the surface finale sounds like. Plays the finale with the
# Laser III bot (t171_finale_play) and, every half second, lists every audio
# player in the tree that is playing: stream, bus, volume, pitch and node path.
# The end note sums up how long each sound played, longest first, so a sound
# that drones on through the battle stands out. No single boss sound (the
# Monster bus, where boss/sfx.gd plays) may last over 8 s: the great eye's
# looping charge sound used to play on forever.

var _census: Dictionary = {}   # key -> {"s": seconds, "db": loudest, "path": node path}
var _census_on: bool = true


func laser_level() -> int:
	return 3


func _walk(n: Node, out: Array) -> void:
	if (n is AudioStreamPlayer or n is AudioStreamPlayer2D or n is AudioStreamPlayer3D) and n.playing and n.stream != null:
		out.append(n)
	for c in n.get_children():
		_walk(c, out)


func _sample(dt: float) -> void:
	var players: Array = []
	_walk(Engine.get_main_loop().root, players)
	for p in players:
		var src: String = p.stream.resource_path.get_file() if p.stream.resource_path != "" else p.stream.get_class()
		var key: String = "%s | %s | x%.2f | #%d" % [src, str(p.bus), p.pitch_scale, p.get_instance_id()]
		var e: Dictionary = _census.get(key, {"s": 0.0, "db": -80.0, "path": str(p.get_path()), "bus": ""})
		e["s"] = float(e["s"]) + dt
		e["db"] = maxf(float(e["db"]), p.volume_db)
		e["bus"] = str(p.bus)
		_census[key] = e


func _tick(h) -> void:
	while _census_on:
		await h.wait(0.5)
		_sample(0.5)


func run(h) -> void:
	_tick(h)
	await super.run(h)
	_census_on = false
	var rows: Array = []
	for k: String in _census:
		rows.append([float(_census[k]["s"]), k, _census[k]])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	var longest: Array = []
	for r: Array in rows:
		if r[2]["bus"] == "Monster":
			longest = [r[0], r[1]]
			break
	h.check("no boss sound plays over 8 s", longest.is_empty() or float(longest[0]) <= 8.0, longest)
	var out: Array = []
	for r: Array in rows.slice(0, 40):
		out.append("%5.1fs  %s  (loudest %.1f dB)  %s" % [r[0], r[1], float(r[2]["db"]), str(r[2]["path"])])
	h.note("sounds by time played", out)
