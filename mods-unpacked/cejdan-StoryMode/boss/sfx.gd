extends RefCounted

# One-shot sounds for the boss (#160, #163), all from the game's own files.
#   Sfx.play("roar", volume_db, pitch)

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
	"keeper_down": ["res://content/sounds/carryline-break.wav"],
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
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
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
