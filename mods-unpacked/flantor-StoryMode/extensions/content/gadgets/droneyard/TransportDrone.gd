extends "res://content/gadgets/droneyard/TransportDrone.gd"

# A drone carrying a Story Mode mineral (or the miner bones) shows it in its
# claws and plays the carry animation, like vanilla's iron, water and sand
# (#270). Vanilla's setCarriedResource matches only its own types, so these
# got no texture and no carry animation. Packs get the same art for any Story
# piece inside (util/carry_art.gd).

const CarryArt = preload("res://mods-unpacked/flantor-StoryMode/util/carry_art.gd")
static var _CarryArt = CarryArt  # calls go through this: lazy_preload makes const-preload calls slow


# Asking for a way home again and again with none there (a drone sealed in by
# rock, #313) backs off: after HOME_RETRIES_AT_FULL_RATE failed asks at
# vanilla's 0.5 s, the wait doubles each time up to HOME_RETRY_MAX. Back to
# vanilla's rate once a cell opens within RETRY_RESET_TILES of the drone, and
# the count starts over when a way is found. A drone in WAIT that the
# dispatcher can't send anywhere because it is cut off from home sits out the
# hand-out the same way (DroneDispatcher.gd).
const HOME_RETRY := 0.5
const HOME_RETRIES_AT_FULL_RATE := 3
const HOME_RETRY_MAX := 6.0
const RETRY_RESET_TILES := 3

var _path_cells: Dictionary = {}   # Vector2i -> the last index of currentPath in that cell
var story_failed_asks := 0         # asks in a row that found no way
var story_hand_out_after := 0      # Time.get_ticks_msec(): no hand-out to this drone before


func _ready():
	super()
	if Level.map != null and Level.map.has_signal("path_cell_closed"):
		Level.map.path_cell_closed.connect(_on_path_cell_closed)


func targetDrop(drop, path, dropPosition: Vector2):
	super(drop, path, dropPosition)
	_found_a_way()


func setPathHome(path):
	super(path)
	_found_a_way()


func _physics_process(delta):
	var asking: bool = state == State.WAIT_FOR_PATH_HOME and cooldown <= 0.0 and not GameWorld.paused and not GameWorld.gameover
	super(delta)
	# Vanilla asked (request_path_home) and set its 0.5 s cooldown; no way was found.
	if asking and state == State.WAIT_FOR_PATH_HOME:
		cooldown = no_way_found()


# One more ask found no way: the wait before the next (seconds).
func no_way_found() -> float:
	story_failed_asks += 1
	var wait: float = HOME_RETRY
	if story_failed_asks > HOME_RETRIES_AT_FULL_RATE:
		wait = minf(HOME_RETRY * pow(2.0, story_failed_asks - HOME_RETRIES_AT_FULL_RATE), HOME_RETRY_MAX)
	if Level.map != null and Level.map.has_signal("path_cell_opened") and not Level.map.path_cell_opened.is_connected(_on_path_cell_opened):
		Level.map.path_cell_opened.connect(_on_path_cell_opened)
	return wait


func _found_a_way() -> void:
	# The cells of the new path, for _on_path_cell_closed.
	_path_cells.clear()
	if Level.map != null:
		for i in currentPath.size():
			_path_cells[Level.map.getTileCoord(currentPath[i])] = i
	if story_failed_asks == 0:
		return
	story_failed_asks = 0
	story_hand_out_after = 0
	if Level.map != null and Level.map.has_signal("path_cell_opened") and Level.map.path_cell_opened.is_connected(_on_path_cell_opened):
		Level.map.path_cell_opened.disconnect(_on_path_cell_opened)


# Only drones that found no way listen (no_way_found connects them): a cell
# opening near one may be its way out, so it asks again at vanilla's rate.
func _on_path_cell_opened(coord: Vector2) -> void:
	var at: Vector2i = Level.map.getTileCoord(global_position)
	if absi(int(coord.x) - at.x) > RETRY_RESET_TILES or absi(int(coord.y) - at.y) > RETRY_RESET_TILES:
		return
	story_failed_asks = 0
	story_hand_out_after = 0
	cooldown = minf(cooldown, HOME_RETRY)


# A cell on this drone's way turned back into rock (Map.path_cell_closed,
# #313): look for a new way instead of flying through it. Picking up: drop the
# target (the host's dispatcher hands it out again with a fresh path; clients
# follow its RPC). Carrying home: ask for a new path home, as after a pickup.
# Every drone listens, so the check is one lookup in the path's cells.
func _on_path_cell_closed(coord: Vector2) -> void:
	if state != State.PICKUP and state != State.RETRIEVE:
		return
	var i: int = _path_cells.get(Vector2i(coord), -1)
	if i < 0 or i < currentPathIndex - 1:
		return
	if state == State.PICKUP:
		if multiplayer.is_server():
			stopped_targeting_drop.emit()
	else:
		state = State.WAIT_FOR_PATH_HOME
		cooldown = 0.0


func setCarriedResource(res: String):
	var art: Texture2D = _CarryArt.of(res)
	if art == null:
		super(res)
		if res == CONST.PACK:
			_CarryArt.fix_pack($CarriedResource, packedDropContent)
		return
	carriedResource = res
	$CarriedResource.texture = art
	$Sprite.play("carry_idle")
	$SpriteOverlay.visible = true
	$SpriteOverlay.play("carry_idle")
	$PickupSound.startSound()
