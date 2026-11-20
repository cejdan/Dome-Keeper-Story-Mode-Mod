extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 203, the sounds: the gas's four sounds are made in code, so this
# writes each to a WAV file (to listen to outside the game) and measures its
# level against one of the game's own mine sounds.

const GasSfx = preload("res://mods-unpacked/cejdan-StoryMode/gas/gas_sfx.gd")
const REFERENCE := "res://content/sounds/rock-break-1.wav"


func boot() -> Dictionary:
	return {"seed": 12345}


# Peak and RMS of a 16-bit stream, 0..1 (all channels together).
func _levels(stream: AudioStreamWAV) -> Dictionary:
	var d: PackedByteArray = stream.data
	var n: int = d.size() / 2
	var peak := 0.0
	var sum := 0.0
	for i in n:
		var v: float = float(d.decode_s16(i * 2)) / 32768.0
		peak = maxf(peak, absf(v))
		sum += v * v
	return {"peak": snappedf(peak, 0.001), "rms": snappedf(sqrt(sum / maxi(n, 1)), 0.0001), "seconds": snappedf(stream.get_length(), 0.01)}


func run(h) -> void:
	h.disable_waves()
	var out: Dictionary = {}
	for sound in ["burst", "vent", "choke", "ignite"]:
		var s: AudioStreamWAV = GasSfx._make(sound)
		var lv: Dictionary = _levels(s)
		out[sound] = lv
		s.save_to_wav(h.out_dir.path_join("gas_%s.wav" % sound))
		h.check("%s: not silent, not clipped" % sound, lv["peak"] > 0.45 and lv["peak"] < 0.99 and lv["rms"] > 0.03, lv)
	var ref = load(REFERENCE)
	if ref is AudioStreamWAV and ref.format == AudioStreamWAV.FORMAT_16_BITS:
		out["reference (rock-break-1)"] = _levels(ref)
	h.note("levels", out)
