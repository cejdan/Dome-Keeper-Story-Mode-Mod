extends InputProcessor

# Input for an open story beat: it swallows every key, so the keeper and the
# dome stay still, and closes the box on select, accept, cancel, Escape or a
# left click. Closing is ignored for a moment after the box opens, so a key the
# player was already pressing doesn't dismiss the beat unread.

const MIN_OPEN_MS := 700

var popup
var _opened_at: int = 0


func handleStart() -> void:
	_opened_at = Time.get_ticks_msec()
	popup.move_in()


func handleStop() -> void:
	popup.move_out()


func buttonEvent(event) -> bool:
	if Time.get_ticks_msec() - _opened_at < MIN_OPEN_MS:
		return true
	var close: bool = false
	for a: String in ["ui_select", "ui_accept", "ui_cancel", "escape"]:
		if justPressed(event, a):
			close = true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close = true
	if close:
		Audio.sound("gui_confirm")
		desintegrate()
	return true
