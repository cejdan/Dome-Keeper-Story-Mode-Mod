extends InputProcessor

# Input while the last-chain cutscene plays (#367, endgame/last_chain.gd): it
# swallows every key, so no keeper acts while play is frozen. The pause key
# still opens the pause menu (to save and quit, or change options), and holding
# the use or accept key counts toward a skip (the cutscene reads `holding`).

var cutscene = null
var holding: bool = false


func buttonEvent(event) -> bool:
	if justPressed(event, "escape"):
		var k = Keepers.getLocalKeeperByDeviceId(deviceId) if deviceId >= 0 else null
		if k == null:
			k = cutscene._local_keeper() if cutscene != null else null
		if k != null and Level.stage != null:
			Level.stage.openPauseMenu(k)
		return true
	for a: String in ["ui_select", "ui_accept"]:
		if pressed(event, a):
			holding = true
		elif released(event, a):
			holding = false
	return true


func onPaused() -> void:
	holding = false
