extends "res://content/gadgets/droneyard/TransportDrone.gd"

# A drone carrying a Story Mode mineral (or the miner bones) shows it in its
# claws and plays the carry animation, like vanilla's iron, water and sand
# (#270). Vanilla's setCarriedResource matches only its own types, so these
# got no texture and no carry animation. Packs get the same art for any Story
# piece inside (util/carry_art.gd).

const CarryArt = preload("res://mods-unpacked/flantor-StoryMode/util/carry_art.gd")


func setCarriedResource(res: String):
	var art: Texture2D = CarryArt.of(res)
	if art == null:
		super(res)
		if res == CONST.PACK:
			CarryArt.fix_pack($CarriedResource, packedDropContent)
		return
	carriedResource = res
	$CarriedResource.texture = art
	$Sprite.play("carry_idle")
	$SpriteOverlay.visible = true
	$SpriteOverlay.play("carry_idle")
	$PickupSound.startSound()
