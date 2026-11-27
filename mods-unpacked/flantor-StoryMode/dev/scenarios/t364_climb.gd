extends "res://mods-unpacked/flantor-StoryMode/dev/scenario.gd"

# #364: every keeper on the lava ocean's real tentacles (a generated map), the
# Engineer by default; `-Extra "--keeper=keeper2"` (keeper3, keeper4) for the
# others (the Beastmaster only through this dev harness: no DLC here).
# Boots the dev ocean mode (`--tentacles=ocean`: boss gear, waves off, the
# ocean round the tentacles revealed). Suit heat is reset as it goes: the
# checks are about the climb; how long each spent in lava is noted.
#   all:      the keeper never ends up inside rock while beside a tentacle
#             swinging at 10 chains (the swing never pushes it into a wall);
#   keeper1/2 (they fly): up from the ocean floor beside a tentacle to its tip
#             and over the pad, at 0 and at 10 chains;
#   keeper3:  stands on a vertical tip at every wake (0, 3, 5, 8, 10 chains
#             broken); climbs a tentacle from low down with the hook (throw
#             at a segment above, get pulled up, chain-jump, again) onto the
#             pad, at 0 and at 5 chains;
#   keeper4:  climbs from low down to the tip with its claws (holding up), at
#             0 and at 10 chains; its claws hold their spot on the segments
#             and it rides along at 10.
# Bursts of each for the look.

const Ocean = preload("res://mods-unpacked/flantor-StoryMode/map/ocean_tentacles.gd")
static var _Ocean = Ocean  # calls go through this: lazy_preload makes const-preload calls slow
const Story = preload("res://mods-unpacked/flantor-StoryMode/story.gd")
static var _Story = Story  # calls go through this: lazy_preload makes const-preload calls slow
const TIMEOUT := 420
const T := 24.0

var tents
var lava
var _lava_frames: int = 0


func boot() -> Dictionary:
	return {"seed": 12345, "tentacles": "ocean", "keeper": "keeper1"}


func run(h) -> void:
	var kid: String = _Story.user_arg("keeper", "keeper1")
	var ok: bool = await h.until(func(): return _Ocean.find() != null and h.keeper() != null, 30.0)
	if not h.check("the ocean tentacles are there", ok):
		return
	tents = _Ocean.find()
	lava = Level.map.get_node_or_null("StoryLavaField")
	await h.wait(2.0)
	var k = h.keeper()
	h.check("the keeper is the %s" % kid, k.techId == kid, k.techId)
	h.check("the dev ocean mode put it on the left tip", k.global_position.distance_to(tents.rigs[0].pad_top()) < 60.0, k.global_position.distance_to(tents.rigs[0].pad_top()))
	await h.shot("on_tip_%s" % kid)
	match kid:
		"keeper1", "keeper2":
			await _fly(h, k)
		"keeper3":
			await _infiltrator(h, k)
		"keeper4":
			await _beastmaster(h, k)
	await _no_rock_push(h, k)


func _cool(k) -> void:
	if lava != null:
		lava.set_heat_of(k, 0.0)


func _set_chains(n: int) -> void:
	_Ocean.set_chains_broken(n)
	for r in tents.rigs:
		r.target_share = _Ocean.share_for(_Ocean.wake_for(n))
		r.target_speed = _Ocean.speed_for(_Ocean.wake_for(n))
		r.snap_to_target()


func _put(h, k, at: Vector2) -> void:
	k.teleport(at)
	tents.refresh_near()
	if "velocity" in k:
		k.velocity = Vector2.ZERO
	h.snap_camera(k)
	await h.get_tree().physics_frame
	await h.get_tree().physics_frame


# Beside rig `r` low down: `seg` segments up, on the side facing the ocean's middle.
func _beside(r, seg: int, gap: float) -> Vector2:
	var s = r.segments[seg]
	var side: float = 1.0 if r.base.x < 0.0 else -1.0
	# By the rig's clock: it may not have posed yet (nobody near).
	var at: Vector2 = r.transforms_at(r.t, r.share)[seg].origin
	return at + Vector2(side * (s.width * 0.5 + gap), 0.0)


# Is the keeper on rig `r`'s pad (over its top, within its width)?
func _on_pad(k, r) -> bool:
	var p: Vector2 = r.pad.global_transform.affine_inverse() * k.global_position
	# Pad space: +x out of the tentacle (up), the top face at x = height.
	return p.x > r.pad_height - 4.0 and p.x < r.pad_height + 30.0 and absf(p.y) < r.pad_width * 0.5 + 6.0


func _track_lava(k) -> void:
	if lava != null and lava.keeper_in_lava(k):
		_lava_frames += 1


# ---------------------------------------------------------------- flyers

func _fly(h, k) -> void:
	for n in [0, 10]:
		_set_chains(n)
		await h.wait(1.0)
		var r = tents.rigs[0]
		await _put(h, k, _beside(r, 1, 34.0))
		_cool(k)
		var y0: float = k.global_position.y
		var top: float = r.pad_top().y
		_lava_frames = 0
		h.down("ui_up")
		var reached: bool = false
		var frames: int = 0
		while frames < 60 * 20:
			await h.get_tree().physics_frame
			frames += 1
			_track_lava(k)
			if frames % 30 == 0:
				_cool(k)
			# Steer to keep beside the tentacle at this height.
			if k.global_position.y < top - 30.0:
				reached = true
				break
		h.up("ui_up")
		h.note("%s at %d chains: flew up %.0f px in %.1f s (%.1f s in lava)" % [k.techId, n, y0 - k.global_position.y, frames / 60.0, _lava_frames / 60.0])
		h.check("%d chains: flies from the ocean floor up past the tip" % n, reached, {"from": y0, "at": k.global_position.y, "pad top": top})
		# Over the pad and let go.
		var px: float = r.pad_top().x
		var dir: String = "ui_right" if px > k.global_position.x else "ui_left"
		h.down(dir)
		var t: int = 0
		while absf(r.pad_top().x - k.global_position.x) > 8.0 and t < 120:
			await h.get_tree().physics_frame
			t += 1
		h.up(dir)
		await h.wait(1.0)
		await h.shot("%s_over_pad_%d" % [k.techId, n])
		_cool(k)


# ---------------------------------------------------------------- Infiltrator

func _infiltrator(h, k) -> void:
	# Standing on a vertical tip at every wake (`--only=hook` skips it).
	for n in ([] if _Story.user_arg("only", "").begins_with("hook") else [0, 3, 5, 8, 10]):
		_set_chains(n)
		for ri in tents.rigs.size():
			var r = tents.rigs[ri]
			await _put(h, k, r.pad_top_now() + Vector2(0, -12))
			# Land: the pad moves, so put it back on until it stands.
			for f in 30:
				if k.is_on_floor() and _on_pad(k, r):
					break
				k.teleport(r.pad_top_now() + Vector2(0, -12))
				await h.get_tree().physics_frame
			var on: int = 0
			var frames: int = 0
			var tilt: float = 0.0
			while frames < 60 * 6:
				await h.get_tree().physics_frame
				frames += 1
				if _on_pad(k, r):
					on += 1
				tilt = maxf(tilt, rad_to_deg(r.pad_tilt()))
			_cool(k)
			h.note("keeper3 on tip %d at %d chains: %d/%d frames on the pad, pad tilt up to %.1f deg" % [ri, n, on, frames, tilt])
			h.check("%d chains: the Infiltrator stands on tip %d (most of 6 s)" % [n, ri], on > frames * 0.9, [on, frames])
		if n == 0 or n == 10:
			await h.burst("keeper3_tip_%d" % n, 10, 6)
	# Climbing with the hook.
	for n in ([0] if _Story.user_arg("only", "") == "hook0" else [0, 5]):
		_set_chains(n)
		await h.wait(0.5)
		var res: Dictionary = await _hook_climb(h, k, tents.rigs[0])
		h.note("keeper3 hook climb at %d chains" % n, res)
		h.check("%d chains: the Infiltrator climbs from low down onto the pad with the hook" % n, res["on_pad"], res)
		await h.shot("keeper3_climbed_%d" % n)


# Scripted player: jump (or chain-jump) away from the tentacle, throw the
# hook at a segment 4-6 tiles above, hold up while the rope pulls it in and
# it climbs, again; once the pad is in reach, hook the pad, chain-jump toward
# it and steer onto its top.
func _hook_climb(h, k, r) -> Dictionary:
	await _put(h, k, _beside(r, 1, 44.0))
	await h.wait(0.8)
	var start_y: float = k.global_position.y
	var best_y: float = start_y
	var throws: int = 0
	var hits: int = 0
	_lava_frames = 0
	var t0: float = h.now()
	var on_pad: bool = false
	var steps: Array = []   # per loop: keeper - pad top (x, y), hanging, on floor
	while h.now() - t0 < 50.0 and throws < 30:
		_cool(k)
		if _on_pad(k, r) and k.is_on_floor():
			on_pad = true
			break
		var cx: float = _centre_x(r, k.global_position.y)
		var away: String = "ui_right" if k.global_position.x > cx else "ui_left"
		var toward: String = "ui_left" if away == "ui_right" else "ui_right"
		var pad_near: bool = k.global_position.y - r.pad_top().y < 150.0
		steps.append([int(k.global_position.x - r.pad_top().x), int(k.global_position.y - r.pad_top().y), int(k.chainHanging), int(k.is_on_floor())])
		# Hanging just under the pad: out from under its rim with a chain
		# jump, a second jump in the air back toward it, and steer onto it.
		if k.chainHanging and k.global_position.y - r.pad_top().y < 70.0:
			h.down(away)
			await _frames(h, k, 3)
			k.justPressedUp = true
			k.pressingUp = true
			await _frames(h, k, 8)
			k.pressingUp = false
			h.up(away)
			h.down(toward)
			await _frames(h, k, 4)
			k.justPressedUp = true
			k.pressingUp = true
			for f in 60:
				await _frames(h, k, 1)
				if f == 12:
					k.pressingUp = false
				best_y = minf(best_y, k.global_position.y)
				var dx: float = r.pad_top().x - k.global_position.x
				if absf(dx) < 6.0:
					h.up(toward)
				if k.is_on_floor():
					break
			h.up(toward)
			k.pressingUp = false
			await _frames(h, k, 20)
			continue
		# 1. Up and a little out (facing decides a chain jump's side).
		var jdir: String = away
		var y_before: float = k.global_position.y
		h.down(jdir)
		await _frames(h, k, 3)
		# The jump as Keeper3InputProcessor hands it on (the harness's key
		# events for keeper3_jump don't reach it in a background window).
		k.justPressedUp = true
		k.pressingUp = true
		await _frames(h, k, 10)
		k.pressingUp = false
		await _frames(h, k, 6)
		h.up(jdir)
		if throws <= 3:
			h.note("jump before throw %d: y %d -> %d, hanging %s" % [throws + 1, int(y_before), int(k.global_position.y), k.chainHanging])
		best_y = minf(best_y, k.global_position.y)
		if _on_pad(k, r) and k.is_on_floor():
			on_pad = true
			break
		# Over the pad: steer onto it and let it land.
		if k.global_position.y < r.pad_top().y - 4.0:
			var steer: String = "ui_right" if r.pad_top().x > k.global_position.x else "ui_left"
			h.down(steer)
			for f in 45:
				await _frames(h, k, 1)
				if absf(r.pad_top().x - k.global_position.x) < 8.0:
					break
			h.up(steer)
			await _frames(h, k, 30)
			continue
		# 2. The hook: at a segment 4-6 tiles up, or the pad once in reach.
		var target = r.pad
		if not pad_near:
			for sg in r.segments:
				var dy: float = k.global_position.y - sg.global_position.y
				if dy > 96.0 and dy < 150.0:
					target = sg
					break
		var side: float = signf(k.global_position.x - target.global_position.x)
		var aim_at: Vector2 = target.global_position + Vector2(side * 6.0, 0.0)
		if is_instance_valid(k.hook):
			k.releaseHookInput()
			await _frames(h, k, 2)
		k.networkThrowHook((aim_at - k.global_position).normalized(), k.global_position)
		throws += 1
		var hit: bool = await h.until(func(): return k.hook != null and is_instance_valid(k.hook) and k.hook.has_hit, 0.8)
		var on_it: bool = hit and is_instance_valid(k.hook) and (k.hook.attached_target in r.bodies())
		if on_it:
			hits += 1
		if throws <= 6:
			h.note("throw %d" % throws, {"keeper": k.global_position, "aim at": aim_at, "target": String(target.name), "hit": hit, "on the tentacle": on_it})
		# 3. Pulled in; climb the rope.
		h.down("ui_up")
		var trace: Array = []
		for f in 45:
			await _frames(h, k, 1)
			best_y = minf(best_y, k.global_position.y)
			if throws <= 3 and f % 5 == 0:
				trace.append([int(k.global_position.y), int(k.chainActive), int(k.chainPulling), int(k.chainHanging), int(k.hookState)])
		h.up("ui_up")
		if throws <= 3:
			h.note("rope %d [y, active, pulling, hanging, hook state]" % throws, trace)
	if is_instance_valid(k.hook):
		k.releaseHookInput()
	await h.wait(1.0)
	on_pad = on_pad or (_on_pad(k, r) and k.is_on_floor())
	h.note("climb steps [dx, dy to the pad top, hanging, on floor]", steps)
	return {"on_pad": on_pad, "throws": throws, "hits on the tentacle": hits, "rose px": snappedf(start_y - best_y, 1.0), "seconds": snappedf(h.now() - t0, 0.1), "in lava s": snappedf(_lava_frames / 60.0, 0.1)}


func _frames(h, k, n: int) -> void:
	for i in n:
		await h.get_tree().physics_frame
		_track_lava(k)


# The tentacle's middle at height `y` (its nearest segment's).
func _centre_x(r, y: float) -> float:
	var best = r.segments[0]
	for sg in r.segments:
		if absf(sg.global_position.y - y) < absf(best.global_position.y - y):
			best = sg
	return best.global_position.x


# ---------------------------------------------------------------- Beastmaster

func _claws_on(k, r) -> int:
	var bodies: Array = r.bodies()
	var n: int = 0
	for t in k.get_node("Tentacles").tentacles:
		if t.is_grounded() and is_instance_valid(t.attachedTile) and t.attachedTile in bodies:
			n += 1
	return n


# How far (px) the farthest planted claw on rig `r` is outside its body's
# outline: 0 when every claw is on its body. (The mid-air grabs: a claw
# landing where the segment had been when its ray hit it.)
func _claw_in_air(k, r) -> float:
	var worst: float = 0.0
	var bodies: Array = r.bodies()
	for t in k.get_node("Tentacles").tentacles:
		if not t.is_grounded() or not is_instance_valid(t.attachedTile) or not (t.attachedTile in bodies):
			continue
		var b = t.attachedTile
		var p: Vector2 = b.global_transform.affine_inverse() * t.attachmentPoint
		var out: float = 0.0
		if "length" in b:
			var hl: float = b.length * 0.5
			var u: float = clampf((p.x + hl) / b.length, 0.0, 1.0)
			var hw: float = lerpf(b.w_root, b.w_tip, u) * 0.5
			# The tapered piece, or the knuckle round its lower joint.
			var piece: float = maxf(absf(p.y) - hw, maxf(absf(p.x) - hl, 0.0))
			var knuckle: float = p.distance_to(Vector2(-hl, 0.0)) - b.w_root * 0.5
			out = maxf(0.0, minf(piece, knuckle))
		else:
			out = 0.0 if Geometry2D.is_point_in_polygon(p, b.outline(-3.0)) else 3.0
		worst = maxf(worst, out)
	return worst


func _beastmaster(h, k) -> void:
	for n in [0, 10]:
		_set_chains(n)
		await h.wait(0.5)
		var r = tents.rigs[1]
		await _put(h, k, _beside(r, 2, 16.0))
		_cool(k)
		var y0: float = k.global_position.y
		var top: float = r.pad_top().y
		_lava_frames = 0
		var reached: bool = false
		var frames: int = 0
		var gripped: int = 0
		var worst_air: float = 0.0
		h.down("ui_up")
		while frames < 60 * 25:
			await h.get_tree().physics_frame
			frames += 1
			_track_lava(k)
			if frames % 30 == 0:
				_cool(k)
			if _claws_on(k, r) > 0:
				gripped += 1
			worst_air = maxf(worst_air, _claw_in_air(k, r))
			if k.global_position.y < top + 6.0:
				reached = true
				break
		h.up("ui_up")
		h.note("keeper4 at %d chains: climbed %.0f px in %.1f s, claws on the tentacle %d frames, %.1f s in lava" % [n, y0 - k.global_position.y, frames / 60.0, gripped, _lava_frames / 60.0])
		h.check("%d chains: the Beastmaster climbs from low down to the tip with its claws" % n, reached, {"from": y0, "at": k.global_position.y, "pad top": top})
		h.check("%d chains: ... holding the tentacle on the way (claws on it most of the climb)" % n, gripped > frames / 2, [gripped, frames])
		h.check("%d chains: no claw holds the air (every planted claw within 3 px of its body's outline)" % n, worst_air < 3.0, worst_air)
		await h.burst("keeper4_top_%d" % n, 8, 6)
		# Hang on near the top: claws keep their spot and the body rides along.
		var drift: float = 0.0
		var samples: int = 0
		var last: Dictionary = {}
		var kmin := Vector2(INF, INF)
		var kmax := Vector2(-INF, -INF)
		for f in 180:
			await h.get_tree().physics_frame
			var p: Vector2 = k.global_position
			kmin = Vector2(minf(kmin.x, p.x), minf(kmin.y, p.y))
			kmax = Vector2(maxf(kmax.x, p.x), maxf(kmax.y, p.y))
			for t in k.get_node("Tentacles").tentacles:
				if not t.is_grounded() or not is_instance_valid(t.attachedTile) or not (t.attachedTile in r.bodies()):
					last.erase(t)
					continue
				var local: Vector2 = t.attachedTile.global_transform.affine_inverse() * t.attachmentPoint
				if last.has(t) and last[t].b == t.attachedTile:
					var d: float = (local - last[t].l).length()
					if d <= 4.0:
						drift = maxf(drift, d)
						samples += 1
				last[t] = {"b": t.attachedTile, "l": local}
		_cool(k)
		h.note("keeper4 hanging at %d chains: %d claw-frames, max drift %.2f px, keeper moved %s" % [n, samples, drift, str(kmax - kmin)])
		h.check("%d chains: claws hold their spot on the tentacle (drift under 0.5 px)" % n, samples > 30 and drift < 0.5, [samples, drift])
		if n == 10:
			h.check("10 chains: the Beastmaster rides along (moves over 4 px)", (kmax - kmin).length() > 4.0, kmax - kmin)


# ---------------------------------------------------------------- all keepers

# Beside each tentacle at 10 chains, low and high, no input: the swing may
# shove the keeper, never into rock.
func _no_rock_push(h, k) -> void:
	_set_chains(10)
	var inside: Array = []
	for r in tents.rigs:
		for seg in [3, r.count / 2, r.count - 3]:
			await _put(h, k, _beside(r, seg, 10.0))
			for f in 150:
				await h.get_tree().physics_frame
				var c: Vector2i = Vector2i(Level.map.getTileCoord(k.global_position))
				if not Level.map.is_tile_empty(c) and Level.map.tileData.get_resourcev(c) != Data.TILE_EMPTY:
					inside.append([r.name, seg, c])
					break
			_cool(k)
	h.check("beside a tentacle swinging at 10 chains, the keeper never ends up inside rock", inside.is_empty(), inside)
