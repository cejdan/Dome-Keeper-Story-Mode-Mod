extends "res://content/gadgets/droneyard/TransportDrone.gd"

# A drone carrying a Story Mode mineral (or the miner bones) shows it in its
# claws and plays the carry animation, like vanilla's iron, water and sand
# (#270). Vanilla's setCarriedResource matches only its own types, so these
# got no texture and no carry animation. Packs get the same art for any Story
# piece inside (util/carry_art.gd).

const CarryArt = preload("res://mods-unpacked/flantor-StoryMode/util/carry_art.gd")
static var _CarryArt = CarryArt  # calls go through this: lazy_preload makes const-preload calls slow


func setCarriedResource(res: String):
	var art: Texture2D = _CarryArt.of(res)
	if art == null:
		super(res)
		if res == CONST.PACK:
			_CarryArt.fix_pack($CarriedResource, packedDropContent)
		return
	carriedResource = res
	$CarriedResource.texture = art
	$Sprite.play("carry_idle")
	$SpriteOverlay.visible = true
	$SpriteOverlay.play("carry_idle")
	$PickupSound.startSound()


# Miner bones keep their value and biome on the way home (#280,
# drops/drone_cargo.gd): vanilla spawns a fresh, $0 drop of the carried type
# at the dome.
const DroneCargo = preload("res://mods-unpacked/flantor-StoryMode/drops/drone_cargo.gd")
static var _DroneCargo = DroneCargo  # calls go through this: lazy_preload makes const-preload calls slow

var _cargo: Dictionary = {}


func pickup(drop: Carryable) -> void:
	_cargo = _DroneCargo.of(drop)
	super(drop)


func retrieve() -> void:
	var hook: Callable = _DroneCargo.hook(_cargo)
	_cargo = {}
	if hook.is_null():
		super()
		return
	Level.drops.synchronizer.drop_spawned.connect(hook)
	super()
	Level.drops.synchronizer.drop_spawned.disconnect(hook)


func kill():
	if _cargo.is_empty() or carriedResource != _DroneCargo.TYPE:
		super()
		return
	_DroneCargo.respawn(self, _cargo)


func serialize() -> Dictionary:
	var data: Dictionary = super()
	if not _cargo.is_empty():
		data["story.cargo"] = _cargo
	return data


func deserialize(data: Dictionary):
	_cargo = data.get("story.cargo", {})
	super(data)
