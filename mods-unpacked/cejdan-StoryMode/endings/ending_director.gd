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
# Is Saved". The future boss fight calls Storymode.horror_defeated(); until it
# exists only a dev command reaches it (`-- --horror-defeated`, or the harness
# calling Level.mode.horror_defeated()).

const Story = preload("res://mods-unpacked/cejdan-StoryMode/story.gd")
const Endings = preload("res://mods-unpacked/cejdan-StoryMode/data/endings.gd")
const StoryBeats = preload("res://mods-unpacked/cejdan-StoryMode/beats/story_beats.gd")

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
	var beats = StoryBeats.instance()
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


func _cards(cards: Array, mood: String) -> void:
	var box = load(Story.MOD_DIR + "endings/CardBox.gd").new()
	box.cards = cards
	box.mood = mood
	var i = load(Story.MOD_DIR + "beats/BeatInputProcessor.gd").new()
	i.popup = box
	var k = Keepers.first()
	i.deviceId = k.deviceId if k != null else 0
	i.globalInput = true
	Level.stage.showPopup(box, null, "", LevelStage.PopupCanvas.GLOBAL)
	i.integrate(Level.stage)
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
