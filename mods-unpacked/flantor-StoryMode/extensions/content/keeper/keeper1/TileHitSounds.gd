extends "res://content/keeper/keeper1/TileHitSounds.gd"

# A drill on metal (#295) clanks on steel instead of digging: vanilla's dig
# sound and the pitch that climbs as a tile wears down both said the plate was
# giving way. The keeper's drill never cuts metal (data/metal.gd), so any metal
# hit here is refused. Shared by the Engineer's drill and the Assessor's ball.

const Metal = preload("res://mods-unpacked/flantor-StoryMode/data/metal.gd")
static var _Metal = Metal  # calls go through this: lazy_preload makes const-preload calls slow

# Unused anywhere in vanilla, so they mean only this.
const METAL_STREAMS: Array[String] = [
	"res://content/sounds/Resources/Cobalt/Metal_detail_08.wav",
	"res://content/sounds/Resources/Cobalt/Metal_detail_09.wav",
	"res://content/sounds/Resources/Cobalt/Metal_detail_10.wav",
	"res://content/sounds/Resources/Cobalt/Metal_detail_11.wav",
]
const SOUND_SCENE := "res://systems/audio/Sound.tscn"

static var metal_hits := 0   # for playtests

var _metal_sound: Node


func hit(tile, buffed: bool, playHitPitch: bool):
	if not _Metal.is_metal(tile.type):
		super(tile, buffed, playHitPitch)
		return
	metal_hits += 1
	_metal_player().startSound()


func _metal_player() -> Node:
	if _metal_sound == null:
		_metal_sound = load(SOUND_SCENE).instantiate()
		_metal_sound.name = "TileHitMetal"
		var streams: Array[AudioStream] = []
		for path in METAL_STREAMS:
			streams.append(load(path))
		_metal_sound.streams = streams
		_metal_sound.volume_db = -3.0
		_metal_sound.max_polyphony = 3
		_metal_sound.bus = &"Sounds"
		_metal_sound.randomVolume = 1.0
		_metal_sound.randomPitch = 0.08
		_metal_sound.maxAudibleDistance = 400.0
		_metal_sound.minAudibleDistance = 30.0
		add_child(_metal_sound)
	return _metal_sound
