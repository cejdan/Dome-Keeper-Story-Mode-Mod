extends RefCounted

# Monster pleas (#91): lines the monsters shout above the dome during waves.
# Pools by the deepest biome the keeper has reached (beats/story_beats.gd
# deepest(): 0 = B1 .. 7 = B8, 8 = the lava ocean). Each stage has three kinds:
#   arrive  one line when a wave arrives
#   fight   one or two lines during the fight
#   death   now and then, a monster's last words where it falls
# Words in *asterisks* are key words: they translate first (#92).
# Lines are the story script (docs/story/script.md, #25).

const STAGES: Dictionary = {
	"A": {  # B1 to B2: warning
		"arrive": [
			"*Stop*. Go home, small digger.",
			"Ground is *sleeping*. Let it sleep.",
			"You dig *wrong* place. *Leave*.",
			"Not for you. Go *away*, please.",
			"We *warn*. We only warn.",
			"Quiet the drill. Something *listens*.",
		],
		"fight": [
			"*Why* you *dig*? Why?",
			"No more *holes*. No more!",
			"*Stop* the drill!",
			"We not want *hurt*. Just *stop*.",
			"Down is *bad*. Down is bad!",
			"You *hear* it? Do not *listen*.",
			"Go *up*. Go *home*.",
			"Leave the stones. Stones keep it *asleep*.",
		],
		"death": [
			"Please... *stop*...",
			"Tell it... we *tried*...",
			"*Warned* you. Warned you...",
			"Not us... *it*... it wakes...",
			"Go *home*, digger...",
			"So *quiet*... soon so quiet...",
		],
	},
	"B": {  # B3 to B5: begging
		"arrive": [
			"*Please*. We beg you. *Please*.",
			"*Stop* digging. We give anything.",
			"It *sleeps* under you. Please!",
			"Small digger, *listen*. Only listen.",
			"We bring no anger. Bring *fear*.",
			"Every hole you make, it *breathes*.",
		],
		"fight": [
			"*Please*! Please stop!",
			"It *talks* to you. It *lies*.",
			"Warm rock is *it*. Not warm. *It*!",
			"Do not go *deeper*!",
			"We have *children* up here!",
			"It *whispers*? Cover your *ears*!",
			"You are *helping* it!",
			"*Stop*, stop, stop!",
		],
		"death": [
			"Please... *please*...",
			"My *children*... keep them...",
			"It says... *deeper*... do not...",
			"You... *heard*... us?",
			"Not angry... *afraid*...",
			"*Sorry*... sorry we hit dome...",
		],
	},
	"C": {  # B6 to B8: despair
		"arrive": [
			"Too *deep*. You are too deep.",
			"Others came *down*. *Never* came up.",
			"*Why*? Why you not stop?",
			"We fight. Nothing *else* left.",
			"*Bright* stone holds it *down*.",
			"Leave the *seal*. It is last.",
		],
		"fight": [
			"*Turn* back! Still time!",
			"It does not *love*. It *eats*.",
			"We are *dying* for this!",
			"Last *seal*! Last one!",
			"Not *hate* you. *Fear*!",
			"Hear *us*! Not it. Us!",
			"*Bones* below. Miner *bones*. Look!",
			"For *shiny*? All this for shiny?",
		],
		"death": [
			"No more... *time*...",
			"It *smiles*... we feel it smile...",
			"Was our *home*... was home...",
			"You will... *wake* it...",
			"*Remember* us...",
			"Go *up*... while sky still...",
		],
	},
	"D": {  # lava ocean and below: grief
		"arrive": [
			"*Too* *late*. Too late now.",
			"It is *waking*. You did this.",
			"We came to say *goodbye*.",
			"No fight left. Only *sing*.",
			"We sing it to *sleep*. It not listen.",
			"The *ground* is *breathing*.",
		],
		"fight": [
			"Was there *nothing* we could say?",
			"*Shiny*. All this for shiny.",
			"Our young hide. *Nowhere* to hide.",
			"Hit dome. *Nothing* else to do.",
			"Stop *now*? Please? Even now?",
			"It *sings* to you. We *hear* it.",
			"You were *warned*. Every day, warned.",
			"*Sky* goes *dark* soon.",
		],
		"death": [
			"*Goodbye*... digger...",
			"At least... I *sleep* first...",
			"I *forgive*... I try to...",
			"*Home*... was so *pretty*...",
			"You took... *everything*...",
			"*Dark* now... very dark...",
		],
	},
}


# Deepest biome index -> stage: B1-B2 warning, B3-B5 begging, B6-B8 despair,
# the ocean and below grief.
static func stage_for(deepest: int) -> String:
	if deepest >= 8:
		return "D"
	if deepest >= 5:
		return "C"
	if deepest >= 2:
		return "B"
	return "A"


static func pool(stage: String, kind: String) -> Array:
	return STAGES.get(stage, {}).get(kind, [])


# The line as plain English: key-word marks removed.
static func plain(line: String) -> String:
	return line.replace("*", "")
