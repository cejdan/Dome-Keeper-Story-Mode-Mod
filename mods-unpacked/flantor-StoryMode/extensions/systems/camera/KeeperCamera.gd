extends "res://systems/camera/KeeperCamera.gd"

# A keeper's camera made before its team's dome (#263). With lobby keepers,
# vanilla's MultiplayerloadoutStage.build spawns them before setLoadout adds
# the loadout dome, so now and then a camera inits with Level.domesByTeamId
# empty, and updateCameraRestPosition reads a missing key (a script error;
# the end screen's Another Run in splitscreen, in Relic Hunt as well). Here
# the camera takes the rest height at once and the dome's x once the dome is
# there, a frame or a few later. With the dome there it is vanilla's.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")


func updateCameraRestPosition():
	if target == null or not is_instance_valid(target) or Level.domesByTeamId.has(target.teamId):
		super()
		return
	cameraRestPositionInDome.y = getCameraRestPosition(zoomStagePx)
	ModLoaderLog.info("Keeper camera: %s's team has no dome yet; its rest spot waits for it" % str(target.playerId), Story.LOG)
	var tree := Engine.get_main_loop() as SceneTree
	if not tree.process_frame.is_connected(_rest_x_later):
		tree.process_frame.connect(_rest_x_later)
	_waits = 0


var _waits := 0


# Each frame until the dome is there (a connection to a freed camera goes
# with it); gives up after 10 s.
func _rest_x_later() -> void:
	_waits += 1
	var done: bool = _waits > 600 or target == null or not is_instance_valid(target)
	if not done and Level.domesByTeamId.has(target.teamId):
		# The camera eases to it on its own while the keeper is inside.
		super.updateCameraRestPosition()
		done = true
	if done:
		(Engine.get_main_loop() as SceneTree).process_frame.disconnect(_rest_x_later)
