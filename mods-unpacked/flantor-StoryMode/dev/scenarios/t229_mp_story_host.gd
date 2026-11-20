extends "res://mods-unpacked/flantor-StoryMode/dev/mp_scenario.gd"

# #229: host half. The welcome log opens for the team and pauses it; the host
# closes its box first and the beat stays open (and the game paused) until the
# client closes too. A depth beat fired by the client's keeper: the client
# closes first, the host last. Then a sale, a plea and a heat line for the
# client to see, and Retire Rich (the client buys it): the doom ending's beat,
# last words, cards and end screen on both. Pair: t229_mp_story_client.

const TIMEOUT := 600
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
const Endings = preload("res://mods-unpacked/flantor-StoryMode/data/endings.gd")


func boot() -> Dictionary:
	return {"loadout": true, "nethost": true, "beats": true, "welcome": true}


# Select until this player's own box is gone.
static func close_mine(h) -> bool:
	var sb = StoryBeats.instance()
	await h.wait(1.0)
	for i in 14:
		if sb._box == null or not is_instance_valid(sb._box):
			return true
		await h.press("ui_select")
		await h.wait(0.5)
	return sb._box == null or not is_instance_valid(sb._box)


static func waiting_label(h) -> bool:
	var sb = StoryBeats.instance()
	return sb._waiting != null and is_instance_valid(sb._waiting)


func run(h) -> void:
	if not await host_start(h):
		return
	var sb = StoryBeats.instance()

	# --- the welcome log: the host closes first.
	var opened: bool = await h.until(func(): return sb.open_id == "keeper_welcome", 40.0)
	h.check("welcome log opens on the host", opened, sb.open_id)
	h.note("client states at open", Network.clients.map(func(c): return c.connection_state))
	await h.wait(1.0)
	h.check("the host's game is paused", GameWorld.paused)
	h.check("the open beat is in Data", str(Data.ofOr(StoryBeats.OPEN, "")).ends_with(":keeper_welcome"), Data.ofOr(StoryBeats.OPEN, ""))
	await h.shot("host_welcome")
	h.check("host closes its own box", await close_mine(h))
	await h.wait(1.5)
	h.check("the beat stays open for the team", sb.open_id == "keeper_welcome" and StoryBeats.team_open() and not StoryBeats.has_played("keeper_welcome"))
	h.check("still paused while the client reads", GameWorld.paused)
	h.check("host sees the waiting line", waiting_label(h))
	await h.shot("host_waiting")
	var closed: bool = await h.until(func(): return sb.open_id == "", 60.0)
	h.check("welcome closes once the client closed", closed and StoryBeats.has_played("keeper_welcome") and not StoryBeats.team_open())
	await h.wait(0.5)
	h.check("the host's game runs again", not GameWorld.paused)
	h.check("the waiting line is gone", not waiting_label(h))

	# --- a depth beat from the client's keeper: a room in B2.
	var td = Level.map.tileData
	var lava = Level.map.get_node("StoryLavaField")
	var spot = null
	for x in [0, 3, -3, 6, -6, 9, -9]:
		for y in range(2, 60):
			if td.get_biomev(Vector2i(x, y)) == 1:
				var c := Vector2i(x, y + 3)
				var clear := true
				for dy in range(-3, 4):
					for dx in range(-3, 4):
						if lava.magma.has(c + Vector2i(dx, dy)):
							clear = false
				if clear and td.get_biomev(c) == 1:
					spot = c
				break
		if spot != null:
			break
	h.check("a spot in B2", spot != null, spot)
	if spot == null:
		return
	await h.dig_room(spot + Vector2i(-1, 0), spot + Vector2i(1, 1))
	await h.wait(1.0)
	share("b2", [spot.x, spot.y])
	opened = await h.until(func(): return sb.open_id == "biome_b2", 60.0)
	h.check("the client's keeper in B2 fires the depth beat", opened, sb.open_id)
	h.check("host keeper is still at the dome", h.keeper_tile().y < 3, h.keeper_tile())
	await h.wait(1.0)
	h.check("paused for the depth beat", GameWorld.paused)
	await h.shot("host_b2")
	var acked: bool = await h.until(func(): return sb._acks.size() >= 1, 60.0)
	h.check("the client closed first", acked and not sb._acks.has(1), sb._acks)
	await h.wait(1.5)
	h.check("the beat waits for the host", sb.open_id == "biome_b2" and GameWorld.paused and sb._box != null)
	h.check("host closes its box", await close_mine(h))
	closed = await h.until(func(): return sb.open_id == "", 5.0)
	h.check("depth beat closed for the team", closed and StoryBeats.has_played("biome_b2"))
	await h.wait(0.5)
	h.check("running again", not GameWorld.paused)

	# --- a sale, a plea and a heat line.
	await h.wait(2.0)
	await h.deliver("iron", 3)
	await h.wait(3.0)
	var pd = load("res://mods-unpacked/flantor-StoryMode/pleas/plea_director.gd").instance()
	var line: String = pd.say("arrive", null, "", 6.0)
	var ht = load("res://mods-unpacked/flantor-StoryMode/hud/heat_talk.gd").instance()
	ht._say(Keepers.local.keepers[0], "so hot", Color("ff7a3c"), "hot")
	await h.wait(1.0)
	await h.shot("host_pops_plea")
	share("sold", {"money": Data.ofOr("team1.inventory.money", 0), "plea": line, "pops": load("res://mods-unpacked/flantor-StoryMode/hud/sale_pops.gd").instance().shown.size()})
	var heard: bool = await h.until(func(): return ht.shown_remote.size() >= 1, 30.0)
	h.check("host sees the client keeper's heat line", heard, ht.shown_remote)

	# --- Retire Rich, bought by the client.
	await h.wait(4.0)
	Data.apply("team1.inventory.money", 1000000)
	share("rich", true)
	var ending: bool = await h.until(func(): return Level.mode.is_ending(), 30.0)
	h.check("the client's purchase starts the ending on the host", ending)
	if not ending:
		await h.buy("storyretirerich")
	opened = await h.until(func(): return sb.open_id == "doom_thanks", 20.0)
	h.check("the ending's beat opens", opened, sb.open_id)
	await h.wait(2.0)
	await h.shot("host_thanks")
	h.check("host reads the thanks", await close_mine(h))
	closed = await h.until(func(): return sb.open_id == "", 90.0)
	h.check("thanks closed for the team", closed)
	var endings = Level.mode.get_node("StoryEndings")
	await h.until(func(): return endings.last_step == "last_words", 10.0)
	await h.wait(2.0)
	await h.shot("host_last_words")
	var cards: bool = await h.until(func(): return endings.last_step == "cards", 30.0)
	h.check("cards on the host", cards, endings.last_step)
	await h.wait(3.0)
	await h.shot("host_cards")
	var panel: bool = await h.until(func(): return Level.stage.endingPanel != null, 120.0)
	h.check("end screen on the host", panel and GameWorld.won)
	await h.wait(2.5)
	await h.shot("host_end_screen")
	await h.wait(4.0)
	h.check("exactly one set of ending cards and one end screen here", Level.mode.get_node("StoryEndings").cards_shown == 1 and Level.mode.end_screens == 1, [Level.mode.get_node("StoryEndings").cards_shown, Level.mode.end_screens])
	await host_wait_clients_left(h, 120.0)
