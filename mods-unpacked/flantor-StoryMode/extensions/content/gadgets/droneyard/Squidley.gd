extends "res://content/gadgets/droneyard/Squidley.gd"

# The drone cave's resource grabber (Squidley), like the drone yard's drones
# (TransportDrone.gd, #270): a Story Mode mineral or the miner bones show in
# its claws. Vanilla plays "idle" for every single carried piece; so does this.

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
	$Sprite2D.play("idle")
	$PickupSound.startSound()
