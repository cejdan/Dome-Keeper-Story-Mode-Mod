extends Node2D

# The rising lava reaches the surface (#369, Storymode.too_late("surface")):
# the ground round the dome splits and glows from below, lava bursts up out of
# the cracks in spurts, embers rise and the light floods out over the ground.
# Look only (no collision, nothing saved); every peer plays its own copy. It
# grows over GROW_S and stays until the run's end screen.

const GROW_S := 3.0
const HALF_W := 760.0            # px either side of the dome
const COL_HOT := Color("ffd23e")
const COL_LAVA := Color("ff8a1c")
const COL_DEEP := Color("e8430e")

var ground_y: float = 0.0
var centre_x: float = 0.0
var t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _cracks: Array = []          # [PackedVector2Array, delay]
var _spurts: Array = []          # [x, start, height, width]
var _embers: Array = []          # [pos, vel, life, max]
var _glow: Node2D


func setup(dome_pos: Vector2, ground: float) -> void:
	name = "StoryTooLateSurface"
	z_as_relative = false
	z_index = 45
	centre_x = dome_pos.x
	ground_y = ground
	_rng.seed = hash([Level.levelSeed, "too_late"])
	for i in 14:
		var dir: float = -1.0 if i % 2 == 0 else 1.0
		var p := Vector2(centre_x + dir * _rng.randf_range(115.0, 160.0), ground_y + _rng.randf_range(-2.0, 6.0))
		var pts := PackedVector2Array([p])
		var n: int = _rng.randi_range(5, 11)
		for j in n:
			p += Vector2(dir * _rng.randf_range(24.0, 70.0), _rng.randf_range(-6.0, 10.0))
			pts.append(p)
		_cracks.append([pts, _rng.randf_range(0.0, 1.4)])
	for i in 9:
		_spurts.append([centre_x + (1.0 if i % 2 == 0 else -1.0) * _rng.randf_range(140.0, HALF_W * 0.85), _rng.randf_range(0.2, 1.6), _rng.randf_range(90.0, 240.0), _rng.randf_range(10.0, 20.0)])
	_glow = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	_glow.draw.connect(_draw_glow)
	add_child(_glow)


func _process(delta: float) -> void:
	t += delta
	var grow: float = clampf(t / GROW_S, 0.0, 1.0)
	if _embers.size() < 160:
		for i in int(40.0 * grow * delta * 10.0) + 1:
			var x: float = centre_x + _rng.randf_range(-HALF_W, HALF_W) * grow
			_embers.append([Vector2(x, ground_y + _rng.randf_range(-4.0, 8.0)), Vector2(_rng.randf_range(-12.0, 12.0), _rng.randf_range(-90.0, -30.0)), 0.0, _rng.randf_range(0.8, 2.0)])
	for e in _embers:
		e[2] += delta
		e[0] += e[1] * delta
		e[1].y += 14.0 * delta
	_embers = _embers.filter(func(e): return e[2] < e[3])
	queue_redraw()
	_glow.queue_redraw()


func _draw() -> void:
	var grow: float = clampf(t / GROW_S, 0.0, 1.0)
	for c in _cracks:
		var share: float = clampf((t - float(c[1])) / 1.6, 0.0, 1.0)
		var pts: PackedVector2Array = c[0]
		var n: int = int(ceil(share * float(pts.size() - 1)))
		if n < 1:
			continue
		var line := PackedVector2Array()
		for i in n + 1:
			line.append(to_local(pts[i]))
		draw_polyline(line, COL_DEEP, 4.0)
		draw_polyline(line, COL_HOT.lerp(COL_LAVA, 0.5 + 0.5 * sin(t * 9.0 + float(n))), 2.0)
	for s in _spurts:
		var u: float = t - float(s[1])
		if u < 0.0:
			continue
		var phase: float = fposmod(u, 2.2) / 2.2
		var hgt: float = float(s[2]) * sin(phase * PI) * grow
		if hgt < 2.0:
			continue
		var base := to_local(Vector2(float(s[0]), ground_y + 4.0))
		var w: float = float(s[3])
		draw_rect(Rect2(base + Vector2(-w * 0.5, -hgt), Vector2(w, hgt)), COL_DEEP)
		draw_rect(Rect2(base + Vector2(-w * 0.3, -hgt), Vector2(w * 0.6, hgt)), COL_LAVA)
		draw_rect(Rect2(base + Vector2(-w * 0.12, -hgt + 2.0), Vector2(w * 0.24, hgt - 2.0)), COL_HOT)
		draw_circle(base + Vector2(0, -hgt), w * 0.55, COL_LAVA)
	for e in _embers:
		var a: float = 1.0 - float(e[2]) / float(e[3])
		draw_rect(Rect2(to_local(e[0]).round(), Vector2(2, 2)), Color(COL_HOT, a))


# The light flooding out from under the ground.
func _draw_glow() -> void:
	var grow: float = clampf(t / GROW_S, 0.0, 1.0)
	var steps := 24
	for i in steps:
		var u: float = (float(i) + 0.5) / float(steps) * 2.0 - 1.0
		var reach: float = clampf(grow * 1.3 - absf(u), 0.0, 1.0)
		if reach <= 0.0:
			continue
		var x: float = centre_x + u * HALF_W
		var flick: float = 0.8 + 0.2 * sin(t * 7.0 + float(i) * 1.7)
		var hgt: float = 90.0 + 60.0 * reach
		var p := to_local(Vector2(x - HALF_W / float(steps), ground_y - hgt))
		for k in 4:
			var f: float = float(k) / 4.0
			_glow.draw_rect(Rect2(p + Vector2(0, hgt * f), Vector2(HALF_W * 2.0 / float(steps) + 1.0, hgt / 4.0 + 1.0)), Color(COL_LAVA, 0.14 * (0.3 + f) * reach * flick))
