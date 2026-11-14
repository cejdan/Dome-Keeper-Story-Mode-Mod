extends "res://stages/level/LevelStage.gd"

# Story Mode's gadget shop (gamemode/gadget_shop.gd) reuses vanilla's
# gadget-choice popup: a New Gadget entry opens it with the shop's fixed
# offers, a reroll costs water, and the entry's price is charged on pick.
# Everything else, and every vanilla mode, runs vanilla code.

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const GadgetShop = preload("res://mods-unpacked/cejdan-StoryMode/gamemode/gadget_shop.gd")

# playerIds whose open gadget choice came from the shop
var story_shop: Dictionary = {}


# Opens the gadget choice for the next New Gadget entry.
func openStoryGadgetChoice(teamId: String, playerId: String) -> void:
	if GadgetShop.next_entry(teamId) == "" or GadgetShop.candidates(teamId, playerId).is_empty():
		return
	story_shop[playerId] = true
	queueChoice(CONST.GADGET, teamId, playerId)


func startGadgetChoiceInput(teamId: String, playerId: String, offerType: String):
	if not (Story.is_story() and offerType == CONST.GADGET and story_shop.has(playerId)):
		super(teamId, playerId, offerType)
		return
	# Vanilla's setup, with the shop's processor (Cancel closes it).
	var i = load(Story.MOD_DIR + "gamemode/ShopChoiceInputProcessor.gd").new()
	var keeper: Keeper = Keepers.getKeeper(playerId)
	i.deviceId = keeper.deviceId
	i.popup = preload("res://stages/level/GadgetChoicePopup.tscn").instantiate()
	i.popup.droptype = offerType
	i.popup.teamId = teamId
	i.popup.playerId = playerId
	i.popup.inputProcessor = i
	i.teamId = teamId
	i.playerId = playerId
	i.stopWithPredecessor = false
	currentGadgetPopupByPlayerId[playerId] = i.popup
	showPopup(i.popup, keeper)
	showingChoicePopup = true
	i.connect("onStop", unpause)
	i.connect("onStop", Network.rpc_server.bind(continueOfferQueue.bind(playerId)))
	i.connect("gadgetSelected", onGadgetSelected)
	i.integrate(self)
	pause()


func _from_shop(playerId: String) -> bool:
	return Story.is_story() and currentOfferTypeByPlayerId.get(playerId, "") == CONST.GADGET and story_shop.has(playerId)


func generateOffers(teamId: String, playerId: String) -> void:
	if not _from_shop(playerId):
		super(teamId, playerId)
		return
	var ids: Array = GadgetShop.offers(teamId, playerId)
	var newOffers: Array[Dictionary] = []
	for id: String in ids:
		var o: Dictionary = GameWorld.getGadgetOffer(id)
		if o.size():
			newOffers.append(o)
	currentOffersByPlayerId[playerId] = newOffers
	var rerollPossible: bool = GadgetShop.candidates(teamId, playerId).size() > newOffers.size()
	var rerollCost: int = GadgetShop.REROLL_WATER
	offersGenerated.emit(playerId, newOffers, rerollPossible, rerollCost, 0)
	var offerIds: Array[String] = []
	for o: Dictionary in newOffers:
		offerIds.append(o["id"])
	var keeper: = Keepers.getKeeper(playerId)
	Network.rpc_or_local(keeper.peerId, remoteSetOffers.bind(playerId, CONST.GADGET, offerIds, rerollPossible, rerollCost, 0))


@rpc("reliable", "any_peer")
func remoteSetOffers(playerId: String, offerType: String, offerIds: Array[String], rerollPossible: bool, rerollCost: int, freeRerolls: int) -> void:
	if not _from_shop(playerId):
		super(playerId, offerType, offerIds, rerollPossible, rerollCost, freeRerolls)
		return
	# As vanilla, minus the "shred to cobalt" choice: the shop was opened on purpose.
	var currentOffers: Array[Dictionary] = []
	for offerId in offerIds:
		var offer: Dictionary = GameWorld.getGadgetOffer(offerId)
		if offer.size():
			currentOffers.append(offer)
	offersGenerated.emit(playerId, currentOffers, rerollPossible, rerollCost, freeRerolls)


@rpc("reliable", "any_peer")
func rerollOffers(teamId: String, playerId: String) -> void:
	if not _from_shop(playerId):
		super(teamId, playerId)
		return
	if Data.ofOr(teamId + ".inventory.water", 0) < GadgetShop.REROLL_WATER:
		return
	Data.changeByInt(teamId + ".inventory.water", -GadgetShop.REROLL_WATER)
	GameWorld.incrementRunStat("gadgets_rerolled", teamId)
	GadgetShop.reroll(teamId, playerId)
	generateOffers(teamId, playerId)


@rpc("reliable", "any_peer")
func addGadgetUpgrade(id: String, offerType: String, playerId: String, teamId: String):
	if not _from_shop(playerId) or offerType != CONST.GADGET:
		super(id, offerType, playerId, teamId)
		return
	var entry: String = GadgetShop.next_entry(teamId)
	var cost: int = GadgetShop.price(teamId)
	if entry == "" or not GadgetShop.offers(teamId, playerId).has(id) or Data.ofOr(teamId + ".inventory.money", 0) < cost:
		Network.rpc_or_local(Keepers.getKeeper(playerId).peerId, acceptGadgetSelection.bind(false, playerId))
		return
	# The entry is bought the vanilla way: that charges its price and unlocks the next one.
	GameWorld.buyUpgrade(entry, teamId, playerId)
	if not GameWorld.boughtUpgrades.has(entry):
		Network.rpc_or_local(Keepers.getKeeper(playerId).peerId, acceptGadgetSelection.bind(false, playerId))
		return
	GadgetShop.clear(teamId)
	ModLoaderLog.info("Gadget shop: %s bought with %s for $%d" % [id, entry, cost], Story.LOG)
	super(id, offerType, playerId, teamId)


@rpc("reliable", "any_peer")
func continueOfferQueue(playerId: String) -> void:
	story_shop.erase(playerId)
	super(playerId)
