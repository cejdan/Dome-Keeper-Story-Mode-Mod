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
#
# With a team (#230) the tentacles hunt one keeper at a time, the `target`:
# the trail is that keeper's path. They turn on another keeper still out in
# the mine when it is clearly nearer the lead tip (or the target got home):
# the trail is cut at the lead tip and runs straight on to the new target, so
# the tentacles burrow through the rock towards it. A tip that touches any
# keeper out of the dome costs the team a heart. Online the host runs the
# chase; a client's copy is a `puppet` that draws the host's trail and tips
# (net_state() -> net_apply(), sent by the director).

const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
const Boss = preload("res://mods-unpacked/flantor-StoryMode/data/boss.gd")
const Pix = preload("res://mods-unpacked/flantor-StoryMode/boss/pix.gd")
const Sfx = preload("res://mods-unpacked/flantor-StoryMode/boss/sfx.gd")

const STEP := 6.0            # px between trail points
const BODY := 300.0          # px of tentacle drawn behind each tip
const STAGGER := 26.0        # px between one tip and the next
const TOUCH := 11.0
const SWITCH_MARGIN := 90.0  # px nearer the lead tip another keeper must be to be hunted instead
const SWITCH_REST := 2.0     # seconds before the tentacles turn again

var health: Node = null
var trail: PackedVector2Array = PackedVector2Array()
var dist: PackedFloat32Array = PackedFloat32Array()   # path length at each trail point
var heads: Array = []        # path distance of each tip
var seeds: Array = []
var time: float = 0.0
var wait: float = Boss.CHASE_HEAD_START
var recoil: float = 0.0
var hits: int = 0
var gap: float = 0.0         # path distance from the lead tip to the target
var speed: float = 0.0       # the lead tip's speed right now
var keeper_speed: float = 0.0
var running: bool = true
var target = null            # the keeper being hunted
var turns: int = 0           # times the tentacles turned on another keeper
var _rumble: float = 0.0
var _switch_t: float = 0.0

# Online (#230).
var puppet: bool = false     # a client's copy: draws what the host sends
var _sent: int = 0           # host: trail points already sent to clients
var _net_heads: Array = []
var _net_age: float = 0.0
var _net_time: float = -1.0


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
	_net_heads = heads.duplicate()


func _ok(k) -> bool:
	return k != null and is_instance_valid(k)


# Is keeper `k` in the dome? A teammate's keeper moves on its own instance:
# here, its place says.
static func in_dome(k) -> bool:
	return k.isInsideDome if Keepers.local.has(k) else k.getIsInsideDome()


# The keepers the tentacles can hunt: out in the mine.
func _out() -> Array:
	var out: Array = []
	for k in Keepers.getAll():
		if _ok(k) and not in_dome(k):
			out.append(k)
	return out


func _kp() -> Vector2:
	var k = target if _ok(target) else Story.local_keeper()
	return to_local(k.global_position) if k != null and is_instance_valid(k) else trail[trail.size() - 1]


# How close the tentacles are to this instance's own keeper: the path gap for
# the hunted keeper, the straight distance to the lead tip for anyone else.
func my_gap() -> float:
	return gap_for(Story.local_keeper())


# The same for keeper `me` (each local keeper's own in splitscreen, #263).
func gap_for(me) -> float:
	if me == null or not is_instance_valid(me) or me == target:
		return gap
	if float(heads[0]) <= 2.0:
		return maxf(gap, to_local(me.global_position).distance_to(lead_pos()))
	return to_local(me.global_position).distance_to(lead_pos())


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


# Who to hunt: the target while it is out, unless another keeper out is
# clearly nearer the lead tip; the keeper out nearest the lead tip otherwise.
# With nobody out, the last target.
func _choose_target(delta: float) -> void:
	_switch_t = maxf(0.0, _switch_t - delta)
	var out: Array = _out()
	var lead: Vector2 = lead_pos()
	var best = null
	var best_d: float = INF
	for k in out:
		var d: float = lead.distance_to(to_local(k.global_position))
		if d < best_d:
			best = k
			best_d = d
	if not _ok(target):
		target = best if best != null else Story.local_keeper()
		return
	if best == null or best == target or _switch_t > 0.0:
		return
	if not out.has(target) or best_d + SWITCH_MARGIN < lead.distance_to(to_local(target.global_position)):
		_retarget(best)


# The tentacles turn on `k`: the trail ends at the lead tip and goes on
# straight to `k` from there.
func _retarget(k) -> void:
	target = k
	turns += 1
	_switch_t = SWITCH_REST
	var lead_d: float = clampf(float(heads[0]), 0.0, trail_length())
	var p: Vector2 = point_at(lead_d)
	var keep: int = 1
	while keep < dist.size() and dist[keep] <= lead_d:
		keep += 1
	trail.resize(keep)
	dist.resize(keep)
	if p.distance_to(trail[keep - 1]) > 0.01:
		trail.append(p)
		dist.append(dist[keep - 1] + p.distance_to(trail[keep - 1]))
	_sent = mini(_sent, keep)
	ModLoaderLog.info("Chase: the tentacles turn on %s" % str(k.playerId), "flantor-StoryMode")


func _physics_process(delta: float) -> void:
	if GameWorld.paused or not running:
		return
	time += delta
	if puppet:
		_puppet_step(delta)
		return
	_choose_target(delta)
	var keeper = target
	if not _ok(keeper):
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
	# A touch, on any keeper out of the dome.
	if recoil <= 0.0:
		_touch()
	_feel(delta)
	queue_redraw()


func _touch() -> void:
	for k in _out():
		var p: Vector2 = to_local(k.global_position)
		for i in heads.size():
			if float(heads[i]) > 0.0 and p.distance_to(point_at(float(heads[i]))) < TOUCH:
				var from: Vector2 = point_at(float(heads[i]) - 12.0)
				if health != null and health.hurt(from, "chase", k):
					hits += 1
					Sfx.play("whip", -4.0, 0.9)
				recoil = Boss.CHASE_RECOIL
				return


# The ground shakes harder the closer they are to this instance's keeper.
func _feel(delta: float) -> void:
	var g: float = my_gap()
	_rumble -= delta
	if _rumble <= 0.0 and wait <= 0.0 and g < 260.0:
		_rumble = 0.35
		InputSystem.shake(2.0 + 7.0 * (1.0 - g / 260.0), 0.3, 26.0)
		if g < 120.0 and fposmod(time, 1.4) < 0.36:
			Sfx.play("burrow", -14.0 + 8.0 * (1.0 - g / 120.0), 0.8)


# ---------------------------------------------------------------- online (#230)

# The host's chase for clients: the clocks, the tips, the target, and the
# trail points they have not had yet (from `base`). Sent reliably, in order.
func net_state() -> Array:
	var pts: PackedVector2Array = trail.slice(_sent)
	var base: int = _sent
	_sent = trail.size()
	var who: String = str(target.playerId) if _ok(target) else ""
	return [time, wait, recoil, gap, speed, keeper_speed, hits, PackedFloat32Array(heads), base, pts, who, running]


# Sends the whole trail again with the next state (a client that is new or
# missed some of it).
func resend() -> void:
	_sent = 0


# A puppet takes the host's chase. False when the trail part does not fit on
# what this copy has (it missed some): the director asks for all of it again.
func net_apply(d: Array) -> bool:
	if not puppet or d.size() < 12:
		return true
	var base: int = int(d[8])
	if base > trail.size():
		return false
	var pts: PackedVector2Array = d[9]
	trail.resize(base)
	dist.resize(base)
	for p: Vector2 in pts:
		if trail.is_empty():
			dist.append(0.0)
		else:
			dist.append(dist[dist.size() - 1] + p.distance_to(trail[trail.size() - 1]))
		trail.append(p)
	if trail.is_empty():
		trail.append(Vector2.ZERO)
		dist.append(0.0)
	if float(d[0]) >= _net_time:
		_net_time = float(d[0])
		time = float(d[0])
		wait = float(d[1])
		recoil = float(d[2])
		gap = float(d[3])
		speed = float(d[4])
		keeper_speed = float(d[5])
		if int(d[6]) > hits:
			Sfx.play("whip", -4.0, 0.9)
		hits = int(d[6])
		var hs: PackedFloat32Array = d[7]
		_net_heads = Array(hs)
		if heads.size() != _net_heads.size():
			heads = _net_heads.duplicate()
		_net_age = 0.0
		var who: String = str(d[10])
		target = Keepers.getKeeper(who) if who != "" and Keepers.hasKeeper(who) else null
		running = bool(d[11])
	return true


# A puppet's frame: the tips glide on from the host's last word at its speed.
func _puppet_step(delta: float) -> void:
	_net_age = minf(_net_age + delta, 0.25)
	var tl: float = trail_length()
	for i in heads.size():
		var want: float = minf(float(_net_heads[i]) + (speed * _net_age if wait <= 0.0 else 0.0), tl)
		var h: float = float(heads[i])
		heads[i] = want if absf(want - h) > 40.0 else lerpf(h, want, minf(1.0, delta * 14.0))
	_feel(delta)
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
	_draw_warning()


# When the lead tip is off screen, a mark at the screen edge shows where it is
# coming from, brighter as it closes in. In splitscreen (#263) each local
# keeper gets its own mark at its own view's edge, drawn in its view only: a
# child node shown just there (Level.viewports.showForLocalKeeper, as the hit
# flash in keeper_health.gd); this node itself shows in every view.
var _marks: Dictionary = {}   # playerId -> Node2D, with 2+ local keepers


func _draw_warning() -> void:
	var locals: Array = Story.local_keepers()
	if locals.size() <= 1 or Level.viewports == null:
		_draw_warning_on(self, Story.local_keeper())
		return
	for k in locals:
		var m: Node2D = _mark_for(k)
		if m != null:
			m.queue_redraw()


func _mark_for(k) -> Node2D:
	if not _ok(k):
		return null
	if _marks.has(k.playerId) and is_instance_valid(_marks[k.playerId]):
		return _marks[k.playerId]
	var m := Node2D.new()
	m.name = "EdgeMark_" + str(k.playerId)
	m.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(m)
	m.visibility_layer = 0
	Level.viewports.showForLocalKeeper(k, m)
	m.draw.connect(func(): _draw_warning_on(m, k))
	_marks[k.playerId] = m
	return m


# The mark for keeper `k`'s view, drawn on `ci` (this node or a child at its
# origin, so both share its space).
func _draw_warning_on(ci: CanvasItem, k) -> void:
	if not _ok(k) or float(heads[0]) <= 2.0:
		return
	var r: Rect2 = Story.view_rect(k.playerId, -10.0)
	if not r.has_area():
		return
	var view := Rect2(to_local(r.position), r.size)
	var lead: Vector2 = lead_pos()
	if view.has_point(lead):
		return
	var p := Vector2(clampf(lead.x, view.position.x, view.end.x), clampf(lead.y, view.position.y, view.end.y))
	var near: float = clampf(1.0 - gap_for(k) / 500.0, 0.2, 1.0)
	var blink: float = 0.5 + 0.5 * sin(time * (6.0 + 10.0 * near))
	Pix.disc(ci, p, 7.0 + 2.0 * blink, Color(Pix.VIOLET, 0.25 + 0.4 * near))
	Pix.eye(ci, p, int(time * 6.0) % 4, 0.5, Color(1, 1, 1, 0.6 + 0.4 * blink))
