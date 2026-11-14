extends Node2D

# The chase (#161): Velle's body is dead, its tentacles are not. Tentacles
# tipped with eyes pour out of the wreck and follow the exact path the keeper
# takes, all the way up to the dome.
#
# The keeper leaves a trail of points; each tentacle tip travels along it.
# Speed is a share of the keeper's own top speed (so upgrades never make the
# chase safe), on a rubber band: slower than the keeper when right behind,
# faster the further back it is (data/boss.gd). A keeper flying flat out holds
# a gap of a few tiles; anything that slows the keeper (rock in the way, a
# detour, a load) closes it. A tip that touches the keeper costs a heart, and
# every tip then recoils for a moment.

const Boss = preload("res://mods-unpacked/cejdan-StoryMode/data/boss.gd")
const Pix = preload("res://mods-unpacked/cejdan-StoryMode/boss/pix.gd")
const Sfx = preload("res://mods-unpacked/cejdan-StoryMode/boss/sfx.gd")

const STEP := 6.0            # px between trail points
const BODY := 300.0          # px of tentacle drawn behind each tip
const STAGGER := 26.0        # px between one tip and the next
const TOUCH := 11.0

var health: Node = null
var trail: PackedVector2Array = PackedVector2Array()
var dist: PackedFloat32Array = PackedFloat32Array()   # path length at each trail point
var heads: Array = []        # path distance of each tip
var seeds: Array = []
var time: float = 0.0
var wait: float = Boss.CHASE_HEAD_START
var recoil: float = 0.0
var hits: int = 0
var gap: float = 0.0         # path distance from the lead tip to the keeper
var speed: float = 0.0       # the lead tip's speed right now
var keeper_speed: float = 0.0
var running: bool = true
var _rumble: float = 0.0


# Starts the chase from `origin` (this node's space): the tips set off from
# there after a head start.
func setup(p_health: Node, origin: Vector2) -> void:
	health = p_health
	z_index = 7
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	trail.append(origin)
	dist.append(0.0)
	for i in Boss.CHASE_TENTACLES:
		heads.append(-STAGGER * i)
		seeds.append(randf() * TAU)


func _kp() -> Vector2:
	var k = Keepers.first()
	return to_local(k.global_position) if k != null and is_instance_valid(k) else trail[trail.size() - 1]


func trail_length() -> float:
	return dist[dist.size() - 1]


# The point `d` px along the trail.
func point_at(d: float) -> Vector2:
	var n: int = trail.size()
	if d <= 0.0 or n == 1:
		return trail[0]
	if d >= dist[n - 1]:
		return trail[n - 1]
	var lo: int = 0
	var hi: int = n - 1
	while hi - lo > 1:
		var mid: int = (lo + hi) / 2
		if dist[mid] <= d:
			lo = mid
		else:
			hi = mid
	var seg: float = dist[hi] - dist[lo]
	return trail[lo].lerp(trail[hi], (d - dist[lo]) / seg if seg > 0.001 else 0.0)


func lead_pos() -> Vector2:
	return point_at(float(heads[0]))


func _physics_process(delta: float) -> void:
	if GameWorld.paused or not running:
		return
	time += delta
	var keeper = Keepers.first()
	if keeper == null or not is_instance_valid(keeper):
		return
	var kp: Vector2 = _kp()
	var last: Vector2 = trail[trail.size() - 1]
	if kp.distance_to(last) >= STEP:
		trail.append(kp)
		dist.append(dist[dist.size() - 1] + kp.distance_to(last))
	keeper_speed = float(keeper.currentSpeed()) if keeper.has_method("currentSpeed") else 60.0
	gap = trail_length() + kp.distance_to(trail[trail.size() - 1]) - float(heads[0])
	if wait > 0.0:
		wait -= delta
		speed = 0.0
		queue_redraw()
		return
	recoil = maxf(0.0, recoil - delta)
	var f: float = clampf((gap - Boss.CHASE_NEAR_PX) / (Boss.CHASE_FAR_PX - Boss.CHASE_NEAR_PX), 0.0, 1.0)
	speed = keeper_speed * lerpf(Boss.CHASE_SPEED_NEAR, Boss.CHASE_SPEED_FAR, f)
	if recoil > 0.0:
		speed = -keeper_speed * 0.5 if recoil > Boss.CHASE_RECOIL - 0.35 else 0.0
	var lead: float = minf(float(heads[0]) + speed * delta, trail_length())
	heads[0] = lead
	for i in range(1, heads.size()):
		# The others keep their place in the queue behind the lead.
		heads[i] = move_toward(float(heads[i]), lead - STAGGER * i, absf(speed) * delta * 1.2 + 20.0 * delta)
	# A touch.
	if recoil <= 0.0 and not keeper.isInsideDome:
		for i in heads.size():
			if float(heads[i]) > 0.0 and kp.distance_to(point_at(float(heads[i]))) < TOUCH:
				var from: Vector2 = point_at(float(heads[i]) - 12.0)
				if health != null and health.hurt(from, "chase"):
					hits += 1
					Sfx.play("whip", -4.0, 0.9)
				recoil = Boss.CHASE_RECOIL
				break
	# The ground shakes harder the closer they are.
	_rumble -= delta
	if _rumble <= 0.0 and gap < 260.0:
		_rumble = 0.35
		InputSystem.shake(2.0 + 7.0 * (1.0 - gap / 260.0), 0.3, 26.0)
		if gap < 120.0 and fposmod(time, 1.4) < 0.36:
			Sfx.play("burrow", -14.0 + 8.0 * (1.0 - gap / 120.0), 0.8)
	queue_redraw()


func _draw() -> void:
	if trail.size() < 2:
		return
	var kp: Vector2 = _kp()
	for i in range(heads.size() - 1, -1, -1):
		var h: float = float(heads[i])
		if h <= 2.0:
			continue
		var pts: PackedVector2Array = PackedVector2Array()
		var back: float = maxf(0.0, h - BODY)
		var n: int = maxi(2, int((h - back) / 4.0))
		var side: float = (float(i) - (heads.size() - 1) * 0.5) * 7.0
		for j in n + 1:
			var u: float = float(j) / float(n)
			var d: float = lerpf(back, h, u)
			var p: Vector2 = point_at(d)
			var q: Vector2 = point_at(d + 3.0)
			var dir: Vector2 = (q - p).normalized() if q.distance_to(p) > 0.01 else Vector2.UP
			# Each tentacle weaves on its own side of the trail, tight at the tip.
			var weave: float = sin(d * 0.045 - time * 3.0 + float(seeds[i])) * 5.0 + side
			pts.append(p + dir.orthogonal() * weave * (1.0 - u * 0.6))
		var tip: Vector2 = Pix.tentacle(self, pts, 8.0 if i == 0 else 6.0, 3.0, Pix.FLESH_MID if i == 0 else Pix.FLESH)
		# Eyes along the tentacle, and one at its tip.
		for j in range(n - 14, 0, -16):
			if j < pts.size():
				Pix.eye(self, pts[j], Pix.eye_frame_toward(pts[j], kp, time, j * 0.21 + i), 0.5)
		Pix.disc(self, tip, 9.0, Pix.EDGE)
		var mod: Color = Color.WHITE if recoil <= 0.0 else Color(1.6, 1.2, 1.6)
		Pix.eye(self, tip, Pix.eye_frame_toward(tip, kp, time, float(seeds[i])), 1.0, mod)
	_draw_warning(kp)


# When the lead tip is off screen, a mark at the screen edge shows where it is
# coming from, brighter as it closes in.
func _draw_warning(kp: Vector2) -> void:
	var k = Keepers.first()
	if k == null or Level.viewports == null or float(heads[0]) <= 2.0:
		return
	var cam = Level.viewports.getPlayerCam(k.playerId)
	if cam == null:
		return
	var vs: Vector2 = cam.get_viewport_rect().size / cam.zoom
	var view: Rect2 = Rect2(to_local(cam.get_screen_center_position()) - vs * 0.5, vs).grow(-10.0)
	var lead: Vector2 = lead_pos()
	if view.has_point(lead):
		return
	var p := Vector2(clampf(lead.x, view.position.x, view.end.x), clampf(lead.y, view.position.y, view.end.y))
	var near: float = clampf(1.0 - gap / 500.0, 0.2, 1.0)
	var blink: float = 0.5 + 0.5 * sin(time * (6.0 + 10.0 * near))
	Pix.disc(self, p, 7.0 + 2.0 * blink, Color(Pix.VIOLET, 0.25 + 0.4 * near))
	Pix.eye(self, p, int(time * 6.0) % 4, 0.5, Color(1, 1, 1, 0.6 + 0.4 * blink))
