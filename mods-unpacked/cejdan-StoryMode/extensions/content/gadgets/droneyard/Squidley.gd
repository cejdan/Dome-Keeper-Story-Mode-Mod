extends "res://content/gadgets/droneyard/Squidley.gd"

# The drone cave's resource grabber (Squidley), like the drone yard's drones
# (TransportDrone.gd, #270): a Story Mode mineral or the miner bones show in
# its claws. Vanilla plays "idle" for every single carried piece; so does this.

const CarryArt = preload("res://mods-unpacked/cejdan-StoryMode/util/carry_art.gd")


func setCarriedResource(res: String):
	var art: Texture2D = CarryArt.of(res)
	if art == null:
		super(res)
		if res == CONST.PACK:
			CarryArt.fix_pack($CarriedResource, packedDropContent)
		return
	carriedResource = res
	$CarriedResource.texture = art
	$Sprite2D.play("idle")
	$PickupSound.startSound()
