extends Node

# Music for the boss sequence (#163), made only from the game's own layered
# tracks, in the set of the run's keeper (the same sets vanilla uses for the
# final wave and for carrying the relic home):
#
#   fight    the final-wave ("desperation") pair. Phase 1 plays layer 1 alone,
#            a little slow and low; phase 2 brings layer 2 in; phase 3 runs
#            both at full volume and a touch fast.
#   chase    the relic-retrieval pair, sped up; layer 2 swells as the
#            tentacles close in.
#   finale   the final-wave pair again, both layers, full.
#
# Both layers of a pair start together and share one pitch, so they stay in
# step. The mining music is held off while any of this plays, and everything
# fades when the sequence ends (the endings bring their own music).

const SETS := {
	"keeper1": ["res://content/music/LASER Desperation Layer 1 [loop].ogg", "res://content/music/LASER Desperation Layer 2 [loop].ogg",
		"res://content/music/ENGINEER Relic Retrieval Layer 1 [loop].ogg", "res://content/music/ENGINEER Relic Retrieval Layer 2 [loop].ogg"],
	"keeper2": ["res://content/music/ASSESSOR Final Push Layer 1 [loop].ogg", "res://content/music/ASSESSOR Final Push Layer 2 [loop].ogg",
		"res://content/music/ASSESSOR Relic Retrieval Layer 1 [loop].ogg", "res://content/music/ASSESSOR Relic Retrieval Layer 2 [loop].ogg"],
	"keeper3": ["res://content/music/keeper3/keeper3_final_wave_layer1_loop.ogg", "res://content/music/keeper3/keeper3_final_wave_layer2_loop.ogg",
		"res://content/music/keeper3/keeper3_relic_layer1_loop.ogg", "res://content/music/keeper3/keeper3_relic_layer2_loop.ogg"],
	"keeper4": ["res://content/music/keeper4/keeper4_final_wave_layer1_loop.ogg", "res://content/music/keeper4/keeper4_final_wave_layer2_loop.ogg",
		"res://content/music/keeper4/keeper4_relic_layer1_loop.ogg", "res://content/music/keeper4/keeper4_relic_layer2_loop.ogg"],
}
const SILENT := -60.0
const FADE_DB_PER_S := 30.0

var players: Array = []      # battle 1, battle 2, run 1, run 2
var goal: Array = [SILENT, SILENT, SILENT, SILENT]
var mode: String = ""        # "", fight, chase, finale
var set_id: String = ""
var _hold_t: float = 0.0


func _ready() -> void:
	name = "BossMusic"
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = &"Music"
		p.volume_db = SILENT
		add_child(p)
		players.append(p)


func _load_set() -> void:
	set_id = str(Audio.get_music_keeperId())
	if not SETS.has(set_id):
		set_id = "keeper1"
	for i in 4:
		var path: String = SETS[set_id][i]
		players[i].stream = load(path) if ResourceLoader.exists(path) else null


func _start_pair(a: int, pitch: float) -> void:
	for i in [a, a + 1]:
		var p: AudioStreamPlayer = players[i]
		if p.stream == null:
			continue
		p.pitch_scale = pitch
		p.volume_db = SILENT
		p.play()


func _pitch_pair(a: int, pitch: float) -> void:
	players[a].pitch_scale = pitch
	players[a + 1].pitch_scale = pitch


# The chamber fight; `phase` 0..2.
func fight(phase: int) -> void:
	if mode != "fight":
		if set_id == "":
			_load_set()
		mode = "fight"
		_start_pair(0, 0.94)
	match phase:
		0:
			goal = [-3.0, SILENT, SILENT, SILENT]
			_pitch_pair(0, 0.94)
		1:
			goal = [-2.0, -4.0, SILENT, SILENT]
			_pitch_pair(0, 1.0)
		_:
			goal = [0.0, 0.0, SILENT, SILENT]
			_pitch_pair(0, 1.05)


# The chase; `closeness` 0 (far behind) .. 1 (on the keeper).
func chase(closeness: float) -> void:
	if mode != "chase":
		if set_id == "":
			_load_set()
		mode = "chase"
		_start_pair(2, 1.08)
	goal = [SILENT, SILENT, -1.0, lerpf(-18.0, 0.0, clampf(closeness, 0.0, 1.0))]


func finale() -> void:
	if mode != "finale":
		if set_id == "":
			_load_set()
		mode = "finale"
		_start_pair(0, 1.0)
	goal = [0.0, 0.0, SILENT, SILENT]


func stop() -> void:
	mode = ""
	goal = [SILENT, SILENT, SILENT, SILENT]


# What is audible now, for playtests: stream file names and volumes.
func playing() -> Array:
	var out: Array = []
	for i in 4:
		var p: AudioStreamPlayer = players[i]
		if p.playing and p.volume_db > -40.0 and p.stream != null:
			out.append({"file": p.stream.resource_path.get_file(), "db": snappedf(p.volume_db, 0.1), "pitch": p.pitch_scale})
	return out


func _process(delta: float) -> void:
	for i in 4:
		var p: AudioStreamPlayer = players[i]
		if not p.playing:
			continue
		p.volume_db = move_toward(p.volume_db, goal[i], FADE_DB_PER_S * delta)
		# A pair that has faded right out stops.
		var pair: int = i - (i % 2)
		if goal[pair] <= SILENT and goal[pair + 1] <= SILENT and p.volume_db <= SILENT + 0.5:
			p.stop()
	if mode == "":
		return
	# The mining music steps aside.
	_hold_t -= delta
	if _hold_t <= 0.0:
		_hold_t = 0.5
		if Audio.isMusicPlaying():
			Audio.stopMusic(0.0, 1.5)
