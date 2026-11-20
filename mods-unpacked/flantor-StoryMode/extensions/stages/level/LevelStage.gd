extends "res://stages/level/LevelStage.gd"

# Story Mode's gadget shop (gamemode/gadget_shop.gd) reuses vanilla's
# gadget-choice popup: a New Gadget entry opens it with the shop's fixed
# offers, a reroll costs water, and the entry's price is charged on pick.
# Everything else, and every vanilla mode, runs vanilla code.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const GadgetShop = preload("res://mods-unpacked/flantor-StoryMode/gamemode/gadget_shop.gd")
static var _GadgetShop = GadgetShop  # calls go through this: lazy_preload makes const-preload calls slow

# playerIds whose open gadget choice came from the shop
var story_shop: Dictionary = {}


# Opens the gadget choice for the next New Gadget entry. The host runs the
# shop (offers live in Data, which only the host may change), so a client asks
# the host to open it (#236); the client only shows the popup and sends its
# picks, rerolls and Cancel, as with vanilla's gadget choice.
func openStoryGadgetChoice(teamId: String, playerId: String) -> void:
	if not multiplayer.is_server():
		requestStoryGadgetChoice.rpc_id(1, teamId, playerId)
		return
	_open_story_gadget_choice(teamId, playerId)


@rpc("reliable", "any_peer")
func requestStoryGadgetChoice(teamId: String, playerId: String) -> void:
	if not (multiplayer.is_server() and _Story.is_story()):
		return
	var keeper: Keeper = Keepers.getKeeper(playerId)
	if keeper == null or keeper.peerId != multiplayer.get_remote_sender_id() or keeper.teamId != teamId:
		return
	# The shop panel checks the price before asking; the host checks it again.
	var cost = GameWorld.upgrades.get(_GadgetShop.next_entry(teamId), {}).get("cost", {})
	if cost is Dictionary and not GameWorld.canAfford(cost, teamId):
		return
	_open_story_gadget_choice(teamId, playerId)


func _open_story_gadget_choice(teamId: String, playerId: String) -> void:
	if _GadgetShop.next_entry(teamId) == "" or _GadgetShop.candidates(teamId, playerId).is_empty():
		return
	# Only with no choice open for the player: queued behind one, the mark would
	# make that open choice (a found gadget, or the shop's own) the shop's.
	if story_shop.has(playerId) or currentOfferTypeByPlayerId.get(playerId, "") != "":
		return
	story_shop[playerId] = true
	var keeper: Keeper = Keepers.getKeeper(playerId)
	if keeper and keeper.peerId != 1:
		# Sent before vanilla's popup call, on the same ordered channel.
		markStoryShopChoice.rpc_id(keeper.peerId, playerId)
	queueChoice(CONST.GADGET, teamId, playerId)


# Client: the gadget choice the host opens next for this player is the shop's.
@rpc("reliable")
func markStoryShopChoice(playerId: String) -> void:
	story_shop[playerId] = true


func startGadgetChoiceInput(teamId: String, playerId: String, offerType: String):
	if not (_Story.is_story() and offerType == CONST.GADGET and story_shop.has(playerId)):
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
	# The shop's focused panel keeps the focus under the popup, and vanilla only
	# focuses the first card when nothing has focus: the select key and the
	# arrows would still work the shop (#234). Free the focus for the cards and
	# give it back to the panel when the choice closes.
	var vp: Viewport = i.popup.get_viewport()
	var prev: Control = vp.gui_get_focus_owner() if vp != null else null
	if prev != null:
		prev.release_focus()
		var cards: Array = i.popup.get_node("%Gadgets").get_children()
		if not cards.is_empty():
			InputSystem.grabFocus(cards.front())
		i.connect("onStop", func():
			if is_instance_valid(prev) and prev.is_inside_tree() and prev.is_visible_in_tree():
				InputSystem.grabFocus(prev))
	showingChoicePopup = true
	i.connect("onStop", unpause)
	i.connect("onStop", Network.rpc_server.bind(continueOfferQueue.bind(playerId)))
	if not multiplayer.is_server():
		# The host clears its mark in continueOfferQueue; a client clears its own.
		i.connect("onStop", func(): story_shop.erase(playerId))
	i.connect("gadgetSelected", onGadgetSelected)
	i.integrate(self)
	pause()


func _from_shop(playerId: String) -> bool:
	return _Story.is_story() and currentOfferTypeByPlayerId.get(playerId, "") == CONST.GADGET and story_shop.has(playerId)


func generateOffers(teamId: String, playerId: String) -> void:
	if not _from_shop(playerId):
		super(teamId, playerId)
		return
	var ids: Array = _GadgetShop.offers(teamId, playerId)
	var newOffers: Array[Dictionary] = []
	for id: String in ids:
		var o: Dictionary = GameWorld.getGadgetOffer(id)
		if o.size():
			newOffers.append(o)
	currentOffersByPlayerId[playerId] = newOffers
	var rerollPossible: bool = _GadgetShop.candidates(teamId, playerId).size() > newOffers.size()
	var rerollCost: int = GadgetShop.REROLL_WATER
	offersGenerated.emit(playerId, newOffers, rerollPossible, rerollCost, 0)
	var offerIds: Array[String] = []
	for o: Dictionary in newOffers:
		offerIds.append(o["id"])
	var keeper: = Keepers.getKeeper(playerId)
	Network.rpc_or_local(keeper.peerId, remoteSetOffers.bind(playerId, CONST.GADGET, offerIds, rerollPossible, rerollCost, 0))


@rpc("reliable", "any_peer")
func remoteSetOffers(playerId: String, offerType: String, offerIds: Array[String], rerollPossible: bool, rerollCost: int, freeRerolls: int) -> void:
	# Not _from_shop: a client has the shop mark but not the host's offer type.
	if not (_Story.is_story() and offerType == CONST.GADGET and story_shop.has(playerId)):
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
	_GadgetShop.reroll(teamId, playerId)
	generateOffers(teamId, playerId)


@rpc("reliable", "any_peer")
func addGadgetUpgrade(id: String, offerType: String, playerId: String, teamId: String):
	if not _from_shop(playerId) or offerType != CONST.GADGET:
		super(id, offerType, playerId, teamId)
		return
	var entry: String = _GadgetShop.next_entry(teamId)
	var cost: int = _GadgetShop.price(teamId)
	if entry == "" or not _GadgetShop.offers(teamId, playerId).has(id) or Data.ofOr(teamId + ".inventory.money", 0) < cost:
		Network.rpc_or_local(Keepers.getKeeper(playerId).peerId, acceptGadgetSelection.bind(false, playerId))
		return
	# The entry is bought the vanilla way: that charges its price and unlocks the next one.
	GameWorld.buyUpgrade(entry, teamId, playerId)
	if not GameWorld.boughtUpgrades.has(entry):
		Network.rpc_or_local(Keepers.getKeeper(playerId).peerId, acceptGadgetSelection.bind(false, playerId))
		return
	_GadgetShop.clear(teamId)
	ModLoaderLog.info("Gadget shop: %s bought with %s for $%d" % [id, entry, cost], Story.LOG)
	super(id, offerType, playerId, teamId)


# A player who leaves with a shop choice open never closes it: drop the mark,
# or the keeper's next player (a drop-in) could never open the shop (#234).
func on_level_keeper_removed(keeper: Keeper) -> void:
	if keeper != null:
		story_shop.erase(keeper.playerId)
	super(keeper)


@rpc("reliable", "any_peer")
func continueOfferQueue(playerId: String) -> void:
	story_shop.erase(playerId)
	super(playerId)
