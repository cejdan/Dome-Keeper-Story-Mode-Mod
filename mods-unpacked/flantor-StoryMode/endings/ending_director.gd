extends Node

# The two story endings (#96, #97), played by the Story Mode game mode node.
#
# Doom (Retire Rich bought): the horror thanks the keeper (story beat
# "doom_thanks", tier 4, three pages), the monsters' last words float over the
# dome one by one at the current translation stage (all runes with no
# translators), the planet's end in narration cards, then the end screen
# "The Planet Is Lost". Still a won run with the $1M.
#
# Saved (the horror defeated): narration cards, then the end screen "The Planet
# Is Saved". The won boss finale calls Storymode.horror_defeated(); so does
# `-- --horror-defeated`.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const Endings = preload("res://mods-unpacked/flantor-StoryMode/data/endings.gd")
const StoryBeats = preload("res://mods-unpacked/flantor-StoryMode/beats/story_beats.gd")
static var _StoryBeats = StoryBeats  # calls go through this: lazy_preload makes const-preload calls slow

signal step(name: String)

var playing: String = ""
var last_step: String = ""


func _step(s: String) -> void:
	last_step = s
	ModLoaderLog.info("Ending: " + s, Story.LOG)
	step.emit(s)


func play_doom() -> void:
	playing = "doom"
	_step("thanks")
	var beats = _StoryBeats.instance()
	if beats != null:
		await beats.play_now("doom_thanks")
	_step("last_words")
	var pd = load(Story.MOD_DIR + "pleas/plea_director.gd").instance()
	if pd != null:
		for line: String in Endings.DOOM_LAST_WORDS:
			pd.say("arrive", null, line, 3.6)
			await get_tree().create_timer(3.4).timeout
	_step("cards")
	await _cards(Endings.DOOM_CARDS, "doom")
	_step("end_screen")


func play_saved() -> void:
	playing = "saved"
	_step("cards")
	await _cards(Endings.SAVED_CARDS, "saved")
	_step("end_screen")


# The lost ending (#162): the keeper fell to Velle.
func play_fallen() -> void:
	playing = "fallen"
	_step("cards")
	await _cards(load(Story.MOD_DIR + "data/boss_text.gd").FALLEN_CARDS, "doom")
	_step("end_screen")


var _card_input = null
# Card sets shown on this instance (a playtest checks there is one per ending).
var cards_shown: int = 0


# Online (#229): the host's cards show on every client too, each running at
# its own player's pace; the host's own cards decide when the ending moves on.
@rpc("authority", "call_remote", "reliable")
func _net_cards(cards: Array, mood: String) -> void:
	_cards(cards, mood)


# Closes cards still on screen (a client, when the host's end screen comes).
func close_cards() -> void:
	if _card_input != null and is_instance_valid(_card_input) and not _card_input.desintegrating:
		_card_input.desintegrate()
	_card_input = null


func _cards(cards: Array, mood: String) -> void:
	if not Network.is_offline_mode() and multiplayer.is_server():
		Network.rpc_if_state(_net_cards.bind(cards, mood), Network.ConnectionState.LEVEL_STAGE_SYNC)
	cards_shown += 1
	var box = load(Story.MOD_DIR + "endings/CardBox.gd").new()
	box.cards = cards
	box.mood = mood
	var i = load(Story.MOD_DIR + "beats/BeatInputProcessor.gd").new()
	i.popup = box
	var k = _Story.local_keeper()
	i.deviceId = k.deviceId if k != null else 0
	i.globalInput = true
	Level.stage.showPopup(box, null, "", LevelStage.PopupCanvas.GLOBAL)
	i.integrate(Level.stage)
	_card_input = i
	var done: Array = [false]
	box.finished.connect(func(): done[0] = true)
	i.onStop.connect(func(): done[0] = true)
	while not done[0]:
		await get_tree().process_frame
	if is_instance_valid(i) and not i.desintegrating:
		i.desintegrate()
	await get_tree().create_timer(0.8).timeout


# Retitles vanilla's end screen popup for the ending that was played.
static func retitle(popup, title: String, subtitle: String) -> void:
	if popup == null or popup.get("titleLabel") == null:
		return
	popup.titleLabel.text = title
	var parent: Node = popup.titleLabel.get_parent()
	var sub: Label = Label.new()
	sub.name = "StorySubtitle"
	sub.text = subtitle
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.label_settings = load("res://gui/fontsettings/NormalFontSettings.tres")
	var box: Node = parent
	if parent is MarginContainer and parent.get_parent() is VBoxContainer:
		box = parent.get_parent()
		box.add_child(sub)
		box.move_child(sub, parent.get_index() + 1)
	else:
		parent.add_child(sub)
