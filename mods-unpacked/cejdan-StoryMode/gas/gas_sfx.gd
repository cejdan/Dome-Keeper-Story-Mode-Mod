extends RefCounted

# The gas's sounds (#203), made in code: hisses of filtered noise, so there is
# no audio file to ship and nothing borrowed that might loop.
#   GasSfx.play("burst")   a pressurised pocket letting go
#   GasSfx.play("vent")    gas leaving at the surface (softer, lower)
#   GasSfx.play("choke")   the suit's warning as the toxin bar nears full
#   GasSfx.play("ignite")  gas catching fire: a low whoomp

const RATE := 22050

static var played: Dictionary = {}   # name -> times played (for playtests)
static var _cache: Dictionary = {}
static var _last: Dictionary = {}    # name -> ticks (ms) it last played


static func play(name: String, volume_db: float = 0.0, min_gap: float = 0.0) -> void:
	var now: int = Time.get_ticks_msec()
	if min_gap > 0.0 and now - int(_last.get(name, -100000)) < int(min_gap * 1000.0):
		return
	_last[name] = now
	played[name] = int(played.get(name, 0)) + 1
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return
	if not _cache.has(name):
		_cache[name] = _make(name)
	var p := AudioStreamPlayer.new()
	p.stream = _cache[name]
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.94, 1.06)
	p.bus = &"Mine"
	tree.root.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	# Bound to the player, not a lambda capturing it (see boss/sfx.gd, #237).
	tree.create_timer(p.stream.get_length() + 0.5).timeout.connect(p.queue_free)


# Noise through a band-pass (a one-pole high-pass, then a one-pole low-pass),
# shaped by an envelope. `hp` and `lp` are the filters' coefficients (0..1).
# The result is scaled so its loudest sample is `peak` of full scale: the
# filters take very different amounts of level out (a low rumble came out at
# 6% before this).
static func _make(name: String) -> AudioStreamWAV:
	var secs := 1.7
	var hp := 0.82
	var lp := 0.55
	var attack := 0.015
	var decay := 2.6
	var peak := 0.8
	var flutter := 0.25
	if name == "vent":
		secs = 2.2
		hp = 0.6
		lp = 0.22
		attack = 0.25
		decay = 1.6
		peak = 0.5
		flutter = 0.4
	elif name == "choke":
		secs = 0.5
		hp = 0.5
		lp = 0.12
		attack = 0.02
		decay = 7.0
		peak = 0.6
		flutter = 0.0
	elif name == "ignite":
		secs = 1.1
		hp = 0.25
		lp = 0.05
		attack = 0.012
		decay = 4.5
		peak = 0.9
		flutter = 0.5
	var n := int(secs * RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var loudest := 0.0001
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var low := 0.0
	var prev_x := 0.0
	var high := 0.0
	for i in n:
		var t: float = float(i) / RATE
		var x: float = rng.randf_range(-1.0, 1.0)
		high = hp * (high + x - prev_x)
		prev_x = x
		low += lp * (high - low)
		var env: float = minf(1.0, t / attack) * exp(-t * decay) * minf(1.0, (secs - t) * 20.0)
		env *= 1.0 - flutter * (0.5 + 0.5 * sin(t * 53.0 + 2.0 * sin(t * 17.0)))
		var v: float = low * env
		samples[i] = v
		loudest = maxf(loudest, absf(v))
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var scale: float = peak / loudest * 32767.0
	for i in n:
		bytes.encode_s16(i * 2, int(samples[i] * scale))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w
