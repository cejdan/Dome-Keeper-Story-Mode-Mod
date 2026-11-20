extends "res://mods-unpacked/cejdan-StoryMode/dev/mp_scenario.gd"

# #229: client half. The welcome log opens here and pauses the game; the host
# closing its box doesn't close this one; closing this one resumes the game.
# This keeper walks into B2 and the depth beat opens; this player closes first
# and waits, paused, for the host. Then the host's sale pops, plea and heat
# line show here, this player buys Retire Rich, and the doom ending plays here
# to the end screen. Pair: t229_mp_story_host.

const TIMEOUT := 600
const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")
const Endings = preload("res://mods-unpacked/cejdan-StoryMode/data/endings.gd")
const Host = preload("res://mods-unpacked/cejdan-StoryMode/dev/scenarios/t229_mp_story_host.gd")


func boot() -> Dictionary:
	return {"netjoin": true}


func run(h) -> void:
	h.check("this is a client", not h.multiplayer.is_server())
	var sb = StoryBeats.instance()

	# --- the welcome log: the host closes first, this player after.
	var opened: bool = await h.until(func(): return sb.open_id == "keeper_welcome", 40.0)
	h.check("welcome log opens on the client", opened, [sb.open_id, Data.ofOr(StoryBeats.OPEN, "")])
	await h.wait(1.0)
	h.check("the client's game is paused", GameWorld.paused)
	h.check("the log box is on screen", h.beat_box() != null and h.beat_box().name == "StoryLogPopup")
	await h.shot("client_welcome")
	var p0: Vector2 = h.keeper().global_position
	h.down("ui_left")
	# The host closes its own box meanwhile.
	await h.wait(8.0)
	h.up("ui_left")
	h.check("still open here after the host closed theirs", sb.open_id == "keeper_welcome" and h.beat_box() != null and GameWorld.paused)
	h.check("the keeper stood still", h.keeper().global_position.distance_to(p0) < 1.0, h.keeper().global_position - p0)
	h.check("client closes its box", await Host.close_mine(h))
	var closed: bool = await h.until(func(): return not StoryBeats.team_open(), 5.0)
	h.check("the beat closes for the team", closed and StoryBeats.has_played("keeper_welcome"), Data.ofOr(StoryBeats.PLAYED, ""))
	await h.wait(0.5)
	h.check("the client's game runs again", not GameWorld.paused)
	h.check("it doesn't reopen", sb.open_id == "" and h.beat_box() == null)
	await h.shot("client_welcome_closed")

	# --- the depth beat: this keeper goes to B2; this player closes first.
	var b2 = await shared(h, "b2", 60.0)
	h.check("host dug a room in B2", b2 != null, b2)
	if b2 == null:
		return
	await h.teleport_tile(Vector2i(int(b2[0]), int(b2[1])))
	opened = await h.until(func(): return sb.open_id == "biome_b2", 20.0)
	h.check("the depth beat opens on the client", opened, sb.open_id)
	await h.wait(1.0)
	h.check("paused for the depth beat", GameWorld.paused)
	await h.shot("client_b2")
	h.check("client closes its box first", await Host.close_mine(h))
	await h.wait(1.0)
	h.check("the beat is still open for the team", StoryBeats.team_open() and GameWorld.paused)
	h.check("client sees the waiting line", Host.waiting_label(h))
	await h.shot("client_waiting")
	closed = await h.until(func(): return not StoryBeats.team_open(), 60.0)
	h.check("depth beat closed once the host closed", closed and StoryBeats.has_played("biome_b2"))
	await h.wait(0.5)
	h.check("running again", not GameWorld.paused and not Host.waiting_label(h))

	# --- the host's sale pops, plea and heat line.
	var dome = Level.getDome("team1")
	h.keeper().teleport(dome.global_position + Vector2(0, -8))
	h.snap_camera()
	var pops = load("res://mods-unpacked/cejdan-StoryMode/hud/sale_pops.gd").instance()
	var popped: bool = await h.until(func(): return pops.shown.size() >= 1, 30.0)
	await h.shot("client_pop")
	var sold = await shared(h, "sold", 30.0)
	h.check("sale pops show on the client", popped and sold != null and pops.shown.size() == int(sold["pops"]) and pops.shown.size() == 3, [pops.shown, sold])
	h.check("the client has the money", sold != null and int(Data.ofOr("team1.inventory.money", 0)) == int(sold["money"]) and int(sold["money"]) > 0, sold)
	var pd = load("res://mods-unpacked/cejdan-StoryMode/pleas/plea_director.gd").instance()
	h.check("the host's plea shows here, same line", sold != null and pd.shown.size() == 1 and pd.shown[0]["line"] == sold["plea"] and sold["plea"] != "", [pd.shown, sold])
	var ht = load("res://mods-unpacked/cejdan-StoryMode/hud/heat_talk.gd").instance()
	h.check("the host keeper's heat line shows here", ht.shown_remote.size() == 1 and ht.shown_remote[0]["text"] == "so hot", ht.shown_remote)
	await h.shot("client_plea_heat")
	h.check("no plea of the client's own", pd.say("arrive") == "" and pd.shown.size() == 1)
	ht._say(Keepers.local.keepers[0], "so hot", Color("ff7a3c"), "hot")

	# --- Retire Rich.
	var rich = await shared(h, "rich", 60.0)
	await h.until(func(): return int(Data.ofOr("team1.inventory.money", 0)) >= 1000000, 10.0)
	h.check("the team has $1,000,000", rich != null and int(Data.ofOr("team1.inventory.money", 0)) == 1000000, Data.ofOr("team1.inventory.money", 0))
	await h.buy("storyretirerich")
	opened = await h.until(func(): return sb.open_id == "doom_thanks", 30.0)
	h.check("the ending's beat opens on the client", opened, sb.open_id)
	h.check("the client's mode is in its ending", Level.mode.is_ending())
	await h.wait(2.0)
	await h.shot("client_thanks")
	# The host closes first; the box here stays until this player is done.
	await h.wait(8.0)
	h.check("thanks still open here", sb.open_id == "doom_thanks" and h.beat_box() != null)
	var n0: int = pd.shown.size()
	h.check("client reads the thanks", await Host.close_mine(h))
	var words: bool = await h.until(func(): return pd.shown.size() >= n0 + Endings.DOOM_LAST_WORDS.size(), 30.0)
	var said: Array = pd.shown.slice(n0).map(func(e): return e["line"])
	h.check("the monsters' last words show on the client", words and said == Endings.DOOM_LAST_WORDS, said)
	await h.shot("client_last_words")
	var cards: bool = await h.until(func(): return h.get_tree().get_nodes_in_group("story-beat-box").any(func(n): return n.name.begins_with("StoryEndingCards")), 20.0)
	h.check("the ending's cards show on the client", cards)
	await h.wait(3.0)
	var box = null
	for n in h.get_tree().get_nodes_in_group("story-beat-box"):
		if n.name.begins_with("StoryEndingCards"):
			box = n
	h.check("a doom card is on screen", box != null and box.current_card() in Endings.DOOM_CARDS, box.current_card() if box != null else null)
	await h.shot("client_cards")
	var panel: bool = await h.until(func(): return Level.stage.endingPanel != null, 120.0)
	h.check("end screen on the client", panel and GameWorld.won, [GameWorld.won, GameWorld.lost])
	await h.wait(2.5)
	var ep = Level.stage.endingPanel
	h.check("titled for the doom ending", ep != null and ep.titleLabel.text == Endings.DOOM_TITLE, ep.titleLabel.text if ep != null else null)
	h.check("the cards are gone", not h.get_tree().get_nodes_in_group("story-beat-box").any(func(n): return n.name.begins_with("StoryEndingCards") and not n._closing))
	await h.shot("client_end_screen")
	await h.wait(4.0)
	h.check("exactly one set of ending cards and one end screen here", Level.mode.get_node("StoryEndings").cards_shown == 1 and Level.mode.end_screens == 1, [Level.mode.get_node("StoryEndings").cards_shown, Level.mode.end_screens])
