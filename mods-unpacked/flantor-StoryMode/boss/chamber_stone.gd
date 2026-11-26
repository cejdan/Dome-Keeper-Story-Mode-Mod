extends Node2D

# Velle's chamber in living stone (#361): the chamber's walls and floor are
# stone with a few purple tentacles diving in and out of it, wall steps and
# stumps of the same stone stand on the floor, and stone stalactites hang from
# the roof. They give the Infiltrator and the Beastmaster something to stand
# on and climb in the fight and the chase.
#
# The walls, the floor and the roof (bar its entry tiles) are undrillable map
# tiles (map/story_gen.gd). The steps, stumps and stalactites are static bodies
# on the tile layer with no "destructable" meta, so nothing mines them. The
# look is baked by art/tools/make_chamber_art.py: a still stone image, and the
# tentacles' animation as frames of only the pixels that change. Collision
# outlines come from the same shapes (art/chamber/shapes.json).
#
# Hidden until the player has seen into the chamber, so it doesn't show through
# the dark. Every peer builds its own from the chamber's rect: nothing to sync.

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const Assets = preload("res://mods-unpacked/flantor-StoryMode/util/assets.gd")
static var _Assets = Assets  # calls go through this: lazy_preload makes const-preload calls slow

const NAME := "StoryChamberStone"
const DIR := "res://mods-unpacked/flantor-StoryMode/art/chamber/"
const SEEN_EVERY := 0.5

var chamber: Rect2i = Rect2i()
var bodies: Array = []          # StaticBody2D, one per step, stump and stalactite
var polygons: Array = []        # their outlines in this node's space (PackedVector2Array)
var seen: bool = false
var _tendrils: Sprite2D
var _stone: Sprite2D
var _frames: int = 1
var _cols: int = 1
var _fps: float = 10.0
var _size: Vector2 = Vector2.ZERO
var _t: float = 0.0
var _frame: int = -1
var _seen_acc: float = 0.0
var _probe: Array = []


static func find():
	if Level.map == null or not is_instance_valid(Level.map):
		return null
	return Level.map.get_node_or_null(NAME)


func setup(map) -> bool:
	var td = map.tileData
	if not td.has_meta("story_boss_chamber"):
		return false
	chamber = td.get_meta("story_boss_chamber")
	name = NAME
	z_index = 3          # over the tiles (1), under Velle (5) and the keepers
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Arena-local (0, 0) is the chamber's top-left corner.
	position = map.to_local(map.getTilePos(Vector2(chamber.position))) - Vector2(12, 12)
	var f := FileAccess.open(DIR + "shapes.json", FileAccess.READ)
	if f == null:
		push_error("StoryMode: missing " + DIR + "shapes.json")
		return false
	var shapes: Dictionary = JSON.parse_string(f.get_as_text())
	var origin := Vector2(shapes["origin"][0], shapes["origin"][1])
	_size = Vector2(shapes["size"][0], shapes["size"][1])
	_frames = int(shapes["frames"])
	_cols = int(shapes["cols"])
	_fps = float(shapes["fps"])
	_stone = Sprite2D.new()
	_stone.texture = _Assets.tex(DIR + "stone.png")
	_stone.centered = false
	_stone.position = origin
	add_child(_stone)
	_tendrils = Sprite2D.new()
	_tendrils.texture = _Assets.tex(DIR + "tendrils.png")
	_tendrils.centered = false
	_tendrils.position = origin
	_tendrils.region_enabled = true
	add_child(_tendrils)
	_set_frame(0)
	for b: Dictionary in shapes["bodies"]:
		var pts := PackedVector2Array()
		for p in b["points"]:
			pts.append(Vector2(p[0], p[1]))
		var body := StaticBody2D.new()
		body.name = String(b["name"])
		body.collision_layer = 1
		body.collision_mask = 0
		var poly := CollisionPolygon2D.new()
		poly.polygon = pts
		body.add_child(poly)
		add_child(body)
		bodies.append(body)
		polygons.append(pts)
	# Seen once any cell of the chamber's inside is in sight.
	for y in range(chamber.position.y, chamber.end.y):
		for x in range(chamber.position.x, chamber.end.x):
			_probe.append(Vector2(x, y))
	visible = false
	_check_seen()
	return true


# Is `global_pos` inside a step, stump or stalactite?
func is_solid(global_pos: Vector2) -> bool:
	var p: Vector2 = to_local(global_pos)
	for poly: PackedVector2Array in polygons:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false


func _set_frame(i: int) -> void:
	if i == _frame:
		return
	_frame = i
	_tendrils.region_rect = Rect2(Vector2(i % _cols, i / _cols) * _size, _size)


func _check_seen() -> void:
	var vis: Dictionary = Level.map.visibleTileCoords
	for c in _probe:
		if vis.has(c):
			seen = true
			visible = true
			return


func _process(delta: float) -> void:
	if not seen:
		_seen_acc += delta
		if _seen_acc >= SEEN_EVERY:
			_seen_acc = 0.0
			_check_seen()
		return
	if GameWorld.paused:
		return
	_t += delta
	_set_frame(int(_t * _fps) % _frames)
