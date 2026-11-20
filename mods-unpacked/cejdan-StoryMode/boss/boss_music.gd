extends Node

# Music for the boss sequence: the mod's own score (#172), written by
# art/music/score.py into music/boss_<cue>_<layer>.ogg. Each cue is a loop in
# layers that start together and stay in step; the director turns layers up
# and down with the fight:
#
#   fight    1 the pulse alone in phase 1; 2 war drums and brass join in
#            phase 2; 3 Velle's theme, choir and crashes on top in phase 3.
#   chase    1 the run; 2 what is behind you, louder the closer the
#            tentacles are.
#   breath   no cue: silence before the finale's bells (hush()).
#   finale   "Toll": music/boss_finale_intro.ogg once (bells while the ground
#            cracks), then both loop layers at full, starting exactly at the
#            intro's end so the drop lands. boss/finale.gd times the cracking
#            to intro_time(). The intro pauses with the game (the console's
#            menu, the shop), so its clock and the cracking stay together.
#
# The mining music is held off while any of this plays, and everything fades
# when the sequence ends (the endings bring their own music). The OGGs are
# read from their bytes, like the mod's PNGs, so they need no import step.

const Boss = preload("res://mods-unpacked/cejdan-StoryMode/data/boss.gd")
const DIR := "res://mods-unpacked/cejdan-StoryMode/music/"
const CUES := {"fight": 3, "chase": 2, "finale": 2}
const SILENT := -60.0
const FADE_DB_PER_S := 30.0
# Layer volumes (dB) per state.
const FIGHT := [[2.0, SILENT, SILENT], [0.0, 0.0, SILENT], [0.0, 0.0, 0.0]]
const CHASE_FAR := -16.0
const FINALE := [0.0, 0.0]
# All boss music sits this far above the layer volumes. The files are mastered
# to the game's own music loudness, but the boss fights are busier with sound
# than a wave, so the music is lifted to carry over them (playtest 2026-11-15).
# The Music bus is ~10 dB down and the master bus has a limiter: no clipping.
const GAIN_DB := 3.0

static var _streams: Dictionary = {}   # path -> AudioStreamOggVorbis

var cues: Dictionary = {}    # cue -> [AudioStreamPlayer, ...]
var goals: Dictionary = {}   # cue -> [dB, ...]
var mode: String = ""        # "", fight, chase, breath, finale
var intro: AudioStreamPlayer = null   # the finale's bell intro
var _intro_pending: bool = false      # the intro plays; the loop has not started yet
var _paused_at: float = 0.0           # where the intro was paused with the game
var _hold_t: float = 0.0


func _ready() -> void:
	name = "BossMusic"


static func intro_length() -> float:
	return Boss.FINALE_BEAT * Boss.FINALE_INTRO_BEATS


static func stream(cue: String, layer: int, loop: bool = true) -> AudioStream:
	var path: String = DIR + ("boss_%s_%d.ogg" % [cue, layer] if layer > 0 else "boss_%s_intro.ogg" % cue)
	if not _streams.has(path):
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		var s: AudioStreamOggVorbis = AudioStreamOggVorbis.load_from_buffer(bytes) if not bytes.is_empty() else null
		if s == null:
			push_error("StoryMode: missing or bad music file " + path)
		else:
			s.loop = loop
			s.resource_name = path.get_file()
		_streams[path] = s
	return _streams[path]


# Starts every layer of `cue` together, silent; the goals bring them in.
func _start(cue: String) -> void:
	if mode == cue:
		return
	if CUES.has(mode):
		goals[mode] = _silence(mode)
	mode = cue
	_ensure(cue)
	_play_cue(cue, 0.0)
	goals[cue] = _silence(cue)


func _ensure(cue: String) -> void:
	if not cues.has(cue):
		var list: Array = []
		for i in CUES[cue]:
			var p := AudioStreamPlayer.new()
			p.bus = &"Music"
			p.volume_db = SILENT
			p.stream = stream(cue, i + 1)
			add_child(p)
			list.append(p)
		cues[cue] = list


# Plays every layer of `cue` from `from` seconds, silent, or straight at its
# goal volume when `loud` (the finale's drop must land, not fade in).
func _play_cue(cue: String, from: float, loud: bool = false) -> void:
	var g: Array = goals.get(cue, _silence(cue))
	for i in cues[cue].size():
		var p: AudioStreamPlayer = cues[cue][i]
		if p.stream != null:
			p.volume_db = _out_db(float(g[i])) if loud else SILENT
			p.play(maxf(0.0, from))


# A layer volume as played: lifted by GAIN_DB unless it is silent.
static func _out_db(layer_db: float) -> float:
	return layer_db if layer_db <= SILENT else layer_db + GAIN_DB


func _silence(cue: String) -> Array:
	var out: Array = []
	for i in CUES[cue]:
		out.append(SILENT)
	return out


# The chamber fight; `phase` 0..2.
func fight(phase: int) -> void:
	_start("fight")
	goals["fight"] = FIGHT[clampi(phase, 0, 2)].duplicate()


# The chase; `closeness` 0 (far behind) .. 1 (on the keeper).
func chase(closeness: float) -> void:
	_start("chase")
	goals["chase"] = [0.0, lerpf(CHASE_FAR, 0.0, clampf(closeness, 0.0, 1.0))]


# Silence: whatever plays fades out, and the mining music stays away.
func hush() -> void:
	if mode == "breath":
		return
	if CUES.has(mode):
		goals[mode] = _silence(mode)
	mode = "breath"


func finale() -> void:
	if mode == "finale":
		return
	if CUES.has(mode):
		goals[mode] = _silence(mode)
	mode = "finale"
	_ensure("finale")
	goals["finale"] = FINALE.duplicate()
	var s = stream("finale", 0, false)
	if s == null:
		_play_cue("finale", 0.0)
		return
	if intro == null:
		intro = AudioStreamPlayer.new()
		intro.bus = &"Music"
		add_child(intro)
	intro.stream = s
	intro.volume_db = GAIN_DB
	intro.play()
	_intro_pending = true


# Seconds into the finale's bell intro, from the audio clock, or -1 when no
# intro is playing (no file, or the loop has taken over).
func intro_time() -> float:
	if not _intro_pending or intro == null:
		return -1.0
	if intro.stream_paused:
		return _paused_at
	if not intro.playing:
		return -1.0
	return intro.get_playback_position() + AudioServer.get_time_since_last_mix()


func stop() -> void:
	if CUES.has(mode):
		goals[mode] = _silence(mode)
	mode = ""
	_intro_pending = false


# What is audible now, for playtests: file names, volumes and play positions.
func playing() -> Array:
	var out: Array = []
	if intro != null and intro.playing and intro.volume_db > -40.0:
		out.append({"file": intro.stream.resource_name, "db": snappedf(intro.volume_db, 0.1), "pitch": 1.0, "pos": snappedf(intro.get_playback_position(), 0.01)})
	for cue: String in cues:
		for p: AudioStreamPlayer in cues[cue]:
			if p.playing and p.volume_db > -40.0 and p.stream != null:
				out.append({"file": p.stream.resource_name, "db": snappedf(p.volume_db, 0.1), "pitch": p.pitch_scale, "pos": snappedf(p.get_playback_position(), 0.01)})
	return out


func _process(delta: float) -> void:
	# The finale's drop: the loop starts where the intro's bars end, from the
	# overshoot, so it lands on the beat; the intro's bells ring on over it.
	if _intro_pending and intro != null and intro.stream_paused != GameWorld.paused:
		if GameWorld.paused:
			_paused_at = intro.get_playback_position()
		intro.stream_paused = GameWorld.paused
	if _intro_pending and not (intro != null and intro.stream_paused):
		var at: float = intro_time()
		if at < 0.0 or at >= intro_length():
			_intro_pending = false
			_play_cue("finale", at - intro_length() if at >= 0.0 else 0.0, true)
	if intro != null and intro.playing and mode != "finale":
		intro.volume_db = move_toward(intro.volume_db, SILENT, FADE_DB_PER_S * delta)
		if intro.volume_db <= SILENT + 0.5:
			intro.stop()
	for cue: String in cues:
		var g: Array = goals.get(cue, _silence(cue))
		var all_out: bool = true
		for i in cues[cue].size():
			var p: AudioStreamPlayer = cues[cue][i]
			if not p.playing:
				continue
			p.volume_db = move_toward(p.volume_db, _out_db(g[i]), FADE_DB_PER_S * delta)
			all_out = all_out and g[i] <= SILENT and p.volume_db <= SILENT + 0.5
		# A cue that has faded right out stops.
		if all_out:
			for p: AudioStreamPlayer in cues[cue]:
				p.stop()
	if mode == "":
		return
	# The mining music steps aside.
	_hold_t -= delta
	if _hold_t <= 0.0:
		_hold_t = 0.5
		if Audio.isMusicPlaying():
			Audio.stopMusic(0.0, 1.5)
