extends Node

# Gas in the dome (#213). Gas that vents out of the mine through the shaft
# under the dome goes into the dome and stays there: the keeper breathes it
# while inside (the gas field's toxin bar fills from it, far slower than in the
# cave and faster the more there is), and the only sign of it is a green haze
# over the dome's inside that thickens as it builds. The shop's "Vent the
# Dome" (data/upgrades.yaml) clears it back to nothing.
#
# A child of the gas field; the amount is saved with the field's own state.

const GasData = preload("res://mods-unpacked/flantor-StoryMode/data/gas.gd")
const GasSfx = preload("res://mods-unpacked/flantor-StoryMode/gas/gas_sfx.gd")
const VENT_ID := "storyventdome"
const HAZE_Z := 29                 # over the keeper and the dome's insides, under the glass (30)

var field
var amount := 0.0                  # gas vented into the dome, in the field's units
var vents := 0                     # times the dome was vented this run
var shown := 0.0                   # the haze as drawn, 0..1 (eases toward haze())

var _dome = null
var _mats: Array = []              # one per haze sprite: [material, share of the haze it shows]
var _sprites: Array = []

const HAZE := preload("res://mods-unpacked/flantor-StoryMode/gas/look/dome_haze.gdshader")


func setup(p_field) -> void:
	field = p_field
	GameWorld.upgradeAdded.connect(_on_upgrade_added)


func _exit_tree() -> void:
	if GameWorld.upgradeAdded.is_connected(_on_upgrade_added):
		GameWorld.upgradeAdded.disconnect(_on_upgrade_added)
	for s in _sprites:
		if is_instance_valid(s):
			s.queue_free()
	_sprites.clear()


# The dome's gas in pockets' worth (the unit the tuning numbers use).
func pockets() -> float:
	return amount / GasData.DOME_POCKET_MASS


func add(m: float) -> void:
	amount += m


# Toxin a second while the keeper is in the dome (0 with only a trace).
func toxin_rate() -> float:
	return GasData.dome_toxin_rate(pockets())


# 0..1: how thick the haze should be.
func haze() -> float:
	if pockets() < GasData.DOME_TRACE_POCKETS:
		return 0.0
	return clampf(pockets() / GasData.DOME_THICK_POCKETS, 0.0, 1.0)


# Is the vent worth buying right now? (The shop refuses it otherwise.)
static func has_gas() -> bool:
	var map = Level.map
	if map == null or not is_instance_valid(map):
		return false
	var f = map.get_node_or_null("StoryGasField")
	return f != null and f.dome != null and f.dome.pockets() >= GasData.DOME_TRACE_POCKETS


func vent() -> void:
	ModLoaderLog.info("Dome vented: %.1f pockets of gas" % pockets(), "flantor-StoryMode")
	amount = 0.0
	vents += 1
	GasSfx.play("vent", 0.0, 0.8)


# Vent the Dome bought by any player: upgradeAdded is the one signal the host
# gets for a client's purchase too (#228), and every client gets it as well.
func _on_upgrade_added(id: String, _team: String) -> void:
	if id.get_slice(".", id.get_slice_count(".") - 1) != VENT_ID:
		return
	if field.net_client:
		# The dome's gas is the host's: it clears it and sends the new amount.
		GasSfx.play("vent", 0.0, 0.8)
	elif amount > 0.0:
		# (The host gets the signal twice for a purchase of its own.)
		vent()


func _process(delta: float) -> void:
	if field == null or DisplayServer.get_name() == "headless":
		return
	_attach()
	var want: float = haze()
	# Builds slowly; a vent clears it in a couple of seconds.
	shown = move_toward(shown, want, delta * (0.25 if want > shown else 0.6))
	for e in _mats:
		e[0].set_shader_parameter("amount", shown * e[1])
	for s in _sprites:
		if is_instance_valid(s):
			s.visible = shown > 0.004


# The haze is drawn as copies of the dome's back wall and cellar, in their
# places, through a shader that keeps only their shape: the inside of the
# dome, whatever dome it is.
func _attach() -> void:
	var dome = Level.domesByTeamId.get("team1") if "domesByTeamId" in Level else null
	if dome == null or not is_instance_valid(dome):
		return
	if dome == _dome and not _sprites.is_empty():
		return
	for s in _sprites:
		if is_instance_valid(s):
			s.queue_free()
	_sprites.clear()
	_dome = dome
	_mats.clear()
	# Gas rises: the cellar under the dome gets less of it than the dome.
	for pair in [["Background", 1.0], ["Cellar", 0.6]]:
		var path: String = pair[0]
		var src = dome.get_node_or_null(path)
		if not src is Sprite2D or src.texture == null:
			continue
		var s := Sprite2D.new()
		s.name = "StoryGasHaze" + path
		s.texture = src.texture
		s.centered = src.centered
		s.offset = src.offset
		s.region_enabled = src.region_enabled
		s.region_rect = src.region_rect
		s.hframes = src.hframes
		s.vframes = src.vframes
		s.frame = src.frame
		s.position = src.position
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.z_as_relative = false
		s.z_index = HAZE_Z
		var mat := ShaderMaterial.new()
		mat.shader = HAZE
		s.material = mat
		_mats.append([mat, pair[1]])
		s.visible = false
		dome.add_child(s)
		_sprites.append(s)
