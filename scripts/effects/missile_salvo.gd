class_name MissileSalvo
extends RefCounted

# Reusable missile-salvo attack — telegraph circles, staggered lobbed missiles, and
# AoE zone strikes — extracted from missile_cruiser.gd (Roman 2026-06-16) so both the
# missile cruiser AND the Shepherd boss's Phase 2 share ONE implementation.
#
# The caller owns cadence + positioning: the cruiser drives the pieces from its
# traverse state machine; a boss can `await MissileSalvo.run_salvo(...)` for a single
# self-contained cycle. Shared pieces: the non-overlapping zone picker, the
# TelegraphCircle + Missile world-space nodes, and the missile glow texture.

const BulletWorld = preload("res://scripts/systems/bullet_world.gd")
const ExplosionFx = preload("res://scripts/effects/explosion_fx.gd")
const Playfield = preload("res://scripts/systems/playfield.gd")

# --- Telegraph circle visual ------------------------------------------------
const TELEGRAPH_COLOR := Color(1.0, 0.15, 0.15, 0.5)  # filled red, alpha 0.5
const TELEGRAPH_PULSE_HZ: float = 3.0
const TELEGRAPH_PULSE_PX: float = 5.0                  # radius pulse amplitude

# Retry cap for rejection-sampling a non-overlapping zone point.
const ZONE_PICK_TRIES: int = 24


# ---- Zone picking ----------------------------------------------------------
# Pick `count` random strike points in the gameplay band (X via Playfield, Y in
# [y_min, y_max]) that are each at least `min_sep` from all previously chosen
# points. Rejection sampling with a retry cap; on cap, keep the best-spread
# candidate so it never loops forever. World coords.
static func pick_zone_points(count: int, y_min: float, y_max: float, min_sep: float) -> Array:
	var points: Array = []
	var sep_sq: float = min_sep * min_sep
	for _i in range(count):
		var best: Vector2 = _rand_zone_point(y_min, y_max)
		var best_min_d: float = _min_dist_sq(best, points)
		if best_min_d >= sep_sq:
			points.append(best)
			continue
		for _try in range(ZONE_PICK_TRIES):
			var cand: Vector2 = _rand_zone_point(y_min, y_max)
			var cand_min_d: float = _min_dist_sq(cand, points)
			if cand_min_d >= sep_sq:
				best = cand
				best_min_d = cand_min_d
				break
			if cand_min_d > best_min_d:
				best = cand
				best_min_d = cand_min_d
		points.append(best)
	return points


static func _rand_zone_point(y_min: float, y_max: float) -> Vector2:
	return Vector2(randf_range(Playfield.X_MIN, Playfield.X_MAX), randf_range(y_min, y_max))


static func _min_dist_sq(p: Vector2, pts: Array) -> float:
	var best: float = INF
	for q_v in pts:
		var q: Vector2 = q_v
		var d: float = p.distance_squared_to(q)
		if d < best:
			best = d
	return best


# ---- In-place AoE detonation ----------------------------------------------
# Detonate an area strike at `world_pos`: every "player"-group Node2D within `radius`
# takes `damage`, then a 1× explosion plays. Shared by Missile._detonate (a lobbed
# missile) AND in-place bombs that never fly (the bombing run). `tree` drives the
# player-group lookup — pass null to skip damage (a dev lab with no player, pure VFX
# tuning). `parent` is the explosion's parent (resolve via BulletWorld for SubViewport
# benches; null = window root, the production default).
static func detonate_aoe(world_pos: Vector2, radius: float, damage: int, tree: SceneTree, parent: Node = null) -> void:
	if tree != null:
		for p in tree.get_nodes_in_group("player"):
			if not (p is Node2D):
				continue
			var pn: Node2D = p as Node2D
			if pn.global_position.distance_to(world_pos) <= radius and pn.has_method("take_damage"):
				pn.take_damage(damage)
	ExplosionFx.play(world_pos, 1.0, true, parent)


# ---- Missile glow texture (built once, shared) -----------------------------
static var _glow_tex: GradientTexture2D = null

static func _ensure_glow_tex() -> void:
	if _glow_tex != null:
		return
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 16
	t.height = 16
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_glow_tex = t


# ---- One-shot awaitable salvo (scripted callers, e.g. a boss) --------------
# Picks zones, shows telegraphs, staggers the missile launches, then waits out the
# last missile's travel + fuse so a caller can gap cleanly between salvos.
# opts keys (all optional): zone_count, telegraph_time, missile_travel_time,
#   fuse_time, aoe_radius, explosion_damage, launch_stagger, zone_y_min, zone_y_max,
#   min_zone_separation, launch (Callable(idx)->Vector2; default host.global_position).
static func run_salvo(host: Node2D, world: Node, opts: Dictionary = {}) -> void:
	if host == null or not is_instance_valid(host) or world == null:
		return
	var tree: SceneTree = host.get_tree()
	if tree == null:
		return
	var zone_count: int = int(opts.get("zone_count", 4))
	var telegraph_time: float = float(opts.get("telegraph_time", 1.2))
	var travel: float = float(opts.get("missile_travel_time", 0.8))
	var fuse: float = float(opts.get("fuse_time", 0.4))
	var radius: float = float(opts.get("aoe_radius", 24.0))
	var damage: int = int(opts.get("explosion_damage", 1))
	var stagger: float = float(opts.get("launch_stagger", 0.12))
	var y_min: float = float(opts.get("zone_y_min", 40.0))
	var y_max: float = float(opts.get("zone_y_max", 240.0))
	var min_sep: float = float(opts.get("min_zone_separation", 56.0))
	var launch_cb: Callable = opts.get("launch", Callable())
	# Optional arc: each missile is lobbed out of the launch point along `launch_forward`
	# for ~`launch_forward_dist` px before curving to its zone (quadratic bezier). 0 dist
	# (default) = a straight lerp — the cruiser is unchanged.
	var forward: Vector2 = opts.get("launch_forward", Vector2.ZERO)
	var forward_dist: float = float(opts.get("launch_forward_dist", 0.0))

	var zones: Array = pick_zone_points(zone_count, y_min, y_max, min_sep)
	var teles: Array = []
	for z in zones:
		var c := TelegraphCircle.new()
		c.setup(z, radius)
		world.add_child(c)
		teles.append({"zone": z, "node": c})
	await tree.create_timer(telegraph_time).timeout
	for i in teles.size():
		if not is_instance_valid(host):
			return
		var t: Dictionary = teles[i]
		var from: Vector2 = launch_cb.call(i) if launch_cb.is_valid() else host.global_position
		var control := Vector2(INF, INF)
		if forward_dist > 0.0 and forward != Vector2.ZERO:
			control = from + forward.normalized() * forward_dist
		var m := Missile.new()
		m.setup(from, t["zone"], travel, fuse, radius, damage, t["node"], control)
		world.add_child(m)
		WeaponSfx.play(tree.root, from, "missile")
		if stagger > 0.0 and i < teles.size() - 1:
			await tree.create_timer(stagger).timeout
	await tree.create_timer(travel + fuse + 0.1).timeout


# ============================================================================
# Telegraph circle — pulsing 50%-transparent filled red disc in world space.
# ============================================================================
class TelegraphCircle extends Node2D:
	var _radius: float = 24.0
	var _pulse_t: float = 0.0

	func setup(world_pos: Vector2, radius: float) -> void:
		global_position = world_pos
		_radius = radius

	func _process(delta: float) -> void:
		_pulse_t += delta
		queue_redraw()

	func _draw() -> void:
		var pulse: float = sin(_pulse_t * TAU * MissileSalvo.TELEGRAPH_PULSE_HZ)
		var r: float = _radius + pulse * MissileSalvo.TELEGRAPH_PULSE_PX
		var a: float = MissileSalvo.TELEGRAPH_COLOR.a * (0.7 + 0.3 * (0.5 + 0.5 * pulse))
		var col := Color(
			MissileSalvo.TELEGRAPH_COLOR.r,
			MissileSalvo.TELEGRAPH_COLOR.g,
			MissileSalvo.TELEGRAPH_COLOR.b,
			a
		)
		draw_circle(Vector2.ZERO, maxf(1.0, r), col)


# ============================================================================
# Missile — flies from launch to UNDER its zone point over travel_time, waits a
# fuse, then explodes: AoE damage to players in radius + ExplosionFx + clears its
# telegraph circle. Trailed by the shared MissileSmokeTrail (mirrors enemy_rocket).
# ============================================================================
class Missile extends Node2D:
	signal detonated

	const CORE_COLOR := Color(1.0, 0.96, 0.35, 1.0)
	const GLOW_COLOR := Color(1.0, 0.9, 0.45, 1.0)
	const CORE_W_LAUNCH: float = 1.0
	const CORE_W_ASCEND: float = 2.0
	const CORE_LEN: float = 4.0
	const ASCEND_START: float = 0.18

	var _from: Vector2 = Vector2.ZERO
	var _to: Vector2 = Vector2.ZERO
	var _travel: float = 0.8
	var _fuse: float = 0.4
	var _radius: float = 24.0
	var _damage: int = 1
	var _telegraph: Node2D = null
	var _control: Vector2 = Vector2(INF, INF)  # quadratic-bezier control; INF = straight
	var _curved: bool = false

	var _t: float = 0.0
	var _arrived: bool = false
	var _fuse_t: float = 0.0
	var _detonated: bool = false
	var _heading: float = 0.0
	var _trail: MissileSmokeTrail = null

	func _ready() -> void:
		var trail: MissileSmokeTrail = MissileSmokeTrail.new()
		trail.flip_drift = (_to.y > _from.y)  # downward missile → smoke lags upward
		BulletWorld.resolve(self, get_tree().root).call_deferred("add_child", trail)
		trail.call_deferred("attach_to", self)
		_trail = trail

	func setup(
		from: Vector2, to: Vector2, travel: float, fuse: float,
		radius: float, damage: int, telegraph: Node2D, control: Vector2 = Vector2(INF, INF)
	) -> void:
		_from = from
		_to = to
		_travel = maxf(0.05, travel)
		_fuse = maxf(0.0, fuse)
		_radius = radius
		_damage = damage
		_telegraph = telegraph
		_control = control
		_curved = not is_inf(control.x)
		global_position = from
		_heading = ((control if _curved else to) - from).angle()

	func _process(delta: float) -> void:
		if _detonated:
			return
		if not _arrived:
			_t += delta
			var u: float = clampf(_t / _travel, 0.0, 1.0)
			var eased: float = 1.0 - pow(1.0 - u, 2.0)
			var prev: Vector2 = global_position
			if _curved:
				# Quadratic bezier launch → control (forward) → zone: lobs out of the
				# launcher, then curves to the target.
				var omt: float = 1.0 - eased
				global_position = _from * (omt * omt) + _control * (2.0 * omt * eased) + _to * (eased * eased)
			else:
				global_position = _from.lerp(_to, eased)
			var step: Vector2 = global_position - prev
			if step.length_squared() > 0.0001:
				_heading = step.angle()
			queue_redraw()
			if u >= 1.0:
				_arrived = true
				_fuse_t = 0.0
		else:
			_fuse_t += delta
			queue_redraw()
			if _fuse_t >= _fuse:
				_detonate()

	func _detonate() -> void:
		if _detonated:
			return
		_detonated = true
		MissileSalvo.detonate_aoe(_to, _radius, _damage, get_tree())
		if _trail != null and is_instance_valid(_trail):
			_trail.attach_to(null)
			_trail = null
		if _telegraph != null and is_instance_valid(_telegraph):
			_telegraph.queue_free()
		detonated.emit()
		queue_free()

	func _draw() -> void:
		if _detonated:
			return
		if not _arrived:
			var u: float = clampf(_t / _travel, 0.0, 1.0)
			var asc: float = clampf((u - ASCEND_START) / (1.0 - ASCEND_START), 0.0, 1.0)
			var core_w: float = lerpf(CORE_W_LAUNCH, CORE_W_ASCEND, asc)
			var dir := Vector2.RIGHT.rotated(_heading)
			MissileSalvo._ensure_glow_tex()
			var flick: float = 0.65 + 0.35 * randf()
			var glow_half: float = (core_w + 1.5) * flick
			var gcol := Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.5 * flick)
			draw_texture_rect(
				MissileSalvo._glow_tex,
				Rect2(Vector2(-glow_half, -glow_half), Vector2(glow_half * 2.0, glow_half * 2.0)),
				false, gcol
			)
			draw_line(dir * (-CORE_LEN * 0.5), dir * (CORE_LEN * 0.5), CORE_COLOR, core_w)
		else:
			var pulse: float = 0.5 + 0.5 * sin(_fuse_t * 30.0)
			draw_circle(Vector2.ZERO, 2.0 + pulse * 1.5, Color(1.0, 0.9, 0.4, 0.9))
