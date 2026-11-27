extends RefCounted

# One-shot sounds for the boss (#160, #163), all from the game's own files,
# and its beats of slow motion.
#   Sfx.play("roar", volume_db, pitch)
#   Sfx.hitstop(time_scale, real_seconds)

const SOUNDS := {
	"roar": ["res://content/sounds/monster/Beast/Beast_roar_01.wav", "res://content/sounds/monster/Beast/Beast_roar_02.wav", "res://content/sounds/monster/Beast/Beast_roar_03.wav"],
	"hurt": ["res://content/sounds/monster/Beast/Beast_hit_01.wav", "res://content/sounds/monster/Beast/Beast_hit_02.wav", "res://content/sounds/monster/Beast/Beast_hit_03.wav"],
	"pop": ["res://content/sounds/Bastards/guts_01.wav", "res://content/sounds/Bastards/guts_02.wav", "res://content/sounds/Bastards/guts_03.wav"],
	"spit": ["res://content/sounds/monster/worm/Worm_Spit.wav"],
	"whip": ["res://content/sounds/monster/tormentor/hit_harder_01.wav", "res://content/sounds/monster/tormentor/hit_harder_02.wav", "res://content/sounds/monster/tormentor/hit_harder_03.wav"],
	"grow": ["res://content/sounds/monster/worm/Worm_Emerge.wav"],
	"burrow": ["res://content/sounds/monster/worm/Worm_Burrow.wav"],
	"open": ["res://content/sounds/monster/tormentor/transformSound.wav"],
	"clang": ["res://content/sounds/ShieldReflect.wav"],
	"pull": ["res://content/sounds/monster/Mucker/MuckerApprocach.wav"],
	"charge": ["res://content/sounds/Retro Electric 01.wav"],
	"beam": ["res://content/sounds/OverCharge.wav"],
	"boom": ["res://content/sounds/rock_explode_03.wav"],
	"drop": ["res://content/sounds/rock-break-1.wav"],
	"die": ["res://content/sounds/monster/Beast/Beast_Death_01.wav"],
	"eerie": ["res://content/sounds/Locations/RelicRoom/eerie_01.wav"],
	"seal": ["res://content/sounds/relic-pulse.wav"],
	"heart": ["res://content/sounds/UI/autoheal.wav"],
	"keeper_down": ["res://content/sounds/carryline-break.wav"],
	# The lair seal (#366, endgame/lair_seal.gd).
	"seal_zap": ["res://content/sounds/Locations/DomeShield/Shield_reflect_01.wav", "res://content/sounds/Locations/DomeShield/Shield_reflect_02.wav"],
	"seal_strain": ["res://content/sounds/Locations/Probe/probecharge.wav"],
	"seal_break": ["res://content/sounds/Locations/Orchard/OrchardShield_die.wav"],
	"seal_shatter": ["res://content/sounds/assignments/glasscrack.wav"],
	"seal_settle": ["res://content/sounds/dome4/Tesla_Disarm.wav"],
	"seal_pass": ["res://content/sounds/Biomes/TeleportTouch.wav"],
}

static var played: Dictionary = {}   # name -> times played (for playtests)
static var _cache: Dictionary = {}


static func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	played[name] = int(played.get(name, 0)) + 1
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree) or not SOUNDS.has(name):
		return
	var files: Array = SOUNDS[name]
	var path: String = files[randi() % files.size()]
	if not _cache.has(path):
		_cache[path] = _one_shot(load(path)) if ResourceLoader.exists(path) else null
	var stream = _cache[path]
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = &"Monster"
	tree.root.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	# Belt and braces: a player never outlives its sound (#188). Bound to the
	# player itself, not a lambda that captures it: when `finished` has already
	# freed it, Godot drops the connection, where a lambda would be called with
	# a freed capture and log "Lambda capture at index 0 was freed" (#237).
	var secs: float = stream.get_length() / maxf(0.05, pitch) + 0.5 if stream.get_length() > 0.0 else 10.0
	tree.create_timer(secs).timeout.connect(p.queue_free)


# A beat of slow motion on a big hit (real seconds, whatever the time scale).
# Left alone when something else, a playtest say, has changed the game speed.
# Not online: the host's clock is the whole team's.
static func hitstop(scale: float, real_sec: float) -> void:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree) or not is_equal_approx(Engine.time_scale, 1.0) or not Network.is_offline_mode():
		return
	Engine.time_scale = scale
	await tree.create_timer(real_sec, true, false, true).timeout
	if is_equal_approx(Engine.time_scale, scale):
		Engine.time_scale = 1.0


# Some of the game's sounds loop (the charge, the eerie hum): played as a
# one-shot they never finish and drone on for the rest of the battle (#188).
# Those play from a copy with the loop turned off.
static func _one_shot(stream):
	if stream is AudioStreamWAV and stream.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		var s: AudioStreamWAV = stream.duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_DISABLED
		return s
	if stream is AudioStreamOggVorbis and stream.loop:
		var o: AudioStreamOggVorbis = stream.duplicate()
		o.loop = false
		return o
	return stream
