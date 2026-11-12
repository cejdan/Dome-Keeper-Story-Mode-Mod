extends InputProcessor

# Input for an open story beat: it swallows every key, so the keeper and the
# dome stay still. Select, accept, cancel, Escape or a left click first finish
# the typing-out of the text, then close the box. Keys are ignored for a moment
# after the box opens, and closing waits a little longer, so a key the player
# was already pressing doesn't dismiss the beat unread.

const IGNORE_MS := 300
const MIN_OPEN_MS := 700

var popup
var _opened_at: int = 0


func handleStart() -> void:
	_opened_at = Time.get_ticks_msec()
	popup.move_in()


func handleStop() -> void:
	popup.move_out()


func buttonEvent(event) -> bool:
	var age: int = Time.get_ticks_msec() - _opened_at
	if age < IGNORE_MS:
		return true
	var hit: bool = false
	for a: String in ["ui_select", "ui_accept", "ui_cancel", "escape"]:
		if justPressed(event, a):
			hit = true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hit = true
	if not hit:
		return true
	if popup.is_revealing():
		popup.finish_reveal()
	elif age >= MIN_OPEN_MS:
		Audio.sound("gui_confirm")
		desintegrate()
	return true
