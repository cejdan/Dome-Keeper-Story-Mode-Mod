extends "res://content/gadgets/teleporter/Teleporter.gd"

# The teleporter's suction (teleporterteleportresourcesback) pulls in only the
# drops whose type is on vanilla's list: iron, water, sand and packs (#319). A
# Story Mode drop is pulled in when it is delivered as one of those
# (drops/delivery.gd): every mineral and miner bones, delivered as iron. A
# translator is delivered as a relic, and the suction leaves relics alone, so
# it leaves the translator too.
#
# Delivery is vanilla's: the drop shrinks into the teleporter (Drop.shrink),
# which counts it in team<n>.inventory.<its own type>, so a mineral is paid
# its value there as at the crusher (gamemode/Storymode.gd), and miner bones
# are paid theirs and open their log (drops/BonesDrop.gd).
# Runs when a body enters or leaves the suction area, not every frame.

const Delivery = preload("res://mods-unpacked/flantor-StoryMode/drops/delivery.gd")
static var _Delivery = Delivery  # calls go through this: lazy_preload makes const-preload calls slow


func canTeleportDrop(body):
	return super(body) or _Delivery.teleported(body.type)
