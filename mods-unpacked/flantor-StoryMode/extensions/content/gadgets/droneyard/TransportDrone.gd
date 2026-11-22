extends "res://content/gadgets/droneyard/TransportDrone.gd"

# A drone carrying a Story Mode mineral (or the miner bones) shows it in its
# claws and plays the carry animation, like vanilla's iron, water and sand
# (#270). Vanilla's setCarriedResource matches only its own types, so these
# got no texture and no carry animation. Packs get the same art for any Story
# piece inside (util/carry_art.gd).

const CarryArt = preload("res://mods-unpacked/flantor-StoryMode/util/carry_art.gd")
static var _CarryArt = CarryArt  # calls go through this: lazy_preload makes const-preload calls slow


func _ready():
	super()
	if Level.map != null and Level.map.has_signal("path_cell_closed"):
		Level.map.path_cell_closed.connect(_on_path_cell_closed)


# A cell on this drone's way turned back into rock (Map.path_cell_closed,
# #313): look for a new way instead of flying through it. Picking up: drop the
# target (the host's dispatcher hands it out again with a fresh path; clients
# follow its RPC). Carrying home: ask for a new path home, as after a pickup.
func _on_path_cell_closed(coord: Vector2) -> void:
	if state != State.PICKUP and state != State.RETRIEVE:
		return
	var crossed := false
	for i in range(maxi(currentPathIndex - 1, 0), currentPath.size()):
		if Vector2(Level.map.getTileCoord(currentPath[i])) == coord:
			crossed = true
			break
	if not crossed:
		return
	if state == State.PICKUP:
		if multiplayer.is_server():
			stopped_targeting_drop.emit()
	else:
		state = State.WAIT_FOR_PATH_HOME
		cooldown = 0.0


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
